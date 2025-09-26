# Presign Utility - Cross-Platform Build Guide

This document explains how to build the presign utility on different platforms.

## Supported Platforms

- **macOS** (ARM64/Intel) with Homebrew
- **Linux** (various distributions)

## Prerequisites

### macOS
```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install coreutils for GNU timeout (required for testing)
brew install coreutils

# Choose your crypto backend:

# Option 1: OpenSSL (default, smaller dynamic binary)
brew install openssl

# Option 2: mbedTLS (alternative, can be statically linked)
brew install mbedtls
```

### Linux (Debian/Ubuntu)
```bash
sudo apt update

# Choose your crypto backend:

# Option 1: OpenSSL (default)
sudo apt install build-essential libssl-dev pkg-config

# Option 2: mbedTLS (alternative, can be statically linked)
sudo apt install build-essential libmbedtls-dev pkg-config
```

### Linux (RHEL/CentOS/Fedora)
```bash
# Choose your crypto backend:

# Option 1: OpenSSL (default)
# RHEL/CentOS
sudo yum groupinstall 'Development Tools'
sudo yum install openssl-devel

# Fedora
sudo dnf groupinstall 'Development Tools'
sudo dnf install openssl-devel

# Option 2: mbedTLS (alternative, can be statically linked)
# Note: mbedTLS may not be available in base repositories
# You may need to build from source or find alternative packages
```

## Building

### Quick Build (All Platforms)
```bash
# Default: OpenSSL backend, dynamic linking
make clean && make
```

### Advanced Build Options

The Makefile supports several build configurations:

#### Crypto Backend Selection
```bash
# OpenSSL (default)
make CRYPTO_BACKEND=openssl

# mbedTLS (smaller dependency footprint)
make CRYPTO_BACKEND=mbedtls
```

#### Static vs Dynamic Linking
```bash
# Dynamic linking (default, smaller binary)
make STATIC_LINK=0

# Static linking (self-contained binary, larger but no external deps)
make STATIC_LINK=1 CRYPTO_BACKEND=mbedtls
```

#### Optimization Level
```bash
# Optimize for speed (default)
make OPTIMIZATION=-O2

# Optimize for size
make OPTIMIZATION=-Os
```

#### Combined Example
```bash
# Build static mbedTLS binary optimized for size
make clean && make CRYPTO_BACKEND=mbedtls STATIC_LINK=1 OPTIMIZATION=-Os
strip bin/presign  # Further reduce size
```

### Platform-Specific Instructions

#### macOS
The Makefile automatically detects macOS and uses Homebrew paths. Sudo is NOT required for building (only for installing to system locations):
```bash
# Dynamic build (35K)
make clean && make

# Static build (374K, self-contained)
make clean && make CRYPTO_BACKEND=mbedtls STATIC_LINK=1
strip bin/presign
```

#### Linux
```bash
# Dynamic build (default)
make clean && make

# Static build (requires mbedTLS)
make clean && make CRYPTO_BACKEND=mbedtls STATIC_LINK=1
strip bin/presign

# Or use the legacy build script
./build-linux.sh
```

## Cross-Platform Makefile Details

The Makefile automatically detects the platform using `uname` and supports multiple crypto backends:

- **macOS (Darwin)**: Homebrew paths for OpenSSL/mbedTLS
- **Linux**: System paths for OpenSSL/mbedTLS, adds `-D_GNU_SOURCE`

### Build Configuration Options

| Option | Values | Description |
|--------|--------|-------------|
| `CRYPTO_BACKEND` | `openssl` (default), `mbedtls` | Crypto library to use |
| `STATIC_LINK` | `0` (default), `1` | Static vs dynamic linking |
| `OPTIMIZATION` | `-O2` (default), `-Os` | Compiler optimization level |

### Build Flags by Platform and Backend

#### macOS
| Backend | Static | CFLAGS | LDFLAGS |
|---------|--------|--------|---------|
| OpenSSL | No | `-I/opt/homebrew/include` | `-L/opt/homebrew/lib -lssl -lcrypto` |
| mbedTLS | No | `-I/opt/homebrew/include` | `-L/opt/homebrew/lib -lmbedtls -lmbedcrypto` |
| mbedTLS | Yes | `-I/opt/homebrew/include` | `/opt/homebrew/lib/libmbedtls.a /opt/homebrew/lib/libmbedcrypto.a` |

#### Linux
| Backend | Static | CFLAGS | LDFLAGS |
|---------|--------|--------|---------|
| OpenSSL | No | `-D_GNU_SOURCE` | `-lssl -lcrypto` |
| mbedTLS | No | `-D_GNU_SOURCE` | `-lmbedtls -lmbedcrypto` |
| mbedTLS | Yes | `-D_GNU_SOURCE` | `/usr/lib/libmbedtls.a /usr/lib/libmbedcrypto.a` |

### Binary Size Comparison

| Configuration | Size | Dependencies | Distribution Notes |
|---------------|------|--------------|-------------------|
| **OpenSSL Dynamic** | ~35K | `libssl`, `libcrypto` | Requires OpenSSL installation |
| **mbedTLS Dynamic** | ~35K | `libmbedtls`, `libmbedcrypto` | Requires mbedTLS installation |
| **mbedTLS Static** | ~374K | System libs only | **Self-contained, recommended for distribution** |

## Testing

### Run Test Suite
```bash
cd test
./run-all-tests.sh
```

### Quick Functionality Test
```bash
# Set credentials
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# Test URL generation (explicit region + endpoint)
./bin/presign s3 GET fr-par https://s3.fr-par.scw.cloud bucket/test.txt 15

# Or rely on environment defaults
export S3_REGION=fr-par
export S3_ENDPOINT=https://s3.fr-par.scw.cloud
./bin/presign s3 GET bucket/test.txt 15
```

## Troubleshooting

### macOS Issues

**coreutils not found:**
```bash
# Install coreutils via Homebrew (required for GNU compatibility)
brew install coreutils

# Verify installation
which gsha256sum  # Should show /opt/homebrew/bin/gsha256sum
```

**OpenSSL not found:**
```bash
# Install OpenSSL via Homebrew
brew install openssl

# If still not found, check paths:
ls /opt/homebrew/include/openssl/
ls /opt/homebrew/lib/libssl*
```

**mbedTLS not found:**
```bash
# Install mbedTLS via Homebrew
brew install mbedtls

# Check installation:
ls /opt/homebrew/include/mbedtls/
ls /opt/homebrew/lib/libmbed*
```

**Static linking fails:**
```bash
# Ensure static libraries are available
ls /opt/homebrew/lib/*.a

# If missing, reinstall mbedTLS
brew reinstall mbedtls
```

**Apple Silicon vs Intel:**
- ARM64: `/opt/homebrew/` (Apple Silicon)
- x86_64: `/usr/local/` (Intel Macs, if using custom Homebrew)

### Linux Issues

**Missing build tools:**
```bash
# Debian/Ubuntu
sudo apt install build-essential

# RHEL/CentOS
sudo yum groupinstall 'Development Tools'
```

**OpenSSL/mbedTLS development headers missing:**
```bash
# Debian/Ubuntu - OpenSSL
sudo apt install libssl-dev

# Debian/Ubuntu - mbedTLS
sudo apt install libmbedtls-dev

# RHEL/CentOS - OpenSSL
sudo yum install openssl-devel

# RHEL/CentOS - mbedTLS (may require EPEL or manual install)
sudo yum install mbedtls-devel
```

**Static linking fails on Linux:**
```bash
# Check if static libraries exist
ls /usr/lib/libmbed*.a

# If not available, you may need to build mbedTLS from source
# or use dynamic linking instead
```

## Development Notes

### Adding New Platform Support

To add support for a new platform:

1. Add detection in Makefile:
```makefile
ifeq ($(UNAME), YourPlatform)
    CFLAGS += -DYour_Platform_Specific_Defines
    LDFLAGS += -LYour_Platform_Lib_Path
endif
```

2. Test feature availability:
- `strptime()` and `timegm()` functions
- Crypto library locations
- Standard library variations

3. Update this documentation

### Adding New Crypto Backend

To add a new crypto backend:

1. Add backend detection in Makefile:
```makefile
else ifeq ($(CRYPTO_BACKEND), yourcrypto)
    LDFLAGS = -lyourcrypto
    CFLAGS += -DUSE_YOURCRYPTO
endif
```

2. Add conditional includes in `src/presign.c`:
```c
#ifdef USE_YOURCRYPTO
#include <yourcrypto/yourcrypto.h>
#endif
```

3. Implement the crypto functions:
- `hmac_sha256()` - HMAC-SHA256 implementation
- `sha256_hash()` - SHA256 hash implementation

4. Update BUILD.md documentation

### Code Portability

The codebase uses:
- **C99 standard** for maximum compatibility
- **POSIX functions** with appropriate feature macros
- **Configurable crypto backends** (OpenSSL/mbedTLS)
- **Standard library** functions available everywhere

Platform-specific code is minimized and isolated to build configuration.
