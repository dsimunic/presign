#!/bin/bash

# Advanced PUT example - Upload with multiple headers and metadata
# This script demonstrates advanced upload options

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

echo "=== Advanced PUT Example ==="
echo "Generating presigned URL with multiple headers and metadata..."
echo

# Generate a presigned URL for uploading with advanced options
OBJECT_PATH="documents/report-$(date +%Y%m%d).pdf"
EXPIRE_MIN="120"

echo "Parameters:"
echo "  Service: s3"
echo "  Method: PUT"
echo "  Region: $S3_REGION"
echo "  Bucket: $S3_BUCKET_URL"
echo "  Path: $OBJECT_PATH"
echo "  Expires: $EXPIRE_MIN minutes"
echo "  Headers:"
echo "    Content-Type: application/pdf"
echo "    x-amz-meta-author: Test User"
echo "    x-amz-meta-department: Engineering"
echo "    x-amz-server-side-encryption: AES256"
echo

URL=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --header "Content-Type: application/pdf" \
    --header "x-amz-meta-author: Test User" \
    --header "x-amz-meta-department: Engineering" \
    --header "x-amz-server-side-encryption: AES256")

echo "Generated presigned URL:"
echo "$URL"
echo
echo "You can use this URL with curl to upload a PDF file:"
echo "curl -X PUT --data-binary @your-file.pdf \\"
echo "  -H 'Content-Type: application/pdf' \\"
echo "  -H 'x-amz-meta-author: Test User' \\"
echo "  -H 'x-amz-meta-department: Engineering' \\"
echo "  -H 'x-amz-server-side-encryption: AES256' \\"
echo "  '$URL'"