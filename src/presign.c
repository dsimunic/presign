#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>
#include <limits.h>
#include "version.h"

#ifdef USE_OPENSSL
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <openssl/evp.h>
#elif defined(USE_MBEDTLS)
#include <mbedtls/md.h>
#include <mbedtls/sha256.h>
#endif

#define MAX_URL_LEN 4096
#define MAX_PATH_LEN 2048
#define MAX_HEADER_LEN 1024
#define MAX_HEADERS 32
#define MAX_ENV_VAR_LEN 512

typedef struct {
    char key[MAX_HEADER_LEN];
    char value[MAX_HEADER_LEN];
} header_t;

typedef struct {
    char service[16];
    char method[16];
    char region[64];
    char bucket_url[MAX_URL_LEN];
    char path[MAX_PATH_LEN];
    int expire_min;
    header_t headers[MAX_HEADERS];
    int header_count;
    char now_override[32];
} presign_args_t;

int url_encode_component(const char *src, char *dest, size_t dest_size, int keep_slash) {
    const char *hex = "0123456789ABCDEF";
    char *d = dest;
    size_t remaining = dest_size;

    if (dest_size == 0) {
        return -1;
    }

    while (*src) {
        unsigned char c = (unsigned char)*src;
        size_t needed = 0;

        if ((c >= 'A' && c <= 'Z') ||
            (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') ||
            c == '-' || c == '_' || c == '.' || c == '~' ||
            (keep_slash && c == '/')) {
            needed = 1;
        } else {
            needed = 3;
        }

        if (needed >= remaining) {
            return -1;
        }

        if (needed == 1) {
            *d++ = (char)c;
            remaining--;
        } else {
            *d++ = '%';
            *d++ = hex[(c >> 4) & 0xF];
            *d++ = hex[c & 0xF];
            remaining -= 3;
        }

        src++;
    }

    if (remaining == 0) {
        return -1;
    }

    *d = '\0';
    return 0;
}

void to_hex(const unsigned char *data, int len, char *hex) {
    const char *hex_chars = "0123456789abcdef";
    for (int i = 0; i < len; i++) {
        hex[i * 2] = hex_chars[(data[i] >> 4) & 0xF];
        hex[i * 2 + 1] = hex_chars[data[i] & 0xF];
    }
    hex[len * 2] = '\0';
}

void hmac_sha256(const char *key, int key_len, const char *data, int data_len, unsigned char *result) {
#ifdef USE_OPENSSL
    unsigned int result_len;
    HMAC(EVP_sha256(), key, key_len, (unsigned char*)data, data_len, result, &result_len);
#elif defined(USE_MBEDTLS)
    const mbedtls_md_info_t *md_info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_hmac(md_info, (const unsigned char*)key, key_len, (const unsigned char*)data, data_len, result);
#endif
}

void sha256_hash(const char *data, int data_len, unsigned char *result) {
#ifdef USE_OPENSSL
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) {
        fprintf(stderr, "Error: Failed to create EVP digest context\n");
        exit(1);
    }

    if (!EVP_DigestInit_ex(ctx, EVP_sha256(), NULL)) {
        fprintf(stderr, "Error: Failed to initialize SHA256 digest\n");
        EVP_MD_CTX_free(ctx);
        exit(1);
    }

    if (!EVP_DigestUpdate(ctx, data, data_len)) {
        fprintf(stderr, "Error: Failed to update SHA256 digest\n");
        EVP_MD_CTX_free(ctx);
        exit(1);
    }

    if (!EVP_DigestFinal_ex(ctx, result, NULL)) {
        fprintf(stderr, "Error: Failed to finalize SHA256 digest\n");
        EVP_MD_CTX_free(ctx);
        exit(1);
    }

    EVP_MD_CTX_free(ctx);
#elif defined(USE_MBEDTLS)
    mbedtls_sha256((const unsigned char*)data, data_len, result, 0);
#endif
}

void derive_signing_key(const char *secret, const char *date, const char *region, const char *service, unsigned char *signing_key) {
    char aws_secret[MAX_ENV_VAR_LEN];
    snprintf(aws_secret, sizeof(aws_secret), "AWS4%s", secret);

    unsigned char date_key[32];
    hmac_sha256(aws_secret, strlen(aws_secret), date, strlen(date), date_key);

    unsigned char date_region_key[32];
    hmac_sha256((char*)date_key, 32, region, strlen(region), date_region_key);

    unsigned char date_region_service_key[32];
    hmac_sha256((char*)date_region_key, 32, service, strlen(service), date_region_service_key);

    hmac_sha256((char*)date_region_service_key, 32, "aws4_request", (int)strlen("aws4_request"), signing_key);
}

int compare_headers(const void *a, const void *b) {
    const header_t *ha = (const header_t *)a;
    const header_t *hb = (const header_t *)b;
    return strcmp(ha->key, hb->key);
}

void generate_presigned_url(presign_args_t *args) {
    char *access_key = getenv("AWS_ACCESS_KEY_ID");
    char *secret_key = getenv("AWS_SECRET_ACCESS_KEY");
    const char *session_token = getenv("AWS_SESSION_TOKEN");

    if (!access_key || !secret_key) {
        fprintf(stderr, "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set\n");
        exit(1);
    }

    if (strlen(access_key) >= MAX_ENV_VAR_LEN) {
        fprintf(stderr, "Error: AWS_ACCESS_KEY_ID too long (max %d chars)\n", MAX_ENV_VAR_LEN - 1);
        exit(1);
    }

    // Validate access key doesn't contain format specifiers
    if (strchr(access_key, '%') != NULL) {
        fprintf(stderr, "Error: AWS_ACCESS_KEY_ID contains invalid characters\n");
        exit(1);
    }

    if (strlen(secret_key) >= MAX_ENV_VAR_LEN) {
        fprintf(stderr, "Error: AWS_SECRET_ACCESS_KEY too long (max %d chars)\n", MAX_ENV_VAR_LEN - 1);
        exit(1);
    }

    if (strlen(secret_key) == 0 || strlen(secret_key) > 512) {
        fprintf(stderr, "Error: AWS_SECRET_ACCESS_KEY invalid length (1-512 chars)\n");
        exit(1);
    }

    time_t now;
    struct tm *utc_tm;

    if (strlen(args->now_override) > 0) {
        struct tm tm_override = {0};
        if (strptime(args->now_override, "%Y-%m-%dT%H:%M:%SZ", &tm_override) == NULL) {
            fprintf(stderr, "Error: Invalid --now format. Use YYYY-MM-DDTHH:MM:SSZ\n");
            exit(1);
        }
        
        #ifdef _WIN32
            now = _mkgmtime(&tm_override);
        #else
            now = timegm(&tm_override);
        #endif
        
        if (now == (time_t)-1) {
            fprintf(stderr, "Error: Invalid time conversion\n");
            exit(1);
        }
        
        utc_tm = gmtime(&now);
    } else {
        now = time(NULL);
        utc_tm = gmtime(&now);
    }

    char date_stamp[16];
    char datetime[32];
    strftime(date_stamp, sizeof(date_stamp), "%Y%m%d", utc_tm);
    strftime(datetime, sizeof(datetime), "%Y%m%dT%H%M%SZ", utc_tm);

    char host[256];
    char *url_start = strstr(args->bucket_url, "://");
    if (!url_start) {
        fprintf(stderr, "Error: Invalid bucket URL format\n");
        exit(1);
    }
    url_start += 3;
    char *path_start = strchr(url_start, '/');
    if (path_start) {
        size_t host_len = (size_t)(path_start - url_start);
        if (host_len >= sizeof(host)) {
            fprintf(stderr, "Error: Bucket host too long (max %zu chars)\n", sizeof(host) - 1);
            exit(1);
        }
        strncpy(host, url_start, host_len);
        host[host_len] = '\0';
    } else {
        size_t host_len = strlen(url_start);
        if (host_len >= sizeof(host)) {
            fprintf(stderr, "Error: Bucket host too long (max %zu chars)\n", sizeof(host) - 1);
            exit(1);
        }
        strncpy(host, url_start, sizeof(host) - 1);
        host[sizeof(host) - 1] = '\0';
    }

    char canonical_uri[MAX_PATH_LEN];
    if (args->path[0] != '/') {
        canonical_uri[0] = '/';
        if (url_encode_component(args->path, canonical_uri + 1, sizeof(canonical_uri) - 1, 1) != 0) {
            fprintf(stderr, "Error: Encoded PATH exceeds maximum length\n");
            exit(1);
        }
    } else {
        if (url_encode_component(args->path, canonical_uri, sizeof(canonical_uri), 1) != 0) {
            fprintf(stderr, "Error: Encoded PATH exceeds maximum length\n");
            exit(1);
        }
    }

    char credential_scope[256];
    snprintf(credential_scope, sizeof(credential_scope), "%s/%s/%s/aws4_request",
             date_stamp, args->region, args->service);

    char credential[512];
    snprintf(credential, sizeof(credential), "%s/%s", access_key, credential_scope);

    char canonical_headers[MAX_HEADER_LEN * MAX_HEADERS];
    canonical_headers[0] = '\0';

    header_t all_headers[MAX_HEADERS + 1];
    strcpy(all_headers[0].key, "host");
    strcpy(all_headers[0].value, host);
    int total_headers = 1;

    for (int i = 0; i < args->header_count; i++) {
        strcpy(all_headers[total_headers].key, args->headers[i].key);
        strcpy(all_headers[total_headers].value, args->headers[i].value);
        total_headers++;
    }

    qsort(all_headers, total_headers, sizeof(header_t), compare_headers);

    for (int i = 0; i < total_headers; i++) {
        char lower_key[MAX_HEADER_LEN];
        for (int j = 0; all_headers[i].key[j]; j++) {
            unsigned char key_ch = (unsigned char)all_headers[i].key[j];
            lower_key[j] = (char)tolower(key_ch);
        }
        lower_key[strlen(all_headers[i].key)] = '\0';

        char trimmed_value[MAX_HEADER_LEN];
        strncpy(trimmed_value, all_headers[i].value, MAX_HEADER_LEN - 1);
        trimmed_value[MAX_HEADER_LEN - 1] = '\0';

        char *start = trimmed_value;
        while (*start && isspace((unsigned char)*start)) {
            start++;
        }
        size_t start_len = strlen(start);
        if (start_len > 0) {
            char *end = start + start_len - 1;
            while (end > start && isspace((unsigned char)*end)) {
                end--;
            }
            *(end + 1) = '\0';
        }

        size_t canonical_len = strlen(canonical_headers);
        size_t key_len = strlen(lower_key);
        size_t value_len = strlen(start);
        
        // Check for integer overflow
        if (key_len > SIZE_MAX - 1 || value_len > SIZE_MAX - 1 ||
            key_len + 1 > SIZE_MAX - (value_len + 1)) {
            fprintf(stderr, "Error: Header too long - integer overflow\n");
            exit(1);
        }
        
        size_t needed_len = key_len + 1 + value_len + 1;
        if (canonical_len > SIZE_MAX - needed_len ||
            canonical_len + needed_len > sizeof(canonical_headers)) {
            fprintf(stderr, "Error: Too many/large headers - canonical headers buffer overflow\n");
            exit(1);
        }

        strcat(canonical_headers, lower_key);
        strcat(canonical_headers, ":");
        strcat(canonical_headers, start);
        strcat(canonical_headers, "\n");
    }

    char signed_headers_final[MAX_HEADER_LEN];
    signed_headers_final[0] = '\0';

    for (int i = 0; i < total_headers; i++) {
        if (i > 0) {
            if (strlen(signed_headers_final) + 1 >= MAX_HEADER_LEN) {
                fprintf(stderr, "Error: Too many headers - signed headers final buffer overflow\n");
                exit(1);
            }
            strcat(signed_headers_final, ";");
        }

        size_t signed_headers_final_len = strlen(signed_headers_final);
        size_t key_len = strlen(all_headers[i].key);
        if (signed_headers_final_len + key_len >= MAX_HEADER_LEN) {
            fprintf(stderr, "Error: Header names too long - signed headers final buffer overflow\n");
            exit(1);
        }

        for (int j = 0; all_headers[i].key[j]; j++) {
            unsigned char key_ch = (unsigned char)all_headers[i].key[j];
            signed_headers_final[signed_headers_final_len] = (char)tolower(key_ch);
            signed_headers_final_len++;
        }
        signed_headers_final[signed_headers_final_len] = '\0';
    }

    char credential_encoded[sizeof(credential) * 3];
    if (url_encode_component(credential, credential_encoded, sizeof(credential_encoded), 0) != 0) {
        fprintf(stderr, "Error: Encoded credential exceeds maximum length\n");
        exit(1);
    }

    char datetime_encoded[sizeof(datetime) * 3];
    if (url_encode_component(datetime, datetime_encoded, sizeof(datetime_encoded), 0) != 0) {
        fprintf(stderr, "Error: Encoded datetime exceeds maximum length\n");
        exit(1);
    }

    char signed_headers_encoded[MAX_HEADER_LEN * 3];
    if (url_encode_component(signed_headers_final, signed_headers_encoded, sizeof(signed_headers_encoded), 0) != 0) {
        fprintf(stderr, "Error: Encoded signed headers exceeds maximum length\n");
        exit(1);
    }

    char query_params[MAX_URL_LEN];
    int query_written = snprintf(query_params, sizeof(query_params),
             "X-Amz-Algorithm=AWS4-HMAC-SHA256&"
             "X-Amz-Credential=%s&"
             "X-Amz-Date=%s&"
             "X-Amz-Expires=%d&"
             "X-Amz-SignedHeaders=%s",
             credential_encoded, datetime_encoded, args->expire_min * 60, signed_headers_encoded);
    if (query_written < 0 || (size_t)query_written >= sizeof(query_params)) {
        fprintf(stderr, "Error: Query parameters too long\n");
        exit(1);
    }

    if (session_token) {
        char encoded_token[MAX_ENV_VAR_LEN * 3];
        if (strlen(session_token) >= MAX_ENV_VAR_LEN) {
            fprintf(stderr, "Error: AWS_SESSION_TOKEN too long (max %d chars)\n", MAX_ENV_VAR_LEN - 1);
            exit(1);
        }
        if (url_encode_component(session_token, encoded_token, sizeof(encoded_token), 0) != 0) {
            fprintf(stderr, "Error: Encoded session token exceeds maximum length\n");
            exit(1);
        }

        size_t query_len = strlen(query_params);
        size_t token_prefix_len = strlen("&X-Amz-Security-Token=");
        size_t encoded_len = strlen(encoded_token);

        if (query_len + token_prefix_len + encoded_len >= sizeof(query_params)) {
            fprintf(stderr, "Error: Query parameters too long - buffer overflow\n");
            exit(1);
        }

        strcat(query_params, "&X-Amz-Security-Token=");
        strcat(query_params, encoded_token);
    }

    char canonical_request[MAX_URL_LEN * 2];
    if (snprintf(canonical_request, sizeof(canonical_request),
             "%s\n%s\n%s\n%s\n%s\nUNSIGNED-PAYLOAD",
             args->method, canonical_uri, query_params, canonical_headers, signed_headers_final) < 0) {
        fprintf(stderr, "Error: Failed to format canonical request\n");
        exit(1);
    }
    unsigned char canonical_hash[32];
    sha256_hash(canonical_request, strlen(canonical_request), canonical_hash);
    char canonical_hash_hex[65];
    to_hex(canonical_hash, 32, canonical_hash_hex);

    char string_to_sign[1024];
    snprintf(string_to_sign, sizeof(string_to_sign),
             "AWS4-HMAC-SHA256\n%s\n%s\n%s",
             datetime, credential_scope, canonical_hash_hex);

    unsigned char signing_key[32];
    derive_signing_key(secret_key, date_stamp, args->region, args->service, signing_key);

    unsigned char signature[32];
    hmac_sha256((char*)signing_key, 32, string_to_sign, strlen(string_to_sign), signature);
    char signature_hex[65];
    to_hex(signature, 32, signature_hex);

    if (getenv("PRESIGN_DEBUG")) {
        fprintf(stderr, "DEBUG canonical_request:\n%s\n", canonical_request);
        fprintf(stderr, "DEBUG canonical_hash:%s\n", canonical_hash_hex);
        fprintf(stderr, "DEBUG string_to_sign:\n%s\n", string_to_sign);
        fprintf(stderr, "DEBUG credential_scope:%s\n", credential_scope);
        fprintf(stderr, "DEBUG signed_headers:%s\n", signed_headers_final);
        fprintf(stderr, "DEBUG signature:%s\n", signature_hex);
        fprintf(stderr, "DEBUG query_params:%s\n", query_params);
    }

    printf("%s%s?%s&X-Amz-Signature=%s\n",
           args->bucket_url, canonical_uri, query_params, signature_hex);
}

void print_version(void) {
    printf("presign %s\n", PRESIGN_VERSION);
}

void print_usage(const char *prog_name) {
    printf("Usage: %s SERVICE METHOD [REGION] [ENDPOINT] S3_PATH EXPIRE_MIN [options]\n", prog_name);
    printf("\nPositional parameters:\n");
    printf("  SERVICE     constant, always 's3'\n");
    printf("  METHOD      GET | PUT | DELETE (case insensitive)\n");
    printf("  REGION      overrides S3_REGION environment variable (optional)\n");
    printf("  ENDPOINT    overrides S3_ENDPOINT environment variable (optional)\n");
    printf("  S3_PATH     bucket and key path (e.g., bucket/object.txt)\n");
    printf("  EXPIRE_MIN  expiration time in minutes (1 to 10080)\n");
    printf("\nOptions:\n");
    printf("  --header 'Key: Value'  Add header to be signed (can be used multiple times)\n");
    printf("  --now TIMESTAMP        Override current time (format: 2025-09-25T08:40:00Z)\n");
    printf("  --version, -v          Show version information\n");
    printf("\nEnvironment variables:\n");
    printf("  AWS_ACCESS_KEY_ID      required\n");
    printf("  AWS_SECRET_ACCESS_KEY  required\n");
    printf("  AWS_SESSION_TOKEN      optional, for temporary credentials\n");
    printf("  S3_REGION              default for REGION\n");
    printf("  S3_ENDPOINT            default for ENDPOINT (e.g., https://s3.fr-par.scw.cloud)\n");
}

int main(int argc, char *argv[]) {
    // Handle version argument before other processing
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
            print_version();
            return 0;
        }
    }

    if (argc < 5) {
        print_usage(argv[0]);
        return 1;
    }

    presign_args_t args = {0};

    int first_option = argc;
    for (int j = 3; j < argc; j++) {
        if (strncmp(argv[j], "--", 2) == 0) {
            first_option = j;
            break;
        }
    }

    int positional_count = first_option - 3;
    if (positional_count < 2 || positional_count > 4) {
        fprintf(stderr, "Error: Invalid positional arguments\n");
        print_usage(argv[0]);
        return 1;
    }

    const char *region_cli = NULL;
    const char *endpoint_cli = NULL;

    if (positional_count >= 3) {
        region_cli = argv[3];
    }
    if (positional_count == 4) {
        endpoint_cli = argv[4];
    }

    const char *path_arg = argv[first_option - 2];
    const char *expire_arg = argv[first_option - 1];

    if (strlen(argv[1]) >= sizeof(args.service)) {
        fprintf(stderr, "Error: Service name too long (max %zu chars)\n", sizeof(args.service) - 1);
        return 1;
    }
    if (strlen(argv[2]) >= sizeof(args.method)) {
        fprintf(stderr, "Error: Method name too long (max %zu chars)\n", sizeof(args.method) - 1);
        return 1;
    }
    if (strlen(path_arg) >= sizeof(args.path)) {
        fprintf(stderr, "Error: Path too long (max %zu chars)\n", sizeof(args.path) - 1);
        return 1;
    }

    strncpy(args.service, argv[1], sizeof(args.service) - 1);
    args.service[sizeof(args.service) - 1] = '\0';
    strncpy(args.method, argv[2], sizeof(args.method) - 1);
    args.method[sizeof(args.method) - 1] = '\0';
    strncpy(args.path, path_arg, sizeof(args.path) - 1);
    args.path[sizeof(args.path) - 1] = '\0';

    const char *region_env = getenv("S3_REGION");
    const char *region_value = region_cli ? region_cli : region_env;
    if (!region_value) {
        fprintf(stderr, "Error: REGION is required (provide CLI argument or set S3_REGION)\n");
        return 1;
    }
    if (strlen(region_value) >= sizeof(args.region)) {
        fprintf(stderr, "Error: Region name too long (max %zu chars)\n", sizeof(args.region) - 1);
        return 1;
    }
    strncpy(args.region, region_value, sizeof(args.region) - 1);
    args.region[sizeof(args.region) - 1] = '\0';

    const char *endpoint_env = getenv("S3_ENDPOINT");
    const char *endpoint_value = endpoint_cli ? endpoint_cli : endpoint_env;
    if (!endpoint_value) {
        fprintf(stderr, "Error: ENDPOINT is required (provide CLI argument or set S3_ENDPOINT)\n");
        return 1;
    }
    if (strlen(endpoint_value) >= sizeof(args.bucket_url)) {
        fprintf(stderr, "Error: Endpoint too long (max %zu chars)\n", sizeof(args.bucket_url) - 1);
        return 1;
    }
    strncpy(args.bucket_url, endpoint_value, sizeof(args.bucket_url) - 1);
    args.bucket_url[sizeof(args.bucket_url) - 1] = '\0';
    size_t endpoint_len = strlen(args.bucket_url);
    while (endpoint_len > 0 && args.bucket_url[endpoint_len - 1] == '/') {
        args.bucket_url[endpoint_len - 1] = '\0';
        endpoint_len--;
    }

    char *endptr = NULL;
    long expire_long = strtol(expire_arg, &endptr, 10);
    if (*expire_arg == '\0' || *endptr != '\0') {
        fprintf(stderr, "Error: EXPIRE_MIN must be an integer\n");
        return 1;
    }
    if (expire_long > INT_MAX) {
        fprintf(stderr, "Error: EXPIRE_MIN too large\n");
        return 1;
    }
    args.expire_min = (int)expire_long;

    size_t service_len = strlen(args.service);
    for (size_t i = 0; i < service_len; i++) {
        unsigned char c = (unsigned char)args.service[i];
        args.service[i] = (char)tolower(c);
    }
    size_t method_len = strlen(args.method);
    for (size_t i = 0; i < method_len; i++) {
        unsigned char c = (unsigned char)args.method[i];
        args.method[i] = (char)toupper(c);
    }

    if (strcmp(args.service, "s3") != 0) {
        fprintf(stderr, "Error: SERVICE must be 's3'\n");
        return 1;
    }

    if (strcmp(args.method, "GET") != 0 && strcmp(args.method, "PUT") != 0 && strcmp(args.method, "DELETE") != 0) {
        fprintf(stderr, "Error: METHOD must be GET, PUT, or DELETE\n");
        return 1;
    }

    if (args.expire_min <= 0 || args.expire_min > 10080) {
        fprintf(stderr, "Error: EXPIRE_MIN must be between 1 and 10080 (7 days)\n");
        return 1;
    }

    for (int i = first_option; i < argc; i++) {
        if (strcmp(argv[i], "--header") == 0 && i + 1 < argc) {
            if (args.header_count >= MAX_HEADERS) {
                fprintf(stderr, "Error: Too many headers (max %d)\n", MAX_HEADERS);
                return 1;
            }

            char *colon = strchr(argv[i + 1], ':');
            if (!colon) {
                fprintf(stderr, "Error: Invalid header format. Use 'Key: Value'\n");
                return 1;
            }

            int key_len = colon - argv[i + 1];
            if (key_len >= MAX_HEADER_LEN) {
                fprintf(stderr, "Error: Header key too long (max %d chars)\n", MAX_HEADER_LEN - 1);
                return 1;
            }
            if (strlen(colon + 1) >= MAX_HEADER_LEN) {
                fprintf(stderr, "Error: Header value too long (max %d chars)\n", MAX_HEADER_LEN - 1);
                return 1;
            }

            strncpy(args.headers[args.header_count].key, argv[i + 1], key_len);
            args.headers[args.header_count].key[key_len] = '\0';

            strncpy(args.headers[args.header_count].value, colon + 1, MAX_HEADER_LEN - 1);
            args.headers[args.header_count].value[MAX_HEADER_LEN - 1] = '\0';
            if (args.headers[args.header_count].value[0] == ' ') {
                memmove(args.headers[args.header_count].value, args.headers[args.header_count].value + 1,
                       strlen(args.headers[args.header_count].value));
            }

            // Validate header value for control characters
            for (size_t j = 0; j < strlen(args.headers[args.header_count].value); j++) {
                if ((unsigned char)args.headers[args.header_count].value[j] < 32 && 
                    args.headers[args.header_count].value[j] != '\t') {
                    fprintf(stderr, "Error: Header value contains control characters\n");
                    return 1;
                }
            }

            args.header_count++;
            i++;
        } else if (strcmp(argv[i], "--now") == 0 && i + 1 < argc) {
            if (strlen(argv[i + 1]) >= sizeof(args.now_override)) {
                fprintf(stderr, "Error: Timestamp too long (max %zu chars)\n", sizeof(args.now_override) - 1);
                return 1;
            }
            strncpy(args.now_override, argv[i + 1], sizeof(args.now_override) - 1);
            args.now_override[sizeof(args.now_override) - 1] = '\0';
            i++;
        } else {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    generate_presigned_url(&args);
    return 0;
}
