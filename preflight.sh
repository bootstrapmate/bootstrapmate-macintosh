#!/bin/bash
# BootstrapMate macOS - Preflight Script
# 
# Exit codes:
#   0 = Skip bootstrap (device already on production manifest)
#   1 = Continue with bootstrap (device on provisioning manifest or new)
#
# This script runs BEFORE any packages are installed. Use it to:
# - Check if device is on production vs provisioning manifest
# - Allow override for forcing reinstall on production devices
# - Log device state and previous bootstrap status
#
# Override mechanism:
#   Touch /var/tmp/.bootstrapmate-force-run to force bootstrap on production devices
#   This file is automatically removed after detection

set -euo pipefail

# Configuration
STATUS_PLIST="/Library/Preferences/com.github.bootstrapmate.plist"
LOG_DIR="/var/log/bootstrapmate"
LOG_FILE="$LOG_DIR/preflight.log"
FORCE_RUN_FLAG="/Library/Managed Bootstrap/.bootstrapmate-force-run"

# Provisioning manifests - devices on these need full bootstrap
PROVISIONING_MANIFESTS=("Bootstrap" "ProvisioningFaculty" "ProvisioningCurriculum" "ProvisioningKiosk" "ProvisioningStaff")

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log() {
    local message="$1"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Check if manifest is a provisioning manifest
is_provisioning_manifest() {
    local manifest="$1"
    for prov_manifest in "${PROVISIONING_MANIFESTS[@]}"; do
        if [[ "$manifest" == "$prov_manifest" ]]; then
            return 0  # true - is provisioning
        fi
    done
    return 1  # false - not provisioning (production)
}

log "=== BootstrapMate Preflight Check ==="
log "Hostname: $(hostname)"
log "Serial: $(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}')"
log "macOS Version: $(sw_vers -productVersion)"
log "Build: $(sw_vers -buildVersion)"
log "Architecture: $(uname -m)"
log "User: $(whoami)"

#===============================================================================
# Override Check - Force run on production devices when needed
#===============================================================================
if [[ -f "$FORCE_RUN_FLAG" ]]; then
    log "OVERRIDE: Force-run flag detected at $FORCE_RUN_FLAG"
    log "Will run bootstrap regardless of manifest status"
    rm -f "$FORCE_RUN_FLAG"
    log "Force-run flag removed (one-time use)"
    FORCE_RUN=true
else
    FORCE_RUN=false
fi

# Check 1: Log previous BootstrapMate status
if [[ -f "$STATUS_PLIST" ]]; then
    stage=$(/usr/libexec/PlistBuddy -c "Print :Stage" "$STATUS_PLIST" 2>/dev/null || echo "Unknown")
    completed_date=$(/usr/libexec/PlistBuddy -c "Print :CompletedDate" "$STATUS_PLIST" 2>/dev/null || echo "Never")
    last_version=$(/usr/libexec/PlistBuddy -c "Print :LastRunVersion" "$STATUS_PLIST" 2>/dev/null || echo "Unknown")
    log "Previous stage: $stage"
    log "Last completed: $completed_date"
    log "Last version: $last_version"
    
    if [[ "$stage" == "Completed" ]]; then
        log "BootstrapMate previously completed - will reinstall management tools"
    fi
    
    if [[ "$stage" == "Failed" ]]; then
        failure_reason=$(/usr/libexec/PlistBuddy -c "Print :FailureReason" "$STATUS_PLIST" 2>/dev/null || echo "Unknown")
        log "Previous run failed: $failure_reason - will retry"
    fi
else
    log "No previous BootstrapMate run detected - first time setup"
fi

# Check 2: Determine if device needs bootstrap based on manifest status
NEEDS_BOOTSTRAP=false
MANIFEST_STATUS="unknown"

if [[ -f "/Library/Preferences/ManagedInstalls.plist" ]]; then
    munki_url=$(/usr/libexec/PlistBuddy -c "Print :SoftwareRepoURL" "/Library/Preferences/ManagedInstalls.plist" 2>/dev/null || echo "")
    client_id=$(/usr/libexec/PlistBuddy -c "Print :ClientIdentifier" "/Library/Preferences/ManagedInstalls.plist" 2>/dev/null || echo "")
    
    if [[ -n "$munki_url" ]]; then
        log "Munki configured with repo: $munki_url"
        log "Munki ClientIdentifier: $client_id"
        
        # Check if we can reach the Munki repo
        if curl -s --head --connect-timeout 5 "$munki_url" &>/dev/null; then
            log "Munki repo is reachable"
        else
            log "Munki repo unreachable - connectivity issue or needs reconfiguration"
        fi
        
        # Log manifest cache status
        if [[ -d "/Library/Managed Installs/manifests" ]]; then
            manifest_count=$(find "/Library/Managed Installs/manifests" -type f 2>/dev/null | wc -l | tr -d ' ')
            log "Munki has $manifest_count manifests cached"
        fi
        
        # Determine if device is on provisioning or production manifest
        if [[ -z "$client_id" ]]; then
            log "No ClientIdentifier set - first time setup"
            NEEDS_BOOTSTRAP=true
            MANIFEST_STATUS="none"
        elif is_provisioning_manifest "$client_id"; then
            log "Device is on provisioning manifest: $client_id"
            log "Bootstrap REQUIRED - device still in provisioning"
            NEEDS_BOOTSTRAP=true
            MANIFEST_STATUS="provisioning"
        else
            log "Device is on production manifest: $client_id"
            MANIFEST_STATUS="production"
            if [[ "$FORCE_RUN" == true ]]; then
                log "Force-run override active - will run bootstrap on production device"
                NEEDS_BOOTSTRAP=true
            else
                log "Bootstrap SKIPPED - device already in production"
                log "To force reinstall, touch $FORCE_RUN_FLAG before running"
                NEEDS_BOOTSTRAP=false
            fi
        fi
    else
        log "Munki repo URL not set - first time setup"
        NEEDS_BOOTSTRAP=true
        MANIFEST_STATUS="none"
    fi
else
    log "Munki not yet configured - first time setup"
    NEEDS_BOOTSTRAP=true
    MANIFEST_STATUS="none"
fi

# Check 3: Is this a DEP/ADE enrolled device?
dep_status=$(/usr/bin/profiles status -type enrollment 2>/dev/null || echo "unknown")
log "Enrollment status: $dep_status"

if echo "$dep_status" | grep -q "MDM enrollment: Yes"; then
    log "Device is MDM enrolled"
    mdm_server=$(/usr/bin/profiles status -type enrollment 2>/dev/null | grep "MDM server" || echo "Unknown")
    log "MDM Server: $mdm_server"
else
    log "Device is NOT MDM enrolled - bootstrap may be limited"
fi

# Check 4: Network connectivity
log "Checking network connectivity..."

# Check general internet
if ping -c 1 -t 5 8.8.8.8 &>/dev/null; then
    log "Internet: Connected (via IP)"
else
    log "Internet: Not connected via IP"
fi

# Check DNS
if ping -c 1 -t 5 google.com &>/dev/null; then
    log "DNS: Working"
else
    log "DNS: Not resolving - may affect downloads"
fi

# Check Azure Storage (where packages are hosted)
if curl -s --head --connect-timeout 5 "https://cimiancloudstorage.blob.core.windows.net" &>/dev/null; then
    log "Azure Storage: Reachable"
else
    log "Azure Storage: Not reachable - package downloads may fail"
fi

# Check 5: Disk space (at least 5GB free for packages)
free_space_bytes=$(df -b / | awk 'NR==2 {print $4}')
free_space_gb=$((free_space_bytes / 1073741824))
log "Free disk space: ${free_space_gb}GB"

if [[ "$free_space_gb" -lt 5 ]]; then
    log "WARNING: Low disk space - less than 5GB free"
    log "Bootstrap may fail due to insufficient space"
fi

# Check 6: Verify we're running as root
if [[ $EUID -ne 0 ]]; then
    log "ERROR: Preflight must run as root (current UID: $EUID)"
    exit 1
fi

# Check 7: Check for pending software updates that might interfere
softwareupdate_list=$(softwareupdate -l 2>&1 || echo "")
if echo "$softwareupdate_list" | grep -q "restart"; then
    log "WARNING: Pending macOS updates require restart"
    log "Consider completing system updates before bootstrap"
fi

# Check 8: Verify SwiftDialog availability (for UI)
if [[ -f "/usr/local/bin/dialog" ]]; then
    dialog_version=$(/usr/local/bin/dialog --version 2>/dev/null || echo "Unknown")
    log "SwiftDialog already installed: $dialog_version"
fi

#===============================================================================
# Final Decision - Bootstrap or Skip
#===============================================================================
log ""
if [[ "$NEEDS_BOOTSTRAP" == true ]]; then
    log "Summary: Device requires bootstrap (manifest: $MANIFEST_STATUS)"
    if [[ "$FORCE_RUN" == true ]]; then
        log "Reason: Force-run override active"
    fi
    log "Preflight result: CONTINUE (exit 1)"
    exit 1
else
    log "Summary: Device already configured (manifest: $MANIFEST_STATUS)"
    log "Preflight result: SKIP (exit 0)"
    log "LaunchDaemon will be removed by BootstrapMate cleanup"
    exit 0
fi
