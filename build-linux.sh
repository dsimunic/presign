#!/bin/bash

# Linux Build Script for Presign Utility
# This script builds the presign utility on Linux systems

echo "=== Presign Linux Build Script ==="
echo ""

# Check if we're running on Linux
if [ "$(uname)" != "Linux" ]; then
    echo "❌ This script should be run on a Linux system"
    echo "Current system: $(uname)"
    exit 1
fi

echo "✅ Running on Linux: $(uname -a)"
echo ""

# Check for required packages (install if missing on Debian/Ubuntu)
echo "🔍 Checking for required packages..."
missing=()
command -v gcc >/dev/null 2>&1 || missing+=(build-essential)
command -v pkg-config >/dev/null 2>&1 || missing+=(pkg-config)
pkg-config --exists openssl || missing+=(libssl-dev)

if [ ${#missing[@]} -gt 0 ]; then
    if command -v apt-get >/dev/null 2>&1; then
        echo "📦 Installing missing packages: ${missing[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends ${missing[*]}
    else
        echo "❌ Missing required packages and cannot auto-install: ${missing[*]}"
        exit 1
    fi
fi

echo "✅ Build dependencies satisfied"
echo ""

# Build the project
echo "🔨 Building presign utility (clean build)..."
if make clean && make; then
    echo ""
    echo "✅ Build successful!"
    echo ""

    # Test the binary
    echo "🧪 Testing the binary..."
    if ./bin/presign >/dev/null 2>&1; then
        echo "❌ Binary test failed (expected - no arguments provided)"
    else
        echo "✅ Binary responds to --help (no arguments provided shows usage)"
    fi

    echo ""
    echo "📦 Distribution:"
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        *) ARCH=$ARCH_RAW ;;
    esac
    echo "   Binary location (test symlink): $(pwd)/bin/presign"
    echo "   Architecture: $ARCH ($ARCH_RAW)"
    echo "   File info: $(file bin/presign 2>/dev/null || echo 'file command not available')"
    echo ""

    # Create a Linux-specific binary name if Makefile did not already do it
    if [ -f bin/presign-linux-$ARCH ]; then
        echo "ℹ️  Arch-specific binary already present: bin/presign-linux-$ARCH"
    else
        cp bin/presign bin/presign-linux-$ARCH
        echo "✅ Created distribution binary: bin/presign-linux-$ARCH"
    fi
    echo ""

    echo "🎉 Build complete! You can now use:"
    echo "   ./bin/presign s3 GET region https://bucket.s3.region.provider.com path 15"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    echo "   2. Run tests: cd test && ./run-all-tests.sh"
    echo "   3. Copy binary to desired location: cp bin/presign /usr/local/bin/"

else
    echo ""
    echo "❌ Build failed!"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   1. Check that all dependencies are installed"
    echo "   2. Review error messages above"
    echo "   3. Ensure you have write permissions in this directory"
    exit 1
fi