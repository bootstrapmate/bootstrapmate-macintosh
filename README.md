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

## Install layout

The package installs `/Applications/Utilities/Managed Bootstrap Install.app`. The bundle holds the CLI `managedbootstrapinstall`, the settings app and the privileged helper. The CLI is also linked at `/usr/local/bin/managedbootstrapinstall` and at `/usr/local/bootstrapmate/managedbootstrapinstall`. The LaunchDaemon label `com.github.bootstrapmate`, the bundle identifier, the preference domain and everything under `/Library/Managed Bootstrap` (logs, cache, `installed.json`, `last-run.json`) keep their names.

Builds before the rename installed the app as `/Applications/Utilities/BootstrapMate.app`. An upgrade removes that bundle in the postinstall, after the new CLI is in place and both daemons have been reloaded from the new bundle, so a Mac never has two apps. Scripts that look for the CLI should use `/usr/local/bin/managedbootstrapinstall`, which works for both layouts.

## Versioning

BootstrapMate uses date-based versioning: `YYYY.MM.DD.HHMM`

Examples:
- `2026.02.08.2230` - Built February 8, 2026 at 22:30 UTC
- Auto-generated from build timestamp unless `VERSION` is specified

`--version`, `tool_version` in `session.json` and `last-run.json`, and the report all give the installed build's version, read from the app bundle's `Info.plist` (`CFBundleShortVersionString` plus `CFBundleVersion`). A binary run outside the bundle falls back to the version the Makefile or release workflow stamped in at build time, or `dev` for a plain `swift build`.

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
| `retries` | no | `3` | Download attempts before the item fails, at most 5 in one run. |
| `retrywait` | no | `5` | Seconds between download attempts, at most 60. |
| `followRedirects` | no | the run-wide setting | `false` refuses HTTP redirects for this item's download; `true` follows them. |
| `skipIf` | no | | `arm64` or `x86_64`: skip the item on that architecture. |
| `donotwait` | no | `false` | Start a script and move on without waiting for it to finish. |
| `baseline` | no | `true` | Set `false` to leave the item out of baseline runs. |

## Baseline throttle

A baseline run may download payloads, so it must not repeat sooner than intended. BootstrapMate records the outcome of each baseline run in `/Library/Managed Bootstrap/baseline.json`. The throttle applies only after the preflight has chosen baseline mode. The manifest and the preflight script are still fetched, which is small, but a throttled baseline downloads and installs no items. A Mac whose preflight chooses provisioning, for example one put back on a provisioning manifest, always provisions, however recent its last baseline:

- After a completed baseline, the next run waits `baselineMinIntervalHours` (default 144, six days, so a weekly schedule still runs every time).
- A new BootstrapMate always runs its baseline. The record keeps the version that last completed a baseline, and a running version that differs from it is exempt from `baselineMinIntervalHours`. A record written by a build that kept no version counts as a different version.
- A baseline that was interrupted, stopped by SIGTERM or left `running` by a restart or crash, is retried by the next run however recent it was, until one ends.
- After a baseline that ended `partial_failure` or `failed`, the next run waits 24 hours, whatever the version. One retry is allowed then; if it does not complete either, the full interval applies again, unless the version has changed.
- A throttled baseline ends as `skip`, logs why, and removes its LaunchDaemon like any other finished run.

BootstrapMate never relaunches itself to retry. A retry happens only when something already starts a run: the LaunchDaemon loading when the package is installed, or your MDM's own schedule.

There is no baseline record on a Mac being provisioned, and a provisioning run clears it. A baseline also goes ahead while the file named by `forceRunFile` exists, provided it is owned by root in a directory only root can write; any other force file is ignored and logged. Dry runs and `--userscript` never run the preflight, so they are never throttled. The throttle only checks for the force file; the preflight is what consumes it.

### Files root acts on

BootstrapMate runs as root, so it acts only on files no other account could have written. `/Library/Managed Bootstrap` and everything in it (the cache, logs, `installed.json`, `last-run.json`, `baseline.json`) are root:wheel and writable by root alone: the package postinstall sets this on install, and every run checks and repairs the directories before it starts. A state file or cached payload that is not root-owned, or that another account can write, is not used: state is ignored, which can only make a run do more, and a cached payload is discarded and downloaded again. A payload is never written into a directory another account can write.

Packages are not downloaded when nothing has changed. A package whose receipt shows the manifest's version is skipped before any download. In a baseline run, so is a package file whose hash is already in the install ledger, unless its receipt now shows an older version. Downloaded files stay in the cache while `retainCache` is true, so an unchanged script is not downloaded again either.

The LaunchDaemon runs once when it is loaded (`RunAtLoad`) and has no `KeepAlive` or schedule. Every run, including one that fails to load its manifest, removes the daemon when it finishes.

## Dry run

`managedbootstrapinstall --dry-run` (or the `dryRun` managed preference) rehearses a manifest against a real Mac without changing it. Every item is downloaded and its hash checked, and every package's signature is checked, so a broken URL, a stale hash or an untrusted package fails the rehearsal just as it would fail a real run. Nothing is installed, no script runs (preflight included), nothing is added to the install ledger, and the run does not reboot, post a report, mark the Mac complete or remove its LaunchDaemon. Because the preflight does not run, a dry run always rehearses the full provisioning path. Items are logged as `[Dry Run] Would install` or `[Dry Run] Would run`, recorded as skipped, and the session's run type is `dry-run`.

## HTTP redirects

Redirects are followed by default, for the manifest and for every item. Set the `followRedirects` managed preference to `false`, or pass `--no-follow-redirects`, to refuse them: a redirected download then fails with the 3xx status and the address it pointed to, instead of fetching from wherever the redirect leads. An item's own `followRedirects` field overrides the run-wide setting for that item.

## Authorization header

A private origin is reached with an `Authorization` header. It is sent only over https, and only to the manifest's host: to the manifest request, and to a package whose URL has the same host (compared without regard to case). A manifest or package fetched over plain http never gets it, even from the manifest's host. A package on any other host, such as public blob storage or a vendor CDN, is fetched without it, so the credential never reaches that host, and storage that rejects a foreign `Authorization` header (Azure Blob Storage answers 403) serves the file. A redirect to another host, or to plain http, drops the header too. A withheld header is logged at debug level by address, never by value.

The header comes from the first of these that gives one:

1. `--headers` on the command line.
2. The `headers` managed preference (also `Headers` or `AuthorizationHeader`), when it is not empty.
3. The file `/Library/Managed Bootstrap/Secrets/AuthorizationHeader`.

The Settings window runs the tool as root through the privileged helper, with a manifest URL any user can type. So a header from the preferences or the file is used only when the run's manifest URL is https on the host the administrator configured:

- The file's header needs a manifest URL forced by a configuration profile (`url` in `com.github.bootstrapmate`), and the run's manifest URL must be on that host. A `url` in `/Library/Preferences` does not count, because the helper writes it for any user. Without a profile-managed URL the file is not used.
- The preference header needs the run's manifest URL on the host of the profile-managed URL, or, with no profile, of the `url` preference. A `--jsonurl` on another host never inherits it.
- A header given with `--headers` is the caller's own and is not checked this way.

A header that fails its check is dropped with a warning naming the hosts, never the value, and no lower source is tried.

A configuration profile's preferences can be read by every user on the Mac, so a credential is better kept in the file. It holds the full header value, such as `Bearer <token>` or `Basic <base64>`, and surrounding whitespace is trimmed. It is used only when it is a regular file owned by root with no group or world permissions (mode `0600`), in a directory owned by root with mode `0700`. A file that fails those checks is ignored with a warning. A standard user cannot read it, so the Settings window never shows it.

Create the directory:

```bash
sudo install -d -o root -g wheel -m 0700 "/Library/Managed Bootstrap/Secrets"
```

Then write the file, pasting the header value and ending with Control-D, so the value stays out of the shell history:

```bash
sudo sh -c 'umask 077 && cat > "/Library/Managed Bootstrap/Secrets/AuthorizationHeader"'
```

A management tool that deploys the file instead must set the same owner and modes.

With no header from any of the three, no `Authorization` header is sent.

## Managed preferences

BootstrapMate reads these keys from the `com.github.bootstrapmate` domain, normally delivered in a configuration profile. `examples/config.mobileconfig` sets each one. The reporting and signature keys are covered in their own sections below.

| Key | Type | Default | Effect |
|---|---|---|---|
| `url` | string | | Manifest URL. Required unless `--jsonurl` is passed. |
| `headers` | string | | `Authorization` header sent to the manifest's host; see Authorization header. An empty value sends none, so a profile can manage the field without setting a header. |
| `networkTimeout` | integer | `120` | Seconds to wait for a network connection before the run starts. `--network-timeout` overrides it. |
| `enableDialog` | bool | `true` | Show the SwiftDialog window during a provisioning run. `--no-dialog` and `--silent` turn it off whatever this says. |
| `dialogTitle`, `dialogMessage` | string | | The window's title and message. `--dialog-title` and `--dialog-message` override them. |
| `dialogIcon` | string | gear symbol | The window's icon: a file path or a SwiftDialog `SF=` symbol. An empty value means the gear symbol. |
| `blurScreen` | bool | `false` | Blur the screen behind the window. |
| `retainCache` | bool | `true` | Keep downloaded payloads in `/Library/Managed Bootstrap/cache` after a successful run, so a later run does not download them again. `false` empties the cache when a run succeeds. |
| `baselineMinIntervalHours` | integer | `144` | Minimum hours between baseline runs; see Baseline throttle. `0` turns the throttle off. |
| `forceRunFile` | string | `/Library/Managed Bootstrap/.bootstrapmate-force-run` | A file whose presence exempts the next run from the baseline throttle. Point it at the file your preflight checks for a forced run. It counts only when owned by root, in a directory only root can write. |
| `userlandLoginTimeout` | integer | `3600` | Seconds to wait for a user to log in before skipping the userland stage. `0` waits forever. |
| `reboot`, `dryRun`, `silentMode`, `verboseMode`, `followRedirects` | bool | | As the matching CLI flags. |

Earlier builds also accepted `installPath`, `daemonIdentifier` and `agentIdentifier` (and their aliases `iapath`, `ldidentifier`, `laidentifier`) but never used them. The install location and the LaunchDaemon label are fixed by the package, so these keys are no longer read, and a run that finds one set logs a warning naming it.

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

When a configuration profile forces swiftDialog's `AuthorisationKey`, dialog shows nothing to a caller that does not present the key. BootstrapMate reads the key from `/Library/Managed Notifications/.authkey` and hands it to dialog in `DIALOG_AUTH_KEY`, never on the command line. The file counts only when owned by root, writable by no other account, in a directory only root can write; make it readable by root alone.

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

`status` uses the same values as `session.json`: `running`, `completed`, `partial_failure`, `failed` or `interrupted`. A run stopped by SIGTERM (a shutdown or restart, or a bootout) closes its session as `interrupted`. A run that could not, because it crashed or was killed outright, stays `running` until the next run starts. That run marks it `interrupted` in `last-run.json` and in its `session.json`, logs a warning, and then starts its own record. Only one run happens at a time: a second instance exits at once and leaves the live run's records alone. Reinstalling the package during a run does not stop it; the postinstall leaves a running job alone and reloads the daemon only when it is idle. Each item's `stage` is `setupassistant` or `userland`, its `result` is `installed`, `skipped` or `failed`, and `error` is present only on failures.

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
