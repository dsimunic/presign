#!/bin/bash

# Full Delete Test - Actually delete a file from S3
# This script deletes a file using presigned URLs

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

echo "=== Full Delete Test ==="

# Allow specifying object path as parameter
if [ "$#" -eq 1 ]; then
    OBJECT_PATH="$1"
    echo "Deleting specified object: $OBJECT_PATH"
else
    echo "Usage: $0 <object-path>"
    echo "Example: $0 test-uploads/file-to-delete.txt"
    echo
    echo "To create a test file to delete, run:"
    echo "  ./full-upload-test.sh"
    exit 1
fi

echo

# Generate presigned URL for delete
EXPIRE_MIN="5"

echo "Generating presigned URL for delete..."
DELETE_URL=$("$PRESIGN_BIN" s3 DELETE "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN")

echo "Delete URL: $DELETE_URL"
echo

# Ask for confirmation
echo "⚠️  WARNING: This will permanently delete the object!"
echo "Object to delete: $OBJECT_PATH"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Perform the delete
echo "Deleting object from S3..."
DELETE_RESPONSE=$(curl -s -w "%{http_code}" -X DELETE "$DELETE_URL")

HTTP_CODE="${DELETE_RESPONSE: -3}"
RESPONSE_BODY="${DELETE_RESPONSE%???}"

echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "204" ]; then
    echo "✅ Delete successful!"
    echo "Object $OBJECT_PATH has been deleted."
elif [ "$HTTP_CODE" = "404" ]; then
    echo "⚠️  Object not found (404)"
    echo "The object $OBJECT_PATH was already deleted or never existed."
else
    echo "❌ Delete failed!"
    echo "Response: $RESPONSE_BODY"
    exit 1
fi

echo
echo "Delete test completed!"

# Verify deletion by trying to download
echo
echo "Verifying deletion by attempting download..."
VERIFY_URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "5")
VERIFY_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "$VERIFY_URL")

if [ "$VERIFY_RESPONSE" = "404" ]; then
    echo "✅ Deletion verified - object no longer exists."
else
    echo "⚠️  Unexpected: object may still exist (HTTP $VERIFY_RESPONSE)"
fi