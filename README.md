# presign

`presign` creates AWS presigned urls.

## Synopsis
   
`presign SERVICE METHOD [REGION] [ENDPOINT] S3_PATH EXPIRE_MIN`

Required parameters:

    SERVICE     constant, always `s3`           [string]
    METHOD      GET | PUT | DELETE              [string]    allow any case, but uppercase internally
    REGION      s3 region                       [string]    example: `fr-par`
    ENDPOINT    service endpoint                [url]       example: https://s3.fr-par.scw.cloud
    S3_PATH     bucket + object path            [path]      example: bucket/inventory/host01.pub
    EXPIRE_MIN  expiration time in minutes      [positive integer > 0 and <= 7 days]

Required environment variables:

    AWS_ACCESS_KEY_ID           [non-empty string]
    AWS_SECRET_ACCESS_KEY       [non-empty string]

Optional environment variables:
    AWS_SESSION_TOKEN           [optional string]   optional, for STS/temporary creds
    S3_REGION                   [string]            default region when omitted on CLI
    S3_ENDPOINT                 [url]               default endpoint when omitted on CLI

The REGION and ENDPOINT positional arguments override any values supplied through the corresponding
environment variables, letting scripted workflows set broad defaults while still permitting per-call
overrides when needed.
      
Usually-needed/conditionally-needed:

*	Session token (`AWS_SESSION_TOKEN`) —- if using temporary credentials must be embedded as `X-Amz-Security-Token`.
*	Headers to be signed (zero or more), only if the client will send them:
    * Common for PUT: `Content-Type`, any `x-amz-*` such as `x-amz-acl`, `x-amz-meta-*`, `x-amz-server-side-encryption*`.
    * For GET response overrides, query params like response-content-type, etc. (must be in the signature).
*	Payload hash policy: for presigned S3 requests use `x-amz-content-sha256=UNSIGNED-PAYLOAD`. (If you choose to sign a fixed payload hash, the client must upload exactly that body.)
*	Clock source / skew tolerance: allows overriding time for testing reproducibility. (example: `--now 2025-09-25T08:40:00Z`)


## Practical use

    echo 'Hello!' > test-file.txt

*Set env*

    export AWS_ACCESS_KEY_ID=...
    export AWS_SECRET_ACCESS_KEY=...

*create presigned url:*

    bin/presign s3 PUT fr-par https://s3.fr-par.scw.cloud bucket/test-file.txt 15 \
    --header 'Content-Type: text/plain' \
    --header 'x-amz-acl: public-read'

*use the url elsewhere within 15 minutes (no env credentials needed):*

    curl -X PUT \
        -H "Content-Type: text/plain" \
        -H "x-amz-acl: public-read" \
        -d @test-file.txt \
    'https://s3.fr-par.scw.cloud/bucket/test-file.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=XXXXXXXXX%2F20250926%2Ffr-par%2Fs3%2Faws4_request&X-Amz-Date=20250926T102811Z&X-Amz-Expires=900&X-Amz-SignedHeaders=content-type%3Bhost%3Bx-amz-acl&X-Amz-Signature=5bdb657e458dc071333bb5a3aa294c8d9d8c7e7a98b70a84d0d5cf7f7ba604e8'

*verify public access (no signature needed):*

    curl https://s3.fr-par.scw.cloud/bucket/test-file.txt
    Hello!

*less messy (bash):*

    make clean all

    set -a
    source test/secrets-s3.env
    set +a

    METHOD=PUT 
    curl -X $METHOD -H "Content-Type: text/plain"-d @BUILD.md $(bin/presign s3 $METHOD $BUCKET/README.md 3)

    METHOD=GET
    curl -sX $M -H "Content-Type: text/plain" -d @BUILD.md $(bin/presign s3 $METHOD $BUCKET/README.md 3) | wc

    METHOD=DELETE
    curl -X $METHOD -H "Content-Type: text/plain"-d @BUILD.md $(bin/presign s3 $METHOD $BUCKET/README.md 3)






Also check `test/examples`. To run examples you'll need to create`test/secrets-s3.env` of this shape:

```bash
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
S3_REGION=your_region
S3_ENDPOINT=https://s3.your-region.provider.com
BUCKET=your-bucket-name
```