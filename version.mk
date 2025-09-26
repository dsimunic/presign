# Format: NAME@REV[.dirty]-YYYYMMDDTHHMMSSZ

FALLBACK_NAME ?= 
FALLBACK_REV  ?= 

INSIDE_WT := $(shell command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree 2>/dev/null || echo false)

ifeq ($(INSIDE_WT),true)
NAME  := $(shell git symbolic-ref --short -q HEAD || git describe --tags --exact-match 2>/dev/null || echo detached)@
REV   := $(shell git rev-parse --short=8 HEAD)
DIRTY := $(shell test -n "$$(git status --porcelain 2>/dev/null)" && echo ".dirty")-
ifneq ($(DIRTY),)
  TIMESTAMP := $(shell date -u +%Y%m%dT%H%M%SZ)
else
  TIMESTAMP := $(shell git log -1 --format=%cd --date=format:%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%Y%m%dT%H%M%SZ)
endif
GITVER := $(NAME)$(REV)$(DIRTY)$(TIMESTAMP)
else
TIMESTAMP := $(shell date -u +%Y%m%dT%H%M%SZ)
GITVER := $(TIMESTAMP)
endif

.PHONY: print-gitver
print-gitver:
	@echo $(GITVER)
