#!/bin/bash

# Run All Basic Examples - Execute all URL generation examples
# This script runs all the basic examples that only generate URLs (no S3 interaction)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "🚀 Running All Basic Examples"
echo "========================================"
echo

# List of basic examples that don't require S3 interaction
BASIC_EXAMPLES=(
    "basic-get.sh"
    "basic-put.sh"
    "basic-delete.sh"
    "advanced-put.sh"
    "special-characters.sh"
    "time-override.sh"
)

SUCCESS_COUNT=0
TOTAL_COUNT=${#BASIC_EXAMPLES[@]}

for example in "${BASIC_EXAMPLES[@]}"; do
    echo "----------------------------------------"
    echo "Running: $example"
    echo "----------------------------------------"

    if ./"$example"; then
        echo "✅ $example completed successfully"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ $example failed"
    fi
    echo
done

echo "========================================"
echo "📊 Results Summary"
echo "========================================"
echo "Successful: $SUCCESS_COUNT / $TOTAL_COUNT"

if [ $SUCCESS_COUNT -eq $TOTAL_COUNT ]; then
    echo "🎉 All basic examples passed!"
    exit 0
else
    echo "⚠️  Some examples failed."
    exit 1
fi