CC = gcc

# Default target
.PHONY: all
.DEFAULT_GOAL := all

# Detect operating system / architecture
UNAME := $(shell uname)
ARCH  := $(shell uname -m)

# Map architecture names to Debian style for clarity if needed later
ifeq ($(ARCH),x86_64)
  ARCH_NORMALIZED := amd64
else ifeq ($(ARCH),aarch64)
  ARCH_NORMALIZED := arm64
else
  ARCH_NORMALIZED := $(ARCH)
endif

# Crypto backend selection
CRYPTO_BACKEND ?= openssl
STATIC_LINK ?= 0

# Base flags
OPTIMIZATION ?= -O2
CFLAGS = -Wall -Wextra -Werror -std=c99 $(OPTIMIZATION)

# Crypto backend specific flags
ifeq ($(CRYPTO_BACKEND), openssl)
    ifeq ($(STATIC_LINK), 1)
        LDFLAGS = -static -lssl -lcrypto
    else
        LDFLAGS = -lssl -lcrypto
    endif
    CFLAGS += -DUSE_OPENSSL
else ifeq ($(CRYPTO_BACKEND), mbedtls)
    ifeq ($(STATIC_LINK), 1)
        ifeq ($(UNAME), Darwin)
            MBEDTLS_LIB_PATH = /opt/homebrew/lib
        else
            MBEDTLS_LIB_PATH = /usr/lib
        endif
        LDFLAGS = $(MBEDTLS_LIB_PATH)/libmbedtls.a $(MBEDTLS_LIB_PATH)/libmbedcrypto.a
    else
        LDFLAGS = -lmbedtls -lmbedcrypto
    endif
    CFLAGS += -DUSE_MBEDTLS
endif

# Platform-specific flags
ifeq ($(UNAME), Darwin)
    # macOS with Homebrew
    ifeq ($(CRYPTO_BACKEND), openssl)
        OPENSSL_PREFIX ?= /opt/homebrew
        CFLAGS += -I$(OPENSSL_PREFIX)/include
        LDFLAGS += -L$(OPENSSL_PREFIX)/lib
    else ifeq ($(CRYPTO_BACKEND), mbedtls)
        MBEDTLS_PREFIX ?= /opt/homebrew
        CFLAGS += -I$(MBEDTLS_PREFIX)/include
        LDFLAGS += -L$(MBEDTLS_PREFIX)/lib
    endif
endif
ifeq ($(UNAME), Linux)
    # Linux - need _GNU_SOURCE for strptime/timegm
    CFLAGS += -D_GNU_SOURCE
    ifeq ($(CRYPTO_BACKEND), mbedtls)
        # On Linux, mbedTLS headers are in /usr/include/mbedtls
        CFLAGS += -I/usr/include
        LDFLAGS += -L/usr/lib
    endif
endif

SRCDIR = src
BUILDDIR = build
BINDIR = bin
VERSION_FILE = VERSION
# Include version.mk for GITVER calculation
ifndef CLEAN_VERSION
include version.mk
else
GITVER := $(shell cat $(VERSION_FILE))
endif

# Add version defines to CFLAGS
CFLAGS += -DPRESIGN_BASE_VERSION=\"$(shell cat $(VERSION_FILE))\"
CFLAGS += -DPRESIGN_BUILD_VERSION=\"$(GITVER)\"

SOURCES = $(SRCDIR)/presign.c
OBJECTS = $(BUILDDIR)/presign.o

# Binary naming convention:
#   macOS: bin/presign
#   Linux: bin/presign-linux-<archNormalized>
ifeq ($(UNAME), Darwin)
  TARGET = $(BINDIR)/presign
else
  TARGET = $(BINDIR)/presign-linux-$(ARCH_NORMALIZED)
endif

# Convenience symlink for tests expecting bin/presign (Linux)
TEST_LINK = $(BINDIR)/presign

.PHONY: clean test install check dist distcheck

all: $(TARGET) symlink-for-tests

$(TARGET): $(OBJECTS) | $(BINDIR)
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

$(BUILDDIR)/%.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BINDIR):
	mkdir -p $(BINDIR)


clean:
	rm -rf $(BUILDDIR) $(BINDIR)

symlink-for-tests: $(TARGET)
ifeq ($(UNAME), Linux)
	@if [ ! -e $(TEST_LINK) ]; then ln -s $(notdir $(TARGET)) $(TEST_LINK); fi
endif

test: all
	@echo "Running fuzz test suite: test/test-suite.sh"
	@./test/test-suite.sh

# "check" is the conventional GNU/make/autotools target name for running
# the project's test-suite. Provide it as an alias to the existing `test`
# target so CI systems that invoke `make check` will run our tests.
check: test

# Create a source distribution tarball. When a git repository is present we
# prefer `git archive` (keeps tar deterministic for tagged commits). If no
# .git directory exists we fall back to a simple `tar` of the common files.
ifneq ($(wildcard .git),)
dist:
	@echo "Creating distribution tarball presign-$(GITVER).tar.gz (via git archive)"
	@git archive --format=tar --prefix=presign-$(GITVER)/ HEAD | gzip > presign-$(GITVER).tar.gz
else
dist:
	@echo "Creating distribution tarball presign-$(GITVER).tar.gz (via tar fallback)"
	@tar -czf presign-$(GITVER).tar.gz --transform "s,^[./]*,presign-$(GITVER)/," \
		src README.md VERSION presign.1 Makefile test || true
endif

# "distcheck" is a common autotools target: build a distribution tarball,
# unpack it in a fresh directory, build from that tree and run the test
# suite there. This provides reasonable assurance that the tarball contains
# everything needed to build and test on a clean system.
distcheck: dist
	@echo "Running distcheck: building and testing from the generated tarball"
	@rm -rf $(BUILDDIR)/distcheck || true
	@mkdir -p $(BUILDDIR)/distcheck
	@tar -xzf presign-$(GITVER).tar.gz -C $(BUILDDIR)/distcheck
	@cd $(BUILDDIR)/distcheck/presign-$(GITVER) && $(MAKE) && $(MAKE) check

install: all
	mkdir -p /usr/local/bin
ifeq ($(UNAME), Darwin)
	cp $(TARGET) /usr/local/bin/presign
else
	cp $(TARGET) /usr/local/bin/presign
endif