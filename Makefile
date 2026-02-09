#!/usr/bin/make -f
#
# BootstrapMate Build System
# Builds, signs, and notarizes macOS installer package
#

# Load environment variables from .env file if it exists
-include .env
export

# Version from environment or generate timestamp
VERSION ?= $(shell date '+%Y.%m.%d.%H%M')

# Paths
BUILD_DIR = build
PKG_ROOT = $(BUILD_DIR)/pkg-root
PACKAGING_DIR = packaging
SCRIPTS_DIR = $(BUILD_DIR)/scripts
BINARY_NAME = installapplications
BINARY_INSTALL_PATH = usr/local/bootstrapmate
APP_BUNDLE_PATH = Applications/Utilities/BootstrapMate.app
APP_MACOS_DIR = $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/MacOS
APP_RESOURCES_DIR = $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/Resources

# Swift Build Configuration
SWIFT_BUILD_DIR = .build/apple/Products/Release
SWIFT_BINARY = $(SWIFT_BUILD_DIR)/bootstrapmate

# Package Configuration
PKG_ID = com.github.bootstrapmate
PKG_NAME = BootstrapMate-$(VERSION).pkg
PKG_OUTPUT = $(BUILD_DIR)/$(PKG_NAME)

# Signing Configuration (must be set via .env file or environment variables)
# SIGNING_IDENTITY_APP - Developer ID Application certificate
# SIGNING_IDENTITY_PKG - Developer ID Installer certificate  
# NOTARIZATION_PROFILE - Notarytool keychain profile name
# NOTARIZATION_TEAM_ID - Apple Developer Team ID

# Colors
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m

.PHONY: all build clean swift-build copy-binary create-app-bundle sign-app build-pkg sign-pkg notarize-pkg verify help check-signing-config

all: build

help:
	@echo "BootstrapMate Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build          - Build, sign, and notarize complete package (default)"
	@echo "  swift-build    - Compile Swift binary only"
	@echo "  copy-binary    - Copy binary to package structure"
	@echo "  create-app-bundle - Create GUI app launcher"
	@echo "  sign-app       - Sign the app bundle"
	@echo "  build-pkg      - Build installer package"
	@echo "  sign-pkg       - Sign installer package"
	@echo "  notarize-pkg   - Notarize and staple package"
	@echo "  verify         - Verify signature and notarization"
	@echo "  clean          - Remove build artifacts"
	@echo ""
	@echo "Configuration:"
	@echo "  Create a .env file (see .env.example) with your signing credentials"
	@echo "  Or set environment variables directly when running make"
	@echo ""
	@echo "Required Variables (set in .env or environment):"
	@echo "  SIGNING_IDENTITY_APP    - Developer ID Application cert"
	@echo "  SIGNING_IDENTITY_PKG    - Developer ID Installer cert"
	@echo "  NOTARIZATION_PROFILE    - Notarytool profile name"
	@echo "  NOTARIZATION_TEAM_ID    - Apple Developer Team ID"
	@echo ""
	@echo "Optional Variables:"
	@echo "  VERSION                 - Package version (default: timestamp)"

check-signing-config:
	@if [ -z "$(SIGNING_IDENTITY_APP)" ]; then \
		echo "$(RED)✗ Error: SIGNING_IDENTITY_APP not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see .env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SIGNING_IDENTITY_PKG)" ]; then \
		echo "$(RED)✗ Error: SIGNING_IDENTITY_PKG not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see .env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARIZATION_PROFILE)" ]; then \
		echo "$(RED)✗ Error: NOTARIZATION_PROFILE not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see .env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARIZATION_TEAM_ID)" ]; then \
		echo "$(RED)✗ Error: NOTARIZATION_TEAM_ID not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see .env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Signing configuration validated$(NC)"

build: check-signing-config swift-build copy-binary create-app-bundle create-launchdaemon sign-app build-pkg sign-pkg notarize-pkg verify
	@echo "$(GREEN)✓ Build complete: $(PKG_OUTPUT)$(NC)"

swift-build:
	@echo "$(BLUE)Building Swift binary (universal)...$(NC)"
	swift build -c release --arch arm64 --arch x86_64
	@echo "$(GREEN)✓ Swift build complete$(NC)"

copy-binary: swift-build
	@echo "$(BLUE)Signing and copying binary to app bundle...$(NC)"
	@mkdir -p $(APP_MACOS_DIR)
	
	# Sign the binary with hardened runtime before packaging
	@codesign --force --sign "$(SIGNING_IDENTITY_APP)" \
		--options runtime \
		--timestamp \
		--identifier com.github.bootstrapmate.installapplications \
		$(SWIFT_BINARY)
	
	# Copy binary to app bundle MacOS directory
	@cp $(SWIFT_BINARY) $(APP_MACOS_DIR)/$(BINARY_NAME)
	@chmod 755 $(APP_MACOS_DIR)/$(BINARY_NAME)
	
	# Create placeholder for symlink directory
	@mkdir -p $(PKG_ROOT)/$(BINARY_INSTALL_PATH)
	@touch $(PKG_ROOT)/$(BINARY_INSTALL_PATH)/.placeholder
	@echo "$(GREEN)✓ Binary signed and copied to app bundle$(NC)"

create-app-bundle: copy-binary
	@echo "$(BLUE)Creating app bundle Info.plist...$(NC)"
	@mkdir -p $(APP_RESOURCES_DIR)
	
	# Copy Info.plist template and substitute version
	@sed 's/{{VERSION}}/$(VERSION)/g' $(PACKAGING_DIR)/resources/Info.plist.template > $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/Info.plist
	
	@echo "$(GREEN)✓ App bundle created$(NC)"

create-launchdaemon: create-app-bundle
	@echo "$(BLUE)Copying LaunchDaemon plist...$(NC)"
	@mkdir -p $(PKG_ROOT)/Library/LaunchDaemons
	@mkdir -p $(SCRIPTS_DIR)
	@cp $(PACKAGING_DIR)/LaunchDaemons/com.github.bootstrapmate.plist $(PKG_ROOT)/Library/LaunchDaemons/
	@cp $(PACKAGING_DIR)/scripts/postinstall $(SCRIPTS_DIR)/
	@chmod +x $(SCRIPTS_DIR)/postinstall
	@echo "$(GREEN)✓ LaunchDaemon and scripts copied$(NC)"

sign-app: create-launchdaemon
	@echo "$(BLUE)Signing app bundle...$(NC)"
	@codesign --force --sign "$(SIGNING_IDENTITY_APP)" \
		--options runtime \
		--timestamp \
		--deep \
		$(PKG_ROOT)/$(APP_BUNDLE_PATH)
	@echo "$(GREEN)✓ App bundle signed$(NC)"

build-pkg: sign-app
	@echo "$(BLUE)Building installer package...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@pkgbuild \
		--root $(PKG_ROOT) \
		--identifier $(PKG_ID) \
		--version $(VERSION) \
		--scripts $(SCRIPTS_DIR) \
		$(PKG_OUTPUT)
	@echo "$(GREEN)✓ Package built: $(PKG_OUTPUT)$(NC)"

sign-pkg: build-pkg
	@echo "$(BLUE)Signing installer package...$(NC)"
	@productsign \
		--sign "$(SIGNING_IDENTITY_PKG)" \
		--timestamp \
		$(PKG_OUTPUT) \
		$(PKG_OUTPUT).signed
	@mv $(PKG_OUTPUT).signed $(PKG_OUTPUT)
	@echo "$(GREEN)✓ Package signed$(NC)"

notarize-pkg: sign-pkg
	@echo "$(BLUE)Notarizing package (this may take several minutes)...$(NC)"
	@xcrun notarytool submit $(PKG_OUTPUT) \
		--keychain-profile "$(NOTARIZATION_PROFILE)" \
		--wait
	@echo "$(BLUE)Stapling notarization ticket...$(NC)"
	@xcrun stapler staple $(PKG_OUTPUT)
	@echo "$(GREEN)✓ Package notarized and stapled$(NC)"

verify:
	@echo "$(BLUE)Verifying package security...$(NC)"
	@echo ""
	@echo "Signature verification:"
	@pkgutil --check-signature $(PKG_OUTPUT) || (echo "$(RED)✗ Package is not signed$(NC)" && exit 1)
	@echo ""
	@echo "Notarization verification:"
	@xcrun stapler validate $(PKG_OUTPUT) || (echo "$(RED)✗ Package is not notarized$(NC)" && exit 1)
	@echo ""
	@echo "Gatekeeper assessment:"
	@spctl --assess --type install $(PKG_OUTPUT) || (echo "$(RED)✗ Package will not pass Gatekeeper$(NC)" && exit 1)
	@echo ""
	@echo "$(GREEN)✓ All security checks passed$(NC)"

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR) || true
	@chmod -R u+w .build 2>/dev/null || true
	@rm -rf .build || true
	@echo "$(GREEN)✓ Clean complete$(NC)"

