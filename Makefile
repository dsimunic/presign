CC = gcc

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

# Base flags
CFLAGS = -Wall -Wextra -Werror -std=c99 -O2
LDFLAGS = -lssl -lcrypto

# Platform-specific flags
ifeq ($(UNAME), Darwin)
    # macOS with Homebrew
    CFLAGS += -I/opt/homebrew/include
    LDFLAGS += -L/opt/homebrew/lib
endif
ifeq ($(UNAME), Linux)
    # Linux - need _GNU_SOURCE for strptime/timegm
    CFLAGS += -D_GNU_SOURCE
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

.PHONY: all clean test install

all: $(TARGET) symlink-for-tests

$(TARGET): $(OBJECTS) | $(BINDIR)
	$(CC) $(OBJECTS) -o $@ $(LDFLAGS)

symlink-for-tests: $(TARGET)
ifeq ($(UNAME), Linux)
	@if [ ! -e $(TEST_LINK) ]; then ln -s $(notdir $(TARGET)) $(TEST_LINK); fi
endif

$(BUILDDIR)/%.o: $(SRCDIR)/%.c | $(BUILDDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BINDIR):
	mkdir -p $(BINDIR)

clean:
	rm -rf $(BUILDDIR) $(BINDIR)

test: all
	@echo "Running basic tests..."
	@echo "Test 1: Help message"
	@./$(TEST_LINK) || true
	@echo "Test 2: Invalid arguments"
	@./$(TEST_LINK) invalid args || true

install: all
	mkdir -p /usr/local/bin
ifeq ($(UNAME), Darwin)
	cp $(TARGET) /usr/local/bin/presign
else
	cp $(TARGET) /usr/local/bin/presign
endif