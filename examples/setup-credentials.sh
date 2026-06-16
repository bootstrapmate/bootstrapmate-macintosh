#!/bin/zsh

# BootstrapMate Build Configuration - Example
# Copy this file and customize for your organization
#
# Usage:
#   1. Copy to setup-credentials.sh (or similar)
#   2. Update with your certificates and Team ID
#   3. source setup-credentials.sh
#   4. Run: ./build.sh 1.0.0

# Code signing certificate (Developer ID Application)
export SIGNING_IDENTITY_APP="Developer ID Application: Your Organization (TEAMID)"

# Package signing certificate (Developer ID Installer)
export SIGNING_IDENTITY_PKG="Developer ID Installer: Your Organization (TEAMID)"

# Bundle identifier (use your organization's domain)
export BUNDLE_ID="com.yourorg.bootstrapmate"

# Notarization credentials (required for distribution)
export NOTARIZATION_APPLE_ID="your@apple.id"
export NOTARIZATION_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # App-specific password from appleid.apple.com
export NOTARIZATION_TEAM_ID="TEAMID"

# Optional: Custom keychain path
# export SIGNING_KEYCHAIN="${HOME}/Library/Keychains/custom.keychain-db"

echo "Build environment configured:"
echo "  Bundle ID: ${BUNDLE_ID}"
echo "  App signing: ${SIGNING_IDENTITY_APP}"
echo "  Pkg signing: ${SIGNING_IDENTITY_PKG}"
echo "  Team ID: ${NOTARIZATION_TEAM_ID}"
echo ""
echo "Ready to build:"
echo "  ./build.sh 1.0.0"
echo ""
