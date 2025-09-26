#!/bin/bash

# Basic PUT example - Generate a presigned URL to upload a file
# This script demonstrates uploading with content type

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

echo "=== Basic PUT Example ==="
echo "Generating presigned URL for uploading a file..."
echo

# Generate a presigned URL for uploading an object
OBJECT_PATH="uploads/document.txt"
EXPIRE_MIN="30"

echo "Parameters:"
echo "  Service: s3"
echo "  Method: PUT"
echo "  Region: $S3_REGION"
echo "  Bucket: $S3_BUCKET_URL"
echo "  Path: $OBJECT_PATH"
echo "  Expires: $EXPIRE_MIN minutes"
echo "  Headers: Content-Type: text/plain"
echo

URL=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --header "Content-Type: text/plain")

echo "Generated presigned URL:"
echo "$URL"
echo
echo "You can use this URL with curl to upload a file:"
echo "curl -X PUT --data-binary @your-file.txt -H 'Content-Type: text/plain' '$URL'"