#!/bin/bash

# Debug GET - Test if GET operations work properly
# This script tests GET presigned URLs

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

echo "=== Debug GET Test ==="
echo

# Generate presigned URL for a GET operation
OBJECT_PATH="test/nonexistent-file.txt"
EXPIRE_MIN="5"

echo "Generating presigned GET URL..."
echo "Command: $PRESIGN_BIN s3 GET $S3_REGION $S3_BUCKET_URL $OBJECT_PATH $EXPIRE_MIN"

GET_URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN")

echo
echo "Generated URL:"
echo "$GET_URL"
echo

# Parse the URL to show components
echo "URL Components:"
echo "Base URL: $(echo "$GET_URL" | cut -d'?' -f1)"
echo "Query Parameters:"
echo "$GET_URL" | cut -d'?' -f2 | tr '&' '\n' | sort
echo

# Test the GET with curl (expect 404 since file doesn't exist, but that means the signature worked)
echo "Testing GET request (expecting 404 since file doesn't exist)..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null "$GET_URL")

echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "404" ]; then
    echo "✅ GET signature is valid (got expected 404)"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ GET signature is invalid (got 403 Forbidden)"
elif [ "$HTTP_CODE" = "400" ]; then
    echo "❌ GET request is malformed (got 400 Bad Request)"
else
    echo "ℹ️  Unexpected response code: $HTTP_CODE"
fi