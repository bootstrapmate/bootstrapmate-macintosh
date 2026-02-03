# BootstrapMate Versioning Scheme

**Effective:** February 2, 2026  
**Previous Format:** Semantic versioning (1.0.0, 2026.02.02.2217, etc.)  
**Current Format:** Date-based timestamps (YYYY.MM.DD.HHMM)

---

## Version Format

All BootstrapMate builds now use a **date-based version format**:

```
YYYY.MM.DD.HHMM
│    │  │   │ └─ Minute (00-59)
│    │  │   └──── Hour (00-23, UTC)
│    │  └──────── Day (01-31)
│    └─────────── Month (01-12)
└──────────────── Year (4 digits)
```

### Example Versions

| Version | Meaning |
|---|---|
| `2026.02.02.2217` | Built on February 2, 2026 at 22:17 UTC |
| `2026.02.03.0930` | Built on February 3, 2026 at 09:30 UTC |
| `2026.12.25.1500` | Built on December 25, 2026 at 15:00 UTC |

---

## Benefits

✅ **Temporal Tracking** - Version immediately indicates when build occurred  
✅ **Unique Identification** - No manual version number management  
✅ **Chronological Ordering** - Versions naturally sort by date  
✅ **Reproducibility** - Build can be traced to exact minute  
✅ **Simplified Workflow** - No need to update version numbers manually  

---

## How Versioning Works

### Automatic Generation

If no version is specified, the build system auto-generates it:

```bash
# Auto-generates version from current date/time
make build-dev

# Generates: BootstrapMate-2026.02.02.2224.pkg
```

### Manual Override

You can still specify a version if needed:

```bash
# Use specific date-based version
make build VERSION=2026.02.02.1000

# Or use any custom version
make build VERSION=custom.my.version.1
```

---

## File Naming

### Package Files

Old format:
```
BootstrapMate-2026.02.02.2217.pkg
BootstrapMate-1.0.0.pkg
```

New format:
```
BootstrapMate-2026.02.02.2217.pkg
BootstrapMate-2026.02.03.0930.pkg
BootstrapMate-2026.12.25.1500.pkg
```

### Bundle Version Strings

The `Info.plist` includes both:

```xml
<key>CFBundleShortVersionString</key>
<string>2026.02.02.2217</string>
<key>CFBundleVersion</key>
<string>2026.02.02.2217</string>
```

Visible in:
- About dialog: "Version 2026.02.02.2217"
- CLI: `/usr/local/bootstrapmate/installapplications --version`
- System profiler

---

## Usage Examples

### Build with Auto-Generated Version

```bash
# Uses current date/time
make build-dev

# Output:
# Building BootstrapMate v2026.02.02.2224...
# ...
# BootstrapMate-2026.02.02.2224.pkg created
```

### Build with Specific Version

```bash
# Specify exact version (useful for rebuilds, rollbacks, etc.)
make build VERSION=2026.02.02.2217

# Output:
# Building BootstrapMate v2026.02.02.2217...
# ...
# BootstrapMate-2026.02.02.2217.pkg created
```

### Install Built Package

```bash
# After build completes, install:
sudo installer -pkg build/BootstrapMate-2026.02.02.2224.pkg -target /

# Or use make:
make install
```

### Verify Version

```bash
# After installation:
/usr/local/bootstrapmate/installapplications --version
# Output: BootstrapMate 2026.02.02.2224

# Or check Info.plist:
defaults read /Applications/Utilities/BootstrapMate.app/Contents/Info CFBundleVersion
# Output: 2026.02.02.2224
```

---

## Timeline

### v1.0.0 through 2026.02.02.2217 (January 2026)
Used traditional semantic versioning

### v2026.02.02.2217 onwards (February 2, 2026)
Switched to date-based versioning

### Why the Change?

1. **No manual version management** - removes human error
2. **Precise build tracking** - timestamp included in version
3. **Easy chronological comparison** - versions naturally sort
4. **Better deployment tracking** - know exactly when deployed
5. **Simplified build process** - one less thing to configure

---

## Deployment Notes

### When Deploying via Munki

```bash
# Copy package with date-based name
cp build/BootstrapMate-2026.02.02.2224.pkg /your/munki/pkgs/

# Create pkginfo with auto-detected version
makepkginfo -f /your/munki/pkgs/BootstrapMate-2026.02.02.2224.pkg > \
  /your/munki/pkgsinfo/BootstrapMate-2026.02.02.2224
```

### When Deploying via Jamf

Upload package with versioned filename: `BootstrapMate-2026.02.02.2224.pkg`

Jamf will auto-detect version from CFBundleVersion in Info.plist

### When Deploying via MDM

No version changes needed - configuration continues to work with any version

---

## FAQ

**Q: How do I know what version is installed?**
```bash
/usr/local/bootstrapmate/installapplications --version
```

**Q: How do I revert to a previous version?**
```bash
# If you have the old package:
sudo installer -pkg BootstrapMate-2026.02.01.1500.pkg -target /
```

**Q: Can I use semantic versioning?**
Yes, you can still override:
```bash
make build VERSION=1.2.3
# Creates: BootstrapMate-1.2.3.pkg
```

**Q: What if I need to rebuild the same timestamp?**
```bash
make build VERSION=2026.02.02.2217
# Creates: BootstrapMate-2026.02.02.2217.pkg (same version)
```

**Q: How are versions sorted chronologically?**
Date-based versions sort naturally:
```
2026.02.01.1000  (older)
2026.02.02.1500  (middle)
2026.02.03.0800  (newer)
```

**Q: Does this affect MDM profiles?**
No - profiles work with any version, no changes needed

---

## Technical Details

### Build System Integration

1. **Makefile** automatically generates version on each build
2. **build.sh** receives version and embeds in Info.plist
3. **CLI** reads version from CFBundleVersion
4. **Package naming** includes version in filename

### Backward Compatibility

- Old packages (v1.0.0, 2026.02.02.2217) still installable
- Old version format still accepted if provided
- No changes to functionality based on version

---

**Version as of:** February 2026  
**Format:** YYYY.MM.DD.HHMM  
**Status:** ✅ Active and mandatory for new builds
