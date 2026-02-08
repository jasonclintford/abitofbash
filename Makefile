SUITE_NAME ?= abitofbash
PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/lib/$(SUITE_NAME)
CONFDIR := $(PREFIX)/share/$(SUITE_NAME)

BIN_SCRIPTS := $(wildcard bin/*.sh)
LIB_FILES := $(wildcard lib/*.sh)
CONF_FILES := $(wildcard config/*)

.PHONY: install uninstall lint test

install:
	@mkdir -p $(BINDIR) $(LIBDIR)/lib $(LIBDIR)/bin $(CONFDIR)
	@cp -a bin $(LIBDIR)/
	@cp -a lib $(LIBDIR)/
	@cp -a config $(LIBDIR)/
	@for f in $(BIN_SCRIPTS); do \
		install -m 0755 $$f $(BINDIR)/$$(basename $$f); \
	done

uninstall:
	@for f in $(BIN_SCRIPTS); do \
		rm -f $(BINDIR)/$$(basename $$f); \
	done
	@rm -rf $(LIBDIR)

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(BIN_SCRIPTS) $(LIB_FILES); \
	else \
		echo "shellcheck not available"; \
	fi

test:
	@for f in $(BIN_SCRIPTS); do \
		bash $$f --help >/dev/null; \
	done
	@echo "Smoke tests complete"
