# BootstrapMate

A bootstrapping tool for Mac device provisioning that downloads and installs packages during Remote Management enrollment in Setup Assistant or after user login.

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
   cp examples/.env.example .env
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
resources/                - Build assets (icons, tooling scripts)
  BootstrapMate.icon/     - App icon source assets
  setup-notarization.sh   - Notarization setup helper
examples/                 - Configuration and manifest examples
  manifest.json           - Example JSON bootstrap manifest
  manifest.yaml           - Example YAML bootstrap manifest
  BootstrapMate-Config.mobileconfig - Example MDM configuration profile
  preflight.sh            - Example pre-bootstrap device validation script
  .env.example            - Environment configuration template
  setup-credentials.example.sh - Build credentials setup example
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
- `examples/.env.example` - Template for other developers
- `Makefile` - Contains no sensitive information

## Security

All signing identities, team IDs, and notarization credentials are kept in the `.env` file or environment variables. The repository contains no hardcoded credentials.

## Reporting

When a run completes, BootstrapMate can POST a vendor-neutral JSON run summary to an optional endpoint, turning "did this Mac provision cleanly?" into a fleet-dashboard query. The payload is plain JSON and not tied to any specific backend — any service that accepts a JSON POST (a custom collector, ReportMate, MunkiReport, etc.) can consume it.

Configure via managed preferences (`com.github.bootstrapmate`) or the `--reporting-url` CLI flag:

| Key | Type | Effect |
|---|---|---|
| `reportingUrl` | string | Endpoint to POST the run summary to. When unset, no report is sent. |
| `reportingHeader` | string | Optional `Authorization` header value sent with the POST. |

The POST is best-effort: it is bounded by a short timeout and never fails the run. Payload fields include `tool`, `platform`, `version`, `runId`, `success`, `startTime`/`endTime`, `durationSeconds`, `architecture`, `hostname`, `serialNumber`, `manifestUrl`, and per-phase outcomes (keyed `Preflight`/`SetupAssistant`/`Userland`, each with stage, exit code, and any error).
### Package signature verification

Before any installer package is handed to `/usr/sbin/installer` (which runs as root), BootstrapMate verifies its code-signing provenance with `pkgutil --check-signature`. The manifest SHA-256 only proves a download matches the manifest — it does not prove the manifest itself is authentic. The signature gate ensures a package was produced by a trusted Apple Developer ID before it executes.

Behaviour is controlled by managed preferences (MDM profile), CLI flags, or per-item manifest fields.

Managed-preference keys (domain `com.github.bootstrapmate`):

| Key | Type | Default | Effect |
|---|---|---|---|
| `verifyPackageSignatures` | bool | `true` | Verify every installer package before running it. |
| `expectedTeamID` | string | _unset_ | Require packages to be signed by this 10-character Apple Team ID. When unset, any signature trusted by macOS is accepted. |
| `allowUnsigned` | bool | `false` | Permit unsigned/untrusted packages (logged as a warning). A Team-ID *mismatch* is never permitted, even with this set. |

CLI equivalents: `--no-verify-signature`, `--expected-team-id <TEAMID>`, `--allow-unsigned`.

Per-item manifest overrides (fall back to the global config): `expectedTeamID`, `allowUnsigned`.
