#!/bin/bash

# Basic DELETE example - Generate a presigned URL to delete a file
# This script demonstrates the DELETE operation

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

echo "=== Basic DELETE Example ==="
echo "Generating presigned URL for deleting a file..."
echo

# Generate a presigned URL for deleting an object
OBJECT_PATH="temp/old-file.txt"
EXPIRE_MIN="15"

echo "Parameters:"
echo "  Service: s3"
echo "  Method: DELETE"
echo "  Region: $S3_REGION"
echo "  Bucket: $S3_BUCKET_URL"
echo "  Path: $OBJECT_PATH"
echo "  Expires: $EXPIRE_MIN minutes"
echo

URL=$("$PRESIGN_BIN" s3 DELETE "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN")

echo "Generated presigned URL:"
echo "$URL"
echo
echo "You can use this URL with curl to delete the file:"
echo "curl -X DELETE '$URL'"