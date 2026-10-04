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

## Requirements

macOS 14 or later, on the Macs it runs on. The settings app uses the Observation framework and SwiftUI APIs that first shipped in macOS 14, so that is the lowest release the package can build for. Nothing needs macOS 15. The floor is set in `Package.swift`, as `LSMinimumSystemVersion` in `packaging/resources/Info.plist.template`, and in `packaging/scripts/preinstall`, which refuses the install on an older Mac rather than leaving a daemon there that cannot launch. A unit test fails if the three disagree.

## Versioning

BootstrapMate uses date-based versioning: `YYYY.MM.DD.HHMM`

Examples:
- `2026.02.08.2230` - Built February 8, 2026 at 22:30 UTC
- Auto-generated from build timestamp unless `VERSION` is specified

Check installed version:
```bash
/usr/local/bootstrapmate/managedbootstrapinstall --version
```

## Building

### Prerequisites

- macOS 14 or later
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

## Manifest item fields

Every item in `preflight`, `setupassistant` and `userland` takes the same fields. `examples/manifest.yaml` and `examples/manifest.json` show each one in use.

| Field | Required | Default | Meaning |
|---|---|---|---|
| `file` | yes | | Absolute path the item is downloaded to on the Mac. |
| `hash` | yes | | SHA-256 of the file. A file already on disk with this hash is not downloaded again. |
| `url` | yes | | Where the file is downloaded from. |
| `type` | yes | | `rootscript`, `package` or `userscript`. |
| `name` | no | the file path | Label shown in logs and the dialog. |
| `packageid`, `version` | no | | A package whose receipt shows this version or newer is skipped. |
| `retries` | no | `3` | Download attempts before the item fails. |
| `retrywait` | no | `5` | Seconds between download attempts. |
| `followRedirects` | no | the run-wide setting | `false` refuses HTTP redirects for this item's download; `true` follows them. |
| `skipIf` | no | | `arm64` or `x86_64`: skip the item on that architecture. |
| `donotwait` | no | `false` | Start a script and move on without waiting for it to finish. |
| `baseline` | no | `true` | Set `false` to leave the item out of baseline runs. |

## Dry run

`managedbootstrapinstall --dry-run` (or the `dryRun` managed preference) rehearses a manifest against a real Mac without changing it. Every item is downloaded and its hash checked, and every package's signature is checked, so a broken URL, a stale hash or an untrusted package fails the rehearsal just as it would fail a real run. Nothing is installed, no script runs (preflight included), nothing is added to the install ledger, and the run does not reboot, post a report, mark the Mac complete or remove its LaunchDaemon. Because the preflight does not run, a dry run always rehearses the full provisioning path. Items are logged as `[Dry Run] Would install` or `[Dry Run] Would run`, recorded as skipped, and the session's run type is `dry-run`.

## HTTP redirects

Redirects are followed by default, for the manifest and for every item. Set the `followRedirects` managed preference to `false`, or pass `--no-follow-redirects`, to refuse them: a redirected download then fails with the 3xx status and the address it pointed to, instead of fetching from wherever the redirect leads. An item's own `followRedirects` field overrides the run-wide setting for that item.

## Preflight exit codes

The preflight rootscript decides what the rest of the run does:

| Exit code | Mode | What runs |
|---|---|---|
| `0` | Skip | Nothing. The run ends and the one-shot LaunchDaemon removes itself. |
| `2` | Baseline | `setupassistant` items, with no SwiftDialog window, no `userland` stage and no reboot. |
| any other positive | Provision | The full bootstrap: `setupassistant`, then `userland`. |

Baseline mode is for a machine that is already provisioned and in use. It brings the tooling in the manifest back to the published versions without provisioning the machine again. Packages that carry `packageid` and `version` are skipped when that version or newer is installed. BootstrapMate also keeps a ledger of the package files it has installed, by hash, in `/Library/Managed Bootstrap/installed.json`, and a baseline run skips any file already in it. That covers payload-free packages, which leave no receipt, and entries whose `packageid` does not match the receipt. A baseline run on a current machine installs nothing. An item leaves itself out of baseline runs with `"baseline": false`.

Root scripts run with `BOOTSTRAPMATE_BASELINE_EXIT_CODE` set in their environment. A preflight that may be run by an older build checks for it before asking for baseline, because a build without baseline mode treats exit `2` as Provision.

The SwiftDialog window opens only after the preflight has chosen Provision, so Skip and Baseline runs never show one.

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

### Session run type

Each run's `session.json` carries a `run_type` set from the preflight's decision: `skip`, `baseline` or `provisioning`. A run with no preflight, or whose preflight failed, stays `provisioning`.

### Last-run summary

Every run also keeps a summary of itself at `/Library/Managed Bootstrap/last-run.json`, outside the log directories so retention never removes it. It is written when the run starts with status `running`, so a run that crashes or is killed still leaves a record, and rewritten atomically when the run ends.

```json
{
  "session_id": "2026-10-04-120045",
  "run_type": "provisioning",
  "status": "partial_failure",
  "tool_version": "2026.10.04.1200",
  "start_time": "2026-10-04T19:00:45.738Z",
  "end_time": "2026-10-04T19:15:47.754Z",
  "duration_seconds": 902,
  "errors": 1,
  "warnings": 0,
  "items": [
    { "name": "Tools", "stage": "setupassistant", "result": "installed" },
    { "name": "Agent", "stage": "setupassistant", "result": "failed", "error": "Download failed" }
  ]
}
```

`status` uses the same values as `session.json`: `running`, `completed`, `partial_failure` or `failed`. Each item's `stage` is `setupassistant` or `userland`, its `result` is `installed`, `skipped` or `failed`, and `error` is present only on failures.

`managedbootstrapinstall --last-run` prints the record as one line of at most 1000 characters, suited to an MDM custom attribute or a script result. The time is the end time, or the start time while a run is going, in UTC to the minute. It prints `no run recorded` when there is no file, and always exits 0.

```
2026-10-04T19:15Z provisioning partial_failure v2026.10.04.1200 installed=1 skipped=0 failed=1: Agent: Download failed
```

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
