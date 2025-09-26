#!/bin/bash

# Time Override example - Use custom timestamp for testing
# This script demonstrates the --now option

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

echo "=== Time Override Example ==="
echo "Generating presigned URLs with custom timestamps..."
echo

OBJECT_PATH="test/timestamped-file.txt"
EXPIRE_MIN="30"

echo "--- Current time (no override) ---"
URL1=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN")
echo "URL: $URL1"
echo

echo "--- Custom time override ---"
CUSTOM_TIME="2025-09-25T10:00:00Z"
echo "Using timestamp: $CUSTOM_TIME"

URL2=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --now "$CUSTOM_TIME")
echo "URL: $URL2"
echo

echo "--- Different method with time override ---"
URL3=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "$EXPIRE_MIN" \
    --header "Content-Type: text/plain" \
    --now "$CUSTOM_TIME")
echo "PUT URL: $URL3"
echo

echo "Time override functionality demonstrated!"
echo "Note: URLs with custom timestamps are useful for testing and reproducible signatures."