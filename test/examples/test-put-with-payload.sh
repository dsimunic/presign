#!/bin/bash

# Test PUT with x-amz-content-sha256=UNSIGNED-PAYLOAD parameter

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -a
source "$SCRIPT_DIR/../secrets-s3.env"
set +a

PRESIGN_BIN="$SCRIPT_DIR/../../bin/presign"

echo "=== Testing PUT with x-amz-content-sha256=UNSIGNED-PAYLOAD ==="

# Create test file
TEST_FILE=$(mktemp)
echo "Hello World! Test PUT with UNSIGNED-PAYLOAD" > "$TEST_FILE"
echo "Test file created: $(wc -c < "$TEST_FILE") bytes"

# Generate presigned URL for PUT
OBJECT_PATH="test-put-$(date +%s).txt"
S3_PATH="$BUCKET/$OBJECT_PATH"

echo "Generating PUT URL..."
PUT_URL=$("$PRESIGN_BIN" s3 PUT us-east-1 "$S3_ENDPOINT" "$S3_PATH" "10" \
    --header "Content-Type: text/plain")

echo "Generated URL: $PUT_URL"

# Modify the URL to add x-amz-content-sha256=UNSIGNED-PAYLOAD
if [[ "$PUT_URL" == *"?"* ]]; then
    MODIFIED_URL="${PUT_URL}&x-amz-content-sha256=UNSIGNED-PAYLOAD"
else
    MODIFIED_URL="${PUT_URL}?x-amz-content-sha256=UNSIGNED-PAYLOAD"
fi

echo "Modified URL with UNSIGNED-PAYLOAD: $MODIFIED_URL"

# Test the upload
echo
echo "Testing upload..."
RESPONSE=$(curl -s -w "%{http_code}" -X PUT \
    --data-binary "@$TEST_FILE" \
    -H "Content-Type: text/plain" \
    -H "x-amz-content-sha256: UNSIGNED-PAYLOAD" \
    "$MODIFIED_URL")

HTTP_CODE="${RESPONSE: -3}"
echo "HTTP Response: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ PUT with UNSIGNED-PAYLOAD succeeded!"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ Still getting 403 - parameter not the issue"
else
    echo "ℹ️  Got unexpected response: $HTTP_CODE"
fi

# Clean up
rm "$TEST_FILE"