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

# Install OpenSSL
brew install openssl
```

### Linux (Debian/Ubuntu)
```bash
sudo apt update
sudo apt install build-essential libssl-dev pkg-config
```

### Linux (RHEL/CentOS/Fedora)
```bash
# RHEL/CentOS
sudo yum groupinstall 'Development Tools'
sudo yum install openssl-devel

# Fedora
sudo dnf groupinstall 'Development Tools'
sudo dnf install openssl-devel
```

## Building

### Quick Build (All Platforms)
```bash
make clean && make
```

### Platform-Specific Instructions

#### macOS
The Makefile automatically detects macOS and uses Homebrew paths. Sudo is NOT required for building (only for installing to system locations):
```bash
make clean && make
# Creates: bin/presign
```

#### Linux 

```bash
cd /path/to/Secrets/tools/presign && ./build-linux.sh

# Creates (Linux):
#   bin/presign-linux-<arch>  (real binary)
#   bin/presign               (symlink for tests)
```

## Cross-Platform Makefile Details

The Makefile automatically detects the platform using `uname`:

- **macOS (Darwin)**: Adds Homebrew include/lib paths
- **Linux**: Adds `-D_GNU_SOURCE` for POSIX functions

### Build Flags by Platform

| Platform | Additional CFLAGS | Additional LDFLAGS |
|----------|-------------------|-------------------|
| macOS | `-I/opt/homebrew/include` | `-L/opt/homebrew/lib` |
| Linux | `-D_GNU_SOURCE` | (none) |

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

**OpenSSL not found:**
```bash
# Install OpenSSL via Homebrew
brew install openssl

# If still not found, check paths:
ls /opt/homebrew/include/openssl/
ls /opt/homebrew/lib/libssl*
```

**Apple Silicon vs Intel:**
- ARM64: `/opt/homebrew/` (Apple Silicon)
- x86_64: `/usr/local/` (Intel Macs)

### Linux Issues

**Missing build tools:**
```bash
# Debian/Ubuntu
sudo apt install build-essential

# RHEL/CentOS
sudo yum groupinstall 'Development Tools'
```

**OpenSSL development headers missing:**
```bash
# Debian/Ubuntu
sudo apt install libssl-dev

# RHEL/CentOS
sudo yum install openssl-devel
```

**strptime/timegm not found:**
- This should be automatically handled by `-D_GNU_SOURCE`
- If issues persist, ensure you're using the provided Makefile

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
- OpenSSL library locations
- Standard library variations

3. Update this documentation

### Code Portability

The codebase uses:
- **C99 standard** for maximum compatibility
- **POSIX functions** with appropriate feature macros
- **OpenSSL** for cryptographic operations
- **Standard library** functions available everywhere

Platform-specific code is minimized and isolated to build configuration.
