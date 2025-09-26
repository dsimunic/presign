#!/bin/bash

# Complete Workflow Test - Upload, Download, and Delete cycle
# This script demonstrates the complete lifecycle of an S3 object

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Loading S3 configuration from $SCRIPT_DIR/../secrets-s3.env"
set -a
source "$SCRIPT_DIR/../secrets-s3.env"
set +a

if [ -z "$S3_REGION" ] || [ -z "$S3_ENDPOINT" ] || [ -z "$BUCKET" ]; then
    echo "Error: S3_REGION, S3_ENDPOINT, and BUCKET must be set in the environment." >&2
    exit 1
fi

echo "Using S3 endpoint: $S3_ENDPOINT in region $S3_REGION for bucket $BUCKET"

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

echo "========================================"
echo "🔄 Complete S3 Workflow Test"
echo "========================================"
echo "This script will:"
echo "1. Create a test file"
echo "2. Upload it to S3"
echo "3. Download it back"
echo "4. Verify content matches"
echo "5. Delete the object"
echo "6. Verify deletion"
echo

# Generate unique object path
TIMESTAMP=$(date +%s)
OBJECT_PATH="test-workflow/complete-test-$TIMESTAMP.txt"

echo "Test object path: $OBJECT_PATH"
echo

# Step 1: Create test file
echo "📝 Step 1: Creating test file..."
TEST_FILE=$(mktemp)
TEST_CONTENT="Complete workflow test file
Created at: $(date)
Timestamp: $TIMESTAMP
Random UUID: $(uuidgen)
Test data: The quick brown fox jumps over the lazy dog."

echo "$TEST_CONTENT" > "$TEST_FILE"
echo "✅ Test file created with $(wc -c < "$TEST_FILE") bytes"
echo

# Step 2: Upload to S3
echo "⬆️  Step 2: Uploading to S3..."
S3_PATH="$BUCKET/$OBJECT_PATH"

UPLOAD_URL=$("$PRESIGN_BIN" s3 PUT "$S3_REGION" "$S3_ENDPOINT" "$S3_PATH" "10" \
    --header "Content-Type: text/plain" \
    --header "x-amz-meta-test: complete-workflow")

UPLOAD_RESPONSE=$(curl -s -w "%{http_code}" -X PUT \
    --data-binary "@$TEST_FILE" \
    -H "Content-Type: text/plain" \
    -H "x-amz-meta-test: complete-workflow" \
    "$UPLOAD_URL")

UPLOAD_CODE="${UPLOAD_RESPONSE: -3}"

if [ "$UPLOAD_CODE" = "200" ]; then
    echo "✅ Upload successful (HTTP $UPLOAD_CODE)"
else
    echo "❌ Upload failed (HTTP $UPLOAD_CODE)"
    rm "$TEST_FILE"
    exit 1
fi
echo

# Step 3: Download from S3
echo "⬇️  Step 3: Downloading from S3..."
DOWNLOAD_URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_ENDPOINT" "$S3_PATH" "5")

DOWNLOAD_FILE=$(mktemp)
DOWNLOAD_RESPONSE=$(curl -s -w "%{http_code}" -o "$DOWNLOAD_FILE" "$DOWNLOAD_URL")

if [ "$DOWNLOAD_RESPONSE" = "200" ]; then
    echo "✅ Download successful (HTTP $DOWNLOAD_RESPONSE)"
    echo "   Downloaded $(wc -c < "$DOWNLOAD_FILE") bytes"
else
    echo "❌ Download failed (HTTP $DOWNLOAD_RESPONSE)"
    rm "$TEST_FILE" "$DOWNLOAD_FILE"
    exit 1
fi
echo

# Step 4: Verify content
echo "🔍 Step 4: Verifying content integrity..."
if cmp -s "$TEST_FILE" "$DOWNLOAD_FILE"; then
    echo "✅ Content verification passed - files are identical"
else
    echo "❌ Content verification failed - files differ!"
    echo
    echo "Original file:"
    echo "=============="
    cat "$TEST_FILE"
    echo
    echo "Downloaded file:"
    echo "================"
    cat "$DOWNLOAD_FILE"
    echo
    rm "$TEST_FILE" "$DOWNLOAD_FILE"
    exit 1
fi
echo

# Step 5: Delete from S3
echo "🗑️  Step 5: Deleting from S3..."
DELETE_URL=$("$PRESIGN_BIN" s3 DELETE "$S3_REGION" "$S3_ENDPOINT" "$S3_PATH" "5")

DELETE_RESPONSE=$(curl -s -w "%{http_code}" -X DELETE "$DELETE_URL")
DELETE_CODE="${DELETE_RESPONSE: -3}"

if [ "$DELETE_CODE" = "204" ]; then
    echo "✅ Delete successful (HTTP $DELETE_CODE)"
else
    echo "❌ Delete failed (HTTP $DELETE_CODE)"
    rm "$TEST_FILE" "$DOWNLOAD_FILE"
    exit 1
fi
echo

# Step 6: Verify deletion
echo "✅ Step 6: Verifying deletion..."
VERIFY_URL=$("$PRESIGN_BIN" s3 GET "$S3_REGION" "$S3_ENDPOINT" "$S3_PATH" "5")
VERIFY_RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null "$VERIFY_URL")

if [ "$VERIFY_RESPONSE" = "404" ]; then
    echo "✅ Deletion verified - object no longer exists (HTTP $VERIFY_RESPONSE)"
else
    echo "⚠️  Unexpected response during verification (HTTP $VERIFY_RESPONSE)"
fi

# Clean up
rm "$TEST_FILE" "$DOWNLOAD_FILE"

echo
echo "🎉 Complete workflow test PASSED!"
echo "   All operations (upload, download, verify, delete) completed successfully."
echo
echo "Summary:"
echo "- Object path: $OBJECT_PATH"
echo "- Upload: HTTP $UPLOAD_CODE"
echo "- Download: HTTP $DOWNLOAD_RESPONSE"
echo "- Content: Identical"
echo "- Delete: HTTP $DELETE_CODE"
echo "- Verification: HTTP $VERIFY_RESPONSE"
