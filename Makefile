# Makefile for BootstrapMate
# Convenience wrapper for common build tasks

.PHONY: help build build-dev clean test install

# Default shell
SHELL := /bin/zsh

# Version - auto-generated from date/time format YYYY.MM.DD.HHMM
# Override with: make build VERSION=2026.02.02.2217
VERSION ?= $(shell date '+%Y.%m.%d.%H%M')

# Signing identities (override or set via environment)
SIGN_APP ?= $(SIGNING_IDENTITY_APP)
SIGN_PKG ?= $(SIGNING_IDENTITY_PKG)
BUNDLE ?= $(BUNDLE_ID)

help:
	@echo "BootstrapMate Build Targets:"
	@echo ""
	@echo "  make build              Build signed package (requires certificates)"
	@echo "  make build-dev          Build unsigned package (for testing)"
	@echo "  make build-debug        Build debug binary only"
	@echo "  make clean              Remove build artifacts"
	@echo "  make test               Run tests"
	@echo "  make install            Install built package locally"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION=YYYY.MM.DD.HHMM Specify version (auto-generated if not provided)"
	@echo "  SIGN_APP=\"identity\"    Code signing identity"
	@echo "  SIGN_PKG=\"identity\"    Package signing identity"
	@echo "  BUNDLE=\"com.example\"   Bundle identifier"
	@echo ""
	@echo "Examples:"
	@echo "  make build-dev          # Auto-generates version like 2026.02.02.2217"
	@echo "  make build VERSION=2026.02.02.2217 SIGN_APP=\"Developer ID Application: Me\""
	@echo ""

build:
	@echo "Building BootstrapMate v$(VERSION)..."
	@if [ -n "$(SIGN_APP)" ] && [ -n "$(SIGN_PKG)" ]; then \
		./build.sh $(VERSION) --sign-app "$(SIGN_APP)" --sign-pkg "$(SIGN_PKG)"; \
	else \
		echo "Warning: No signing identities set. Building unsigned."; \
		./build.sh $(VERSION) --skip-sign; \
	fi

build-dev:
	@echo "Building BootstrapMate v$(VERSION) (unsigned)..."
	./build.sh $(VERSION) --skip-sign

build-debug:
	@echo "Building debug binary..."
	swift build
	@echo ""
	@echo "Binary: .build/debug/installapplications"
	@echo "Run with: .build/debug/installapplications --help"

clean:
	@echo "Cleaning build artifacts..."
	rm -rf .build
	rm -rf build
	rm -rf DerivedData
	rm -f *.pkg
	@echo "✓ Clean"

test:
	@echo "Running tests..."
	swift test

install:
	@if [ ! -f "build/BootstrapMate-$(VERSION).pkg" ]; then \
		echo "Error: Package not found. Run 'make build' or 'make build-dev' first."; \
		exit 1; \
	fi
	@echo "Installing BootstrapMate v$(VERSION)..."
	sudo installer -pkg build/BootstrapMate-$(VERSION).pkg -target /
	@echo ""
	@echo "Verifying installation..."
	@ls -la /Applications/Utilities/BootstrapMate.app/Contents/MacOS/
	@installapplications --version

uninstall:
	@echo "Uninstalling BootstrapMate..."
	@sudo launchctl unload /Library/LaunchDaemons/com.github.bootstrapmate.plist 2>/dev/null || true
	@sudo rm -f /Library/LaunchDaemons/com.github.bootstrapmate.plist
	@sudo rm -rf /Applications/Utilities/BootstrapMate.app
	@sudo rm -rf /usr/local/bootstrapmate
	@sudo rm -f /etc/paths.d/bootstrapmate
	@sudo rm -rf "/Library/Managed Bootstrap"
	@echo "✓ Uninstalled"

verify:
	@if [ ! -f "build/BootstrapMate-$(VERSION).pkg" ]; then \
		echo "Error: Package not found. Run 'make build' first."; \
		exit 1; \
	fi
	@echo "Verifying package signature and notarization..."
	@echo ""
	@echo "=== Signature ==="
	pkgutil --check-signature build/BootstrapMate-$(VERSION).pkg || echo "Not signed"
	@echo ""
	@if command -v xcrun &> /dev/null; then \
		echo "=== Notarization ==="; \
		xcrun stapler validate build/BootstrapMate-$(VERSION).pkg 2>/dev/null || echo "Not notarized"; \
		echo ""; \
		echo "=== Gatekeeper Assessment ==="; \
		spctl -a -vv -t install build/BootstrapMate-$(VERSION).pkg 2>&1 || echo "Will not pass Gatekeeper"; \
	fi

