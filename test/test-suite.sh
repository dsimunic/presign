#!/bin/bash

# Fuzz Testing Suite for Presign Utility
# Tests the utility with malformed, oversized, and edge-case inputs

echo "==============================================="
echo "🐛 PRESIGN UTILITY - FUZZ TESTING SUITE"
echo "==============================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRESIGN_BIN="$SCRIPT_DIR/../bin/presign"

if [ ! -x "$PRESIGN_BIN" ]; then
    echo "${RED}Error:${NC} presign binary not found at $PRESIGN_BIN" >&2
    echo "Build it with 'make' from the repository root." >&2
    exit 1
fi

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Utility: build large strings even when python3 is unavailable
repeat_char() {
    local char="$1"
    local count="$2"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$char" "$count" <<'PY'
import sys
char = sys.argv[1]
count = int(sys.argv[2])
sys.stdout.write(char * count)
PY
        return
    fi

    printf "%0.s$char" $(seq 1 "$count")
}

# Test function that expects the program to NOT crash (should return non-zero but not segfault)
run_fuzz_test() {
    local test_name="$1"
    local expected_behavior="$2"
    shift 2
    local args=("$@")

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing: $test_name ... "

    # Run the command and capture both exit code and any crash signals
    timeout 5s "$PRESIGN_BIN" "${args[@]}" >/dev/null 2>&1
    exit_code=$?

    # Check if program crashed (segfault = 139, timeout = 124)
    if [ $exit_code -eq 124 ]; then
        echo -e "${RED}TIMEOUT (HUNG)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    elif [ $exit_code -ge 128 ]; then
        echo -e "${RED}CRASH (SIGNAL ${exit_code})${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    elif [ $exit_code -eq 0 ]; then
        if [ "$expected_behavior" = "should_fail" ]; then
            echo -e "${RED}UNEXPECTED SUCCESS${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        else
            echo -e "${GREEN}PASS${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        fi
    else
        # Non-zero exit (expected for invalid input)
        if [ "$expected_behavior" = "should_fail" ]; then
            echo -e "${GREEN}PASS (GRACEFUL FAILURE)${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo -e "${YELLOW}UNEXPECTED FAILURE${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi
}


# Set up environment (minimal valid creds for tests that might get that far)
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

echo "🎯 Starting fuzz tests..."
echo ""

DEFAULT_REGION="fr-par"
DEFAULT_ENDPOINT="https://s3.example"
DEFAULT_BUCKET="example-bucket"

# ============================================================================
echo "=== 0. FUNCTIONAL HAPPY PATHS ==="
echo ""

run_fuzz_test "Valid GET request" "should_pass" "s3" "GET" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/documents/report.txt" "60"
run_fuzz_test "Valid PUT request" "should_pass" "s3" "PUT" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/uploads/data.json" "45" "--header" "Content-Type: application/json" "--header" "x-amz-meta-note: unit-test"
run_fuzz_test "Valid DELETE with time override" "should_pass" "s3" "DELETE" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/archive/old.log" "15" "--now" "2025-09-25T10:00:00Z"
run_fuzz_test "Valid GET with special characters" "should_pass" "s3" "GET" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/folder with spaces/file[1] & data+.txt" "30"

export AWS_SESSION_TOKEN=$(repeat_char "A" 511)
run_fuzz_test "Maximum session token length" "should_pass" "s3" "GET" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/test-object" "20"

export AWS_SESSION_TOKEN="token+with/special=chars&more%stuff"
run_fuzz_test "Session token with special characters" "should_pass" "s3" "PUT" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/uploads/résumé & cv [final].pdf" "25"

export AWS_SESSION_TOKEN=$(repeat_char "A" 600)
run_fuzz_test "Oversized session token" "should_fail" "s3" "GET" "$DEFAULT_REGION" "$DEFAULT_ENDPOINT" "$DEFAULT_BUCKET/path" "15"

unset AWS_SESSION_TOKEN

# ============================================================================
echo "=== 1. PARAMETER COUNT FUZZING ==="
echo ""

run_fuzz_test "No arguments" "should_fail"
run_fuzz_test "Too few arguments (1)" "should_fail" "s3"
run_fuzz_test "Too few arguments (2)" "should_fail" "s3" "GET"
run_fuzz_test "Too few arguments (3)" "should_fail" "s3" "GET" "region"
run_fuzz_test "Too few arguments (4)" "should_fail" "s3" "GET" "region"
run_fuzz_test "Too few arguments (5)" "should_fail" "s3" "GET" "region" "https://endpoint"

# ============================================================================
echo ""
echo "=== 2. OVERSIZED PARAMETER FUZZING ==="
echo ""

# Create various oversized strings
HUGE_STRING=$(repeat_char "A" 12000)
MEDIUM_STRING=$(repeat_char "B" 2000)
SMALL_OVERSIZED=$(repeat_char "C" 500)

run_fuzz_test "Huge service name" "should_fail" "$HUGE_STRING" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Huge method name" "should_fail" "s3" "$HUGE_STRING" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Huge region name" "should_fail" "s3" "GET" "$HUGE_STRING" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Huge endpoint" "should_fail" "s3" "GET" "region" "$HUGE_STRING" "bucket/path" "15"
run_fuzz_test "Huge path" "should_fail" "s3" "GET" "region" "https://endpoint" "$HUGE_STRING" "15"

# ============================================================================
echo ""
echo "=== 3. MALFORMED PARAMETER FUZZING ==="
echo ""

# Invalid service names
run_fuzz_test "Invalid service (empty)" "should_fail" "" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid service (random)" "should_fail" "xyz123" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid service (number)" "should_fail" "123" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid service (symbols)" "should_fail" "!@#$" "GET" "region" "https://endpoint" "bucket/path" "15"

# Invalid methods
run_fuzz_test "Invalid method (empty)" "should_fail" "s3" "" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid method (random)" "should_fail" "s3" "INVALID" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid method (number)" "should_fail" "s3" "123" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid method (symbols)" "should_fail" "s3" "G!T" "region" "https://endpoint" "bucket/path" "15"

# Invalid URLs
run_fuzz_test "Invalid endpoint (no protocol)" "should_fail" "s3" "GET" "region" "bucket.com" "bucket/path" "15"
run_fuzz_test "Invalid endpoint (empty)" "should_fail" "s3" "GET" "region" "" "bucket/path" "15"
run_fuzz_test "Invalid endpoint (malformed)" "should_pass" "s3" "GET" "region" "ht!tp://endpoint" "bucket/path" "15"
run_fuzz_test "Invalid endpoint (no host)" "should_fail" "s3" "GET" "region" "https://" "bucket/path" "15"

# Invalid expiration times
run_fuzz_test "Invalid expiry (zero)" "should_fail" "s3" "GET" "region" "https://endpoint" "bucket/path" "0"
run_fuzz_test "Invalid expiry (negative)" "should_fail" "s3" "GET" "region" "https://endpoint" "bucket/path" "-5"
run_fuzz_test "Invalid expiry (too large)" "should_fail" "s3" "GET" "region" "https://endpoint" "bucket/path" "999999"
run_fuzz_test "Invalid expiry (non-number)" "should_fail" "s3" "GET" "region" "https://endpoint" "bucket/path" "abc"
run_fuzz_test "Invalid expiry (float)" "should_fail" "s3" "GET" "region" "https://endpoint" "bucket/path" "15.5"

# ============================================================================
echo ""
echo "=== 4. SPECIAL CHARACTER FUZZING ==="
echo ""

# Null bytes and control characters (these should be handled gracefully)
run_fuzz_test "Null byte in service" "should_fail" "s3\x00" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Control chars in method" "should_fail" "s3" "GET\t\n\r" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "Unicode in region" "should_pass" "s3" "GET" "région-français" "https://endpoint" "bucket/path" "15"

# Injection attempts
run_fuzz_test "Command injection in service" "should_fail" "s3; rm -rf /" "GET" "region" "https://endpoint" "bucket/path" "15"
run_fuzz_test "SQL injection in path" "should_pass" "s3" "GET" "region" "https://endpoint" "'; DROP TABLE users; --" "15"

# Path traversal attempts
run_fuzz_test "Path traversal (simple)" "should_pass" "s3" "GET" "region" "https://bucket.com" "../../../etc/passwd" "15"
run_fuzz_test "Path traversal (encoded)" "should_pass" "s3" "GET" "region" "https://bucket.com" "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd" "15"

# ============================================================================
echo ""
echo "=== 5. OPTION FUZZING ==="
echo ""

# Invalid options
run_fuzz_test "Unknown option" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--invalid-option"
run_fuzz_test "Malformed header option" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header"
run_fuzz_test "Header without colon" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header" "InvalidHeader"
run_fuzz_test "Empty header value" "should_pass" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header" "Content-Type:"

# Oversized headers
run_fuzz_test "Huge header name" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header" "${MEDIUM_STRING}: value"
run_fuzz_test "Huge header value" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header" "Content-Type: ${MEDIUM_STRING}"
run_fuzz_test "Header key parse overflow" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--header" "${HUGE_STRING}: boom"

# Too many headers
MANY_HEADERS=()
for i in {1..50}; do
    MANY_HEADERS+=("--header" "Header-$i: value-$i")
done
run_fuzz_test "Too many headers" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "${MANY_HEADERS[@]}"

# Invalid timestamp formats
run_fuzz_test "Invalid timestamp format" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--now" "invalid-date"
run_fuzz_test "Malformed ISO timestamp" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--now" "2025-13-45T25:70:00Z"
run_fuzz_test "Empty timestamp" "should_pass" "s3" "GET" "region" "https://bucket.com" "path" "15" "--now" ""

# ============================================================================
echo ""
echo "=== 5b. REGRESSION GUARDS FOR PREVIOUS BUGS ==="
echo ""

HUGE_NOW=$(repeat_char "0" 200)
LONG_HEADER_KEY=$(repeat_char "H" 200)
LARGE_HEADER_VALUE=$(repeat_char "V" 1022)

declare -a SIGNED_HEADER_OVERFLOW_HEADERS=()
for i in $(seq 1 6); do
    suffix=$(printf '%02d' "$i")
    SIGNED_HEADER_OVERFLOW_HEADERS+=("--header" "${LONG_HEADER_KEY}${suffix}: value${i}")
done

declare -a CANONICAL_HEADER_OVERFLOW_HEADERS=()
for i in $(seq -w 1 32); do
    CANONICAL_HEADER_OVERFLOW_HEADERS+=("--header" "k${i}: $LARGE_HEADER_VALUE")
done

run_fuzz_test "Service buffer overflow" "should_fail" "$HUGE_STRING" "GET" "region" "https://bucket.com" "path" "15"
run_fuzz_test "Method buffer overflow" "should_fail" "s3" "$HUGE_STRING" "region" "https://bucket.com" "path" "15"
run_fuzz_test "Region buffer overflow" "should_fail" "s3" "GET" "$HUGE_STRING" "https://bucket.com" "path" "15"
run_fuzz_test "Bucket URL buffer overflow" "should_fail" "s3" "GET" "region" "$HUGE_STRING" "path" "15"
run_fuzz_test "Path buffer overflow" "should_fail" "s3" "GET" "region" "https://bucket.com" "$HUGE_STRING" "15"
run_fuzz_test "Now override buffer overflow" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "--now" "$HUGE_NOW"
run_fuzz_test "Signed headers buffer overflow" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "${SIGNED_HEADER_OVERFLOW_HEADERS[@]}"
run_fuzz_test "Canonical headers buffer overflow" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15" "${CANONICAL_HEADER_OVERFLOW_HEADERS[@]}"

# ============================================================================
echo ""
echo "=== 6. ENVIRONMENT VARIABLE FUZZING ==="
echo ""

# Test with missing environment variables
unset AWS_ACCESS_KEY_ID
run_fuzz_test "Missing AWS_ACCESS_KEY_ID" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15"

export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
unset AWS_SECRET_ACCESS_KEY
run_fuzz_test "Missing AWS_SECRET_ACCESS_KEY" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15"

# Test with oversized environment variables
export AWS_ACCESS_KEY_ID="$HUGE_STRING"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
run_fuzz_test "Oversized access key" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15"

export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="$HUGE_STRING"
run_fuzz_test "Oversized secret key" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15"

# Test with malformed environment variables
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
run_fuzz_test "Empty credentials" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "15"

export AWS_ACCESS_KEY_ID="invalid\x00key"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
run_fuzz_test "Null byte in access key" "should_pass" "s3" "GET" "region" "https://bucket.com" "path" "15"

# ============================================================================
echo ""
echo "=== 7. BOUNDARY CONDITION FUZZING ==="
echo ""

# Restore valid environment
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# Test boundary values for expiration (1 min = min, 10080 min = 7 days = max)
run_fuzz_test "Minimum expiry (1)" "should_pass" "s3" "GET" "region" "https://bucket.com" "path" "1"
run_fuzz_test "Maximum expiry (10080)" "should_pass" "s3" "GET" "region" "https://bucket.com" "path" "10080"
run_fuzz_test "Just over maximum (10081)" "should_fail" "s3" "GET" "region" "https://bucket.com" "path" "10081"

# Test empty and single-character inputs
run_fuzz_test "Single char region" "should_pass" "s3" "GET" "a" "https://bucket.com" "path" "15"
run_fuzz_test "Single char path" "should_pass" "s3" "GET" "region" "https://bucket.com" "a" "15"

# ============================================================================
echo ""
echo "=== RESULTS SUMMARY ==="
echo ""

echo "Total tests run: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo ""
    echo -e "${GREEN}🎉 ALL FUZZ TESTS PASSED!${NC}"
    echo "The presign utility handles malformed input gracefully."
    echo ""
    echo "✅ No crashes or segfaults detected"
    echo "✅ No infinite loops or hangs detected"
    echo "✅ Proper error handling for invalid inputs"
    echo "✅ Boundary conditions handled correctly"
    exit 0
else
    echo ""
    echo -e "${RED}❌ SOME FUZZ TESTS FAILED!${NC}"
    echo "The presign utility may have stability or security issues."
    echo ""
    echo "⚠️  Found potential issues:"
    echo "   - Crashes or segfaults on malformed input"
    echo "   - Infinite loops or hangs"
    echo "   - Unexpected success on invalid input"
    echo ""
    echo "🔧 Recommended actions:"
    echo "   1. Review failed test cases above"
    echo "   2. Add proper input validation"
    echo "   3. Add bounds checking for string operations"
    echo "   4. Test with AddressSanitizer (make CFLAGS='-fsanitize=address')"
    exit 1
fi
