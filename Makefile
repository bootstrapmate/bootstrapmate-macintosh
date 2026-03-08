#!/usr/bin/make -f
#
# BootstrapMate Build System
# Builds, signs, and notarizes macOS installer package
#

# Load environment variables from .env file if it exists
-include .env
export

# Version from environment or generate timestamp (evaluated once at parse time)
VERSION := $(or $(VERSION),$(shell date '+%Y.%m.%d.%H%M'))

# Split VERSION into marketing version (date) and build number (time) for macOS About box.
# VERSION=2026.03.07.1012 → MARKETING_VERSION=2026.03.07, BUILD_NUMBER=1012
# This prevents macOS from showing "2026.03.07.1012 (2026.03.07.1012)" and instead
# displays "2026.03.07 (1012)". The full VERSION is still used for the CLI and pkg.
MARKETING_VERSION := $(shell echo $(VERSION) | sed 's/\.[^.]*$$//')
BUILD_NUMBER := $(shell echo $(VERSION) | sed 's/.*\.//')

# Paths
BUILD_DIR = build
PKG_ROOT = $(BUILD_DIR)/pkg-root
PACKAGING_DIR = packaging
SCRIPTS_DIR = $(BUILD_DIR)/scripts
BINARY_NAME = installapplications
GUI_BINARY_NAME = BootstrapMateGUI
HELPER_BINARY_NAME = BootstrapMateHelper
BINARY_INSTALL_PATH = usr/local/bootstrapmate
APP_BUNDLE_PATH = Applications/Utilities/BootstrapMate.app
APP_MACOS_DIR = $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/MacOS
APP_RESOURCES_DIR = $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/Resources
APP_HELPER_LD_DIR = $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/Library/LaunchDaemons

# Icon
ICON_DIR = resources/BootstrapMate.icon
ICON_NAME = BootstrapMate
ACTOOL_OUT = $(BUILD_DIR)/actool-out

# Swift Build Configuration
SWIFT_BUILD_DIR = .build/apple/Products/Release
SWIFT_BINARY = $(SWIFT_BUILD_DIR)/bootstrapmate
SWIFT_GUI_BINARY = $(SWIFT_BUILD_DIR)/BootstrapMateApp
SWIFT_HELPER_BINARY = $(SWIFT_BUILD_DIR)/BootstrapMateHelper

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

.PHONY: all build clean swift-build copy-binary create-app-bundle compile-icon sign-app build-pkg sign-pkg notarize-pkg verify help check-signing-config

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
	@echo "  Create a .env file (see examples/.env.example) with your signing credentials"
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
		echo "$(YELLOW)Please create a .env file (see examples/.env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(SIGNING_IDENTITY_PKG)" ]; then \
		echo "$(RED)✗ Error: SIGNING_IDENTITY_PKG not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see examples/.env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARIZATION_PROFILE)" ] && [ -z "$(NOTARIZATION_APPLE_ID)" ]; then \
		echo "$(RED)✗ Error: NOTARIZATION_PROFILE or NOTARIZATION_APPLE_ID not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see examples/.env.example) or set environment variables$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(NOTARIZATION_TEAM_ID)" ] && [ -z "$(NOTARIZATION_PROFILE)" ]; then \
		echo "$(RED)✗ Error: NOTARIZATION_TEAM_ID not set$(NC)"; \
		echo "$(YELLOW)Please create a .env file (see examples/.env.example) or set environment variables$(NC)"; \
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
	@echo "$(BLUE)Signing and copying binaries to app bundle...$(NC)"
	@mkdir -p $(APP_MACOS_DIR)
	
	# Sign the CLI binary with hardened runtime before packaging
	@codesign --force --sign "$(SIGNING_IDENTITY_APP)" \
		--options runtime \
		--timestamp \
		--identifier com.github.bootstrapmate.installapplications \
		$(SWIFT_BINARY)
	
	# Sign the GUI binary
	@codesign --force --sign "$(SIGNING_IDENTITY_APP)" \
		--options runtime \
		--timestamp \
		--identifier com.github.bootstrapmate.gui \
		$(SWIFT_GUI_BINARY)
	
	# Sign the Helper binary
	@codesign --force --sign "$(SIGNING_IDENTITY_APP)" \
		--options runtime \
		--timestamp \
		--identifier com.github.bootstrapmate.helper \
		$(SWIFT_HELPER_BINARY)
	
	# Copy all binaries to app bundle MacOS directory
	@cp $(SWIFT_BINARY) $(APP_MACOS_DIR)/$(BINARY_NAME)
	@chmod 755 $(APP_MACOS_DIR)/$(BINARY_NAME)
	@cp $(SWIFT_GUI_BINARY) $(APP_MACOS_DIR)/$(GUI_BINARY_NAME)
	@chmod 755 $(APP_MACOS_DIR)/$(GUI_BINARY_NAME)
	@cp $(SWIFT_HELPER_BINARY) $(APP_MACOS_DIR)/$(HELPER_BINARY_NAME)
	@chmod 755 $(APP_MACOS_DIR)/$(HELPER_BINARY_NAME)
	
	# Create placeholder for symlink directory
	@mkdir -p $(PKG_ROOT)/$(BINARY_INSTALL_PATH)
	@touch $(PKG_ROOT)/$(BINARY_INSTALL_PATH)/.placeholder
	@echo "$(GREEN)✓ Binaries signed and copied to app bundle$(NC)"

compile-icon:
	@echo "$(BLUE)Compiling icon bundle with actool...$(NC)"
	@mkdir -p $(ACTOOL_OUT)
	@xcrun actool \
		--compile $(ACTOOL_OUT) \
		--platform macosx \
		--minimum-deployment-target 13.0 \
		--app-icon $(ICON_NAME) \
		--output-partial-info-plist $(ACTOOL_OUT)/partial-info.plist \
		--warnings --errors \
		$(ICON_DIR) > /dev/null
	@echo "$(GREEN)✓ Icon compiled: Assets.car + $(ICON_NAME).icns$(NC)"

create-app-bundle: copy-binary compile-icon
	@echo "$(BLUE)Creating app bundle...$(NC)"
	@mkdir -p $(APP_RESOURCES_DIR)
	@rm -rf $(APP_RESOURCES_DIR)/*
	
	# Copy Info.plist template and substitute version placeholders
	@sed -e 's/{{MARKETING_VERSION}}/$(MARKETING_VERSION)/g' \
	     -e 's/{{BUILD_NUMBER}}/$(BUILD_NUMBER)/g' \
	     $(PACKAGING_DIR)/resources/Info.plist.template > $(PKG_ROOT)/$(APP_BUNDLE_PATH)/Contents/Info.plist
	
	# Copy compiled Assets.car (contains Liquid Glass icon for macOS 26+)
	@cp $(ACTOOL_OUT)/Assets.car $(APP_RESOURCES_DIR)/Assets.car
	
	# Copy .icns fallback (macOS 13–25) - composited by actool, not a raw layer PNG
	@cp $(ACTOOL_OUT)/$(ICON_NAME).icns $(APP_RESOURCES_DIR)/$(ICON_NAME).icns
	
	@echo "$(GREEN)✓ App bundle created$(NC)"

create-launchdaemon: create-app-bundle
	@echo "$(BLUE)Copying LaunchDaemon plists...$(NC)"
	@mkdir -p $(PKG_ROOT)/Library/LaunchDaemons
	@mkdir -p $(SCRIPTS_DIR)
	@mkdir -p $(APP_HELPER_LD_DIR)
	@cp $(PACKAGING_DIR)/LaunchDaemons/com.github.bootstrapmate.plist $(PKG_ROOT)/Library/LaunchDaemons/
	@cp $(PACKAGING_DIR)/LaunchDaemons/com.github.bootstrapmate.helper.plist $(APP_HELPER_LD_DIR)/
	@cp $(PACKAGING_DIR)/scripts/postinstall $(SCRIPTS_DIR)/
	@chmod +x $(SCRIPTS_DIR)/postinstall
	@echo "$(GREEN)✓ LaunchDaemon plists and scripts copied$(NC)"

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
	# Generate component plist and disable bundle relocation to prevent
	# macOS installer from moving the app when upgrading from a different pkg ID.
	# Disable version checking so the split version format (3-component marketing
	# + build number) doesn't fail comparison against older 4-component versions.
	@pkgbuild --analyze --root $(PKG_ROOT) $(BUILD_DIR)/component.plist
	@/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" $(BUILD_DIR)/component.plist
	@/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked false" $(BUILD_DIR)/component.plist
	@pkgbuild \
		--root $(PKG_ROOT) \
		--component-plist $(BUILD_DIR)/component.plist \
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
	@if [ -n "$(NOTARIZATION_PROFILE)" ]; then \
		xcrun notarytool submit $(PKG_OUTPUT) \
			--keychain-profile "$(NOTARIZATION_PROFILE)" \
			--wait; \
	elif [ -n "$(NOTARIZATION_APPLE_ID)" ] && [ -n "$(NOTARIZATION_PASSWORD)" ]; then \
		xcrun notarytool submit $(PKG_OUTPUT) \
			--apple-id "$(NOTARIZATION_APPLE_ID)" \
			--password "$(NOTARIZATION_PASSWORD)" \
			--team-id "$(NOTARIZATION_TEAM_ID)" \
			--wait; \
	else \
		echo "$(RED)Error: Set NOTARIZATION_PROFILE or NOTARIZATION_APPLE_ID + NOTARIZATION_PASSWORD$(NC)"; \
		exit 1; \
	fi
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

