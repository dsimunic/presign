#!/bin/bash

# Full Download Test - Actually download a file from S3
# This script downloads a file using presigned URLs

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

echo "=== Full Download Test ==="

# Allow specifying object path as parameter
if [ "$#" -eq 1 ]; then
    OBJECT_PATH="$1"
    echo "Downloading specified object: $OBJECT_PATH"
else
    # Use a default test object path
    OBJECT_PATH="test-uploads/sample.txt"
    echo "Downloading default test object: $OBJECT_PATH"
    echo "(You can specify a different path as the first argument)"
fi

echo

# Generate presigned URL for download
EXPIRE_MIN="5"

echo "Generating presigned URL for download..."
DOWNLOAD_URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN")

echo "Download URL: $DOWNLOAD_URL"
echo

# Create temporary file for download
DOWNLOAD_FILE=$(mktemp)

# Perform the download
echo "Downloading file from S3..."
DOWNLOAD_RESPONSE=$(curl -s -w "%{http_code}" -o "$DOWNLOAD_FILE" "$DOWNLOAD_URL")

HTTP_CODE="$DOWNLOAD_RESPONSE"

echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Download successful!"
    echo
    echo "Downloaded content:"
    echo "===================="
    cat "$DOWNLOAD_FILE"
    echo "===================="
    echo
    echo "File size: $(wc -c < "$DOWNLOAD_FILE") bytes"
elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ Object not found (404)"
    echo "The object $OBJECT_PATH does not exist in the bucket."
    echo "Try running full-upload-test.sh first to create a test object."
else
    echo "❌ Download failed!"
    echo "Response body:"
    cat "$DOWNLOAD_FILE"
fi

# Clean up
rm "$DOWNLOAD_FILE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "Download test completed successfully!"
    exit 0
else
    exit 1
fi