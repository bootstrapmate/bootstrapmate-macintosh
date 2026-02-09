# BootstrapMate

A macOS bootstrap orchestration tool for automated device provisioning.

## Features

- Universal binary (arm64 + x86_64)
- Automated package installation from JSON manifest
- SwiftDialog integration for UI feedback
- Session tracking and resume capability
- Network-aware with retry logic
- LaunchDaemon for automatic execution
- Comprehensive logging

## Versioning

BootstrapMate uses date-based versioning: `YYYY.MM.DD.HHMM`

Examples:
- `2026.02.08.2230` - Built February 8, 2026 at 22:30 UTC
- Auto-generated from build timestamp unless `VERSION` is specified

Check installed version:
```bash
/usr/local/bootstrapmate/installapplications --version
```

## Building

### Prerequisites

- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 6.0 or later
- Apple Developer ID certificates for signing

### Configuration

BootstrapMate uses environment variables for signing configuration. These should **never** be committed to the repository.

#### Setup

1. Copy the example environment file:
   ```bash
   cp resources/.env.example .env
   ```

2. Edit `.env` with your Apple Developer credentials:
   ```bash
   # Your Developer ID Application certificate
   SIGNING_IDENTITY_APP=Developer ID Application: Your Name (TEAM_ID)
   
   # Your Developer ID Installer certificate
   SIGNING_IDENTITY_PKG=Developer ID Installer: Your Name (TEAM_ID)
   
   # Your notarization credentials profile
   NOTARIZATION_PROFILE=your_profile_name
   
   # Your Apple Developer Team ID
   NOTARIZATION_TEAM_ID=YOUR_TEAM_ID
   ```

3. **Important:** The `.env` file is excluded from git by `.gitignore` to protect your credentials

#### Finding Your Credentials

- **Signing Identities:** Run `security find-identity -v -p codesigning` to list available certificates
- **Team ID:** Found in your Apple Developer account or in the certificate name
- **Notarization Profile:** Create with `xcrun notarytool store-credentials`

### Building the Package

Build the complete signed and notarized installer:

```bash
make build
```

This will:
1. Compile the Swift binary (universal: arm64 + x86_64)
2. Create the app bundle structure
3. Sign the binary and app bundle
4. Build the installer package
5. Sign the installer package
6. Notarize with Apple
7. Staple the notarization ticket
8. Verify all signatures

### Make Targets

- `make help` - Show all available targets
- `make swift-build` - Compile Swift binary only
- `make build-pkg` - Build unsigned package
- `make sign-pkg` - Sign the package
- `make verify` - Verify signatures and notarization
- `make clean` - Remove build artifacts

### Alternative: Command-Line Variables

Instead of using a `.env` file, you can pass variables directly:

```bash
make build \
  SIGNING_IDENTITY_APP="Developer ID Application: Your Name (TEAM_ID)" \
  SIGNING_IDENTITY_PKG="Developer ID Installer: Your Name (TEAM_ID)" \
  NOTARIZATION_PROFILE="your_profile" \
  NOTARIZATION_TEAM_ID="YOUR_TEAM_ID"
```

## Development

### Project Structure

```
Sources/
  BootstrapMateCore/      - Core library code
    Managers/             - Business logic managers
    Utilities/            - Shared utilities and constants
  BootstrapMateCLI/       - Command-line executable
Tests/
  BootstrapMateCoreTests/ - Test suite
packaging/                - Installer source files
  scripts/                - Postinstall scripts
  LaunchDaemons/          - LaunchDaemon plist
  resources/              - App bundle resources
resources/                - Examples and helper scripts
  .env.example            - Environment configuration template
  preflight.sh            - Pre-bootstrap device validation script
  setup-credentials.example.sh - Credentials setup example
  setup-notarization.sh   - Notarization setup helper
```

### Testing

```bash
# Run tests
swift test

# Build debug version
swift build

# Build release (universal)
swift build -c release --arch arm64 --arch x86_64
```

### Version Control

The following files should **never** be committed:
- `.env` - Contains your private credentials (blocked by .gitignore)

The following files **should** be committed:
- `resources/.env.example` - Template for other developers
- `Makefile` - Contains no sensitive information

## Security

All signing identities, team IDs, and notarization credentials are kept in the `.env` file or environment variables. The repository contains no hardcoded credentials.
