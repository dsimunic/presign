#!/bin/bash

# Special Characters example - Handle paths with spaces and special chars
# This script demonstrates URL encoding handling

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

echo "=== Special Characters Example ==="
echo "Generating presigned URLs for paths with special characters..."
echo

# Test various special character scenarios
declare -a TEST_PATHS=(
    "folder with spaces/file.txt"
    "résumé & cv [final].pdf"
    "data+analysis/results (2023).json"
    "files/document#1.txt"
    "uploads/file%20encoded.txt"
    "测试/中文文件.txt"
)

for i in "${!TEST_PATHS[@]}"; do
    OBJECT_PATH="${TEST_PATHS[$i]}"
    echo "--- Test $((i+1)): $OBJECT_PATH ---"

    URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_BUCKET_URL" "$OBJECT_PATH" "60")

    echo "Generated URL:"
    echo "$URL"
    echo
done

echo "All special character paths handled successfully!"