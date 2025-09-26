#!/bin/bash

# Debug Upload - Detailed debugging of upload process
# This script shows detailed information about the upload process

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -a
source "$SCRIPT_DIR/../secrets-s3.env"
set +a

PRESIGN_BIN="$SCRIPT_DIR/../../bin/presign"

if [ ! -x "$PRESIGN_BIN" ]; then
    echo "Error: presign binary not found at $PRESIGN_BIN" >&2
    exit 1
fi

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed." >&2
    exit 1
fi

echo "=== Debug Upload Test ==="
echo

# Create a simple test file
TEST_FILE=$(mktemp)
echo "Hello World! This is a test file." > "$TEST_FILE"
echo "Created test file: $TEST_FILE"
echo "Content: $(cat "$TEST_FILE")"
echo "Size: $(wc -c < "$TEST_FILE") bytes"
echo

# Generate presigned URL
OBJECT_PATH="debug/test-$(date +%s).txt"
EXPIRE_MIN="10"

echo "Generating presigned URL..."
echo "Command: $PRESIGN_BIN s3 PUT $S3_REGION $S3_BUCKET_URL $OBJECT_PATH $EXPIRE_MIN --header \"Content-Type: text/plain\""

UPLOAD_URL=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --header "Content-Type: text/plain")

echo
echo "Generated URL:"
echo "$UPLOAD_URL"
echo

# Parse the URL to show components
echo "URL Components:"
echo "Base URL: $(echo "$UPLOAD_URL" | cut -d'?' -f1)"
echo "Query Parameters:"
echo "$UPLOAD_URL" | cut -d'?' -f2 | tr '&' '\n' | sort
echo

# Test the upload with verbose curl
echo "Performing upload with verbose output..."
curl -v -X PUT \
    --data-binary "@$TEST_FILE" \
    -H "Content-Type: text/plain" \
    "$UPLOAD_URL"

echo
echo "Upload attempt completed."

# Clean up
rm "$TEST_FILE"