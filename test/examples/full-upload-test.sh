#!/bin/bash

# Full Upload Test - Actually upload a file to S3
# This script creates a test file, uploads it, and verifies the upload

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -a
source "$SCRIPT_DIR/../secrets-s3.env"
set +a

PRESIGN_BIN="$SCRIPT_DIR/../../bin/presign"

if [ ! -x "$PRESIGN_BIN" ]; then
    echo "Error: presign binary not found at $PRESIGN_BIN" >&2
    echo "Build it with 'make' from the repository root." >&2
    exit 1
fi

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed." >&2
    exit 1
fi

echo "=== Full Upload Test ==="
echo "This script will upload a real file to S3 using presigned URLs..."
echo

# Create a temporary test file
TEST_FILE=$(mktemp)
TEST_CONTENT="Hello from presign tool test!
This file was uploaded at: $(date)
Random data: $(uuidgen)"

echo "$TEST_CONTENT" > "$TEST_FILE"
echo "Created test file: $TEST_FILE"
echo "Content:"
cat "$TEST_FILE"
echo

# Generate presigned URL for upload
OBJECT_PATH="test-uploads/presign-test-$(date +%s).txt"
EXPIRE_MIN="10"

echo "Generating presigned URL for upload..."
UPLOAD_URL=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --header "Content-Type: text/plain")

echo "Upload URL: $UPLOAD_URL"
echo

# Perform the upload
echo "Uploading file to S3..."
UPLOAD_RESPONSE=$(curl -s -w "%{http_code}" -X PUT \
    --data-binary "@$TEST_FILE" \
    -H "Content-Type: text/plain" \
    "$UPLOAD_URL")

HTTP_CODE="${UPLOAD_RESPONSE: -3}"
RESPONSE_BODY="${UPLOAD_RESPONSE%???}"

echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Upload successful!"
    echo "Object uploaded to: $OBJECT_PATH"
else
    echo "❌ Upload failed!"
    echo "Response: $RESPONSE_BODY"
    rm "$TEST_FILE"
    exit 1
fi

# Clean up
rm "$TEST_FILE"

echo
echo "Upload test completed successfully!"
echo "You can now test downloading this file with: full-download-test.sh $OBJECT_PATH"