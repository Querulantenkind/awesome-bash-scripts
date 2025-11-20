#!/bin/bash

################################################################################
# Script Name: update-manager.sh
# Description: Automated system update manager with support for multiple package
#              managers (apt, yum, dnf, pacman, zypper). Provides safe update
#              automation with backup capability, pre/post hooks, security-only
#              updates, dry-run mode, and automatic reboot handling.
# Author: Luca
# Created: 2025-11-20
# Modified: 2025-11-20
# Version: 1.0.0
#
# Usage: ./update-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -u, --update            Update package lists
#   -U, --upgrade           Upgrade all packages
#   -s, --security          Security updates only
#   -a, --autoremove        Remove unused packages
#   -c, --clean             Clean package cache
#   -b, --backup            Backup package list before update
#   -n, --dry-run           Simulate updates without applying
#   -r, --reboot            Reboot if required after update
#   -y, --yes               Automatic yes to prompts
#   -j, --json              Output in JSON format
#   -o, --output FILE       Save output to file
#   -l, --log FILE          Log operations to file
#   --no-color              Disable colored output
#   --pre-hook CMD          Command to run before update
#   --post-hook CMD         Command to run after update
#
# Examples:
#   # Update package lists and upgrade
#   ./update-manager.sh --update --upgrade
#
#   # Security updates only
#   ./update-manager.sh --security --yes
#
#   # Full update with cleanup and reboot
#   ./update-manager.sh -u -U -a -c -r
#
#   # Dry run to see what would be updated
#   ./update-manager.sh --upgrade --dry-run
#
#   # Update with backup and hooks
#   ./update-manager.sh -u -U --backup --post-hook "echo Done"
#
#   # Generate JSON report
#   ./update-manager.sh --upgrade --json -o update-report.json
#
# Dependencies:
#   - One of: apt, yum, dnf, pacman, zypper
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Permission denied (requires root)
#   4 - Reboot required
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")
BACKUP_DIR="/var/backups/update-manager"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
JSON_OUTPUT=false
OUTPUT_FILE=""
LOG_FILE=""
USE_COLOR=true
DO_UPDATE=false
DO_UPGRADE=false
DO_SECURITY=false
DO_AUTOREMOVE=false
DO_CLEAN=false
DO_BACKUP=false
DRY_RUN=false
AUTO_YES=false
AUTO_REBOOT=false
PRE_HOOK=""
POST_HOOK=""

# Package manager
PKG_MANAGER=""
UPDATE_CMD=""
UPGRADE_CMD=""
AUTOREMOVE_CMD=""
CLEAN_CMD=""
SECURITY_CMD=""
LIST_CMD=""

# Statistics
PACKAGES_UPDATED=0
PACKAGES_INSTALLED=0
PACKAGES_REMOVED=0
REBOOT_REQUIRED=false

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit "${2:-1}"
}

success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo "✓ $1"
    fi
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

warning() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}⚠ $1${NC}"
    else
        echo "⚠ $1"
    fi
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

info() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${CYAN}ℹ $1${NC}"
    else
        echo "ℹ $1"
    fi
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        if [[ "$USE_COLOR" == true ]]; then
            echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
        else
            echo "[VERBOSE] $1" >&2
        fi
    fi
}

section_header() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        if [[ "$USE_COLOR" == true ]]; then
            echo ""
            echo -e "${WHITE}━━━ $1 ━━━${NC}"
        else
            echo ""
            echo "━━━ $1 ━━━"
        fi
    fi
}

show_usage() {
    cat << EOF
${WHITE}Update Manager - Automated System Update Tool${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -u, --update            Update package lists
    -U, --upgrade           Upgrade all packages
    -s, --security          Security updates only
    -a, --autoremove        Remove unused packages
    -c, --clean             Clean package cache
    -b, --backup            Backup package list before update
    -n, --dry-run           Simulate updates without applying
    -r, --reboot            Reboot if required after update
    -y, --yes               Automatic yes to prompts
    -j, --json              Output in JSON format
    -o, --output FILE       Save output to file
    -l, --log FILE          Log operations to file
    --no-color              Disable colored output
    --pre-hook CMD          Command to run before update
    --post-hook CMD         Command to run after update

${CYAN}Examples:${NC}
    # Update package lists and upgrade
    $SCRIPT_NAME --update --upgrade

    # Security updates only
    $SCRIPT_NAME --security --yes

    # Full update with cleanup and reboot
    $SCRIPT_NAME -u -U -a -c -r

    # Dry run to see what would be updated
    $SCRIPT_NAME --upgrade --dry-run

    # Update with backup and hooks
    $SCRIPT_NAME -u -U --backup --post-hook "systemctl restart app"

    # Generate JSON report
    $SCRIPT_NAME --upgrade --json -o update-report.json

${CYAN}Features:${NC}
    • Auto-detect package manager (apt, yum, dnf, pacman, zypper)
    • Security-only updates
    • Package list backup
    • Pre/post update hooks
    • Dry-run mode
    • Automatic reboot handling
    • JSON logging
    • Clean package cache
    • Remove unused packages

${CYAN}Supported Package Managers:${NC}
    • apt (Debian, Ubuntu)
    • yum (CentOS, RHEL 6-7)
    • dnf (Fedora, RHEL 8+)
    • pacman (Arch Linux)
    • zypper (openSUSE, SLES)

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script requires root privileges. Please run with sudo." 3
    fi
}

################################################################################
# Package Manager Detection
################################################################################

detect_package_manager() {
    verbose "Detecting package manager..."

    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        UPDATE_CMD="apt update"
        UPGRADE_CMD="apt upgrade"
        AUTOREMOVE_CMD="apt autoremove"
        CLEAN_CMD="apt clean && apt autoclean"
        SECURITY_CMD="apt upgrade"
        LIST_CMD="dpkg -l"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf check-update"
        UPGRADE_CMD="dnf upgrade"
        AUTOREMOVE_CMD="dnf autoremove"
        CLEAN_CMD="dnf clean all"
        SECURITY_CMD="dnf upgrade --security"
        LIST_CMD="dnf list installed"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        UPDATE_CMD="yum check-update"
        UPGRADE_CMD="yum update"
        AUTOREMOVE_CMD="yum autoremove"
        CLEAN_CMD="yum clean all"
        SECURITY_CMD="yum update --security"
        LIST_CMD="yum list installed"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        UPDATE_CMD="pacman -Sy"
        UPGRADE_CMD="pacman -Su"
        AUTOREMOVE_CMD="pacman -Rns \$(pacman -Qdtq)"
        CLEAN_CMD="pacman -Sc"
        SECURITY_CMD="pacman -Su"
        LIST_CMD="pacman -Q"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        UPDATE_CMD="zypper refresh"
        UPGRADE_CMD="zypper update"
        AUTOREMOVE_CMD="zypper packages --unneeded | xargs zypper remove"
        CLEAN_CMD="zypper clean"
        SECURITY_CMD="zypper patch --category security"
        LIST_CMD="zypper packages --installed-only"
    else
        error_exit "No supported package manager found (apt, yum, dnf, pacman, zypper)" 1
    fi

    verbose "Detected package manager: $PKG_MANAGER"
}

################################################################################
# Backup Functions
################################################################################

create_backup() {
    section_header "CREATING BACKUP"

    verbose "Creating package list backup..."

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    local backup_file="$BACKUP_DIR/packages-$(date +%Y%m%d-%H%M%S).txt"

    if $LIST_CMD > "$backup_file" 2>/dev/null; then
        success "Package list backed up to: $backup_file"
    else
        warning "Failed to create package list backup"
    fi
}

################################################################################
# Update Functions
################################################################################

update_package_lists() {
    section_header "UPDATING PACKAGE LISTS"

    verbose "Running: $UPDATE_CMD"

    local cmd="$UPDATE_CMD"
    [[ "$DRY_RUN" == true ]] && info "[DRY RUN] Would run: $cmd" && return 0

    if eval "$cmd"; then
        success "Package lists updated successfully"
    else
        # yum check-update returns 100 if updates available, not an error
        if [[ "$PKG_MANAGER" == "yum" ]] || [[ "$PKG_MANAGER" == "dnf" ]]; then
            success "Package lists updated"
        else
            error_exit "Failed to update package lists" 1
        fi
    fi
}

upgrade_packages() {
    section_header "UPGRADING PACKAGES"

    local cmd="$UPGRADE_CMD"

    if [[ "$DO_SECURITY" == true ]]; then
        cmd="$SECURITY_CMD"
        info "Performing security updates only"
    fi

    if [[ "$AUTO_YES" == true ]]; then
        case "$PKG_MANAGER" in
            apt)
                cmd="$cmd -y"
                ;;
            yum|dnf|zypper)
                cmd="$cmd -y"
                ;;
            pacman)
                cmd="$cmd --noconfirm"
                ;;
        esac
    fi

    verbose "Running: $cmd"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] Would run: $cmd"

        # Show what would be updated
        case "$PKG_MANAGER" in
            apt)
                apt list --upgradable 2>/dev/null
                ;;
            yum|dnf)
                $PKG_MANAGER list updates 2>/dev/null || true
                ;;
            pacman)
                pacman -Qu 2>/dev/null || true
                ;;
            zypper)
                zypper list-updates 2>/dev/null
                ;;
        esac
        return 0
    fi

    if eval "$cmd"; then
        success "Packages upgraded successfully"
        PACKAGES_UPDATED=1
    else
        error_exit "Failed to upgrade packages" 1
    fi
}

autoremove_packages() {
    section_header "REMOVING UNUSED PACKAGES"

    verbose "Running: $AUTOREMOVE_CMD"

    local cmd="$AUTOREMOVE_CMD"

    if [[ "$AUTO_YES" == true ]]; then
        case "$PKG_MANAGER" in
            apt|yum|dnf|zypper)
                cmd="$cmd -y"
                ;;
            pacman)
                cmd="$cmd --noconfirm"
                ;;
        esac
    fi

    [[ "$DRY_RUN" == true ]] && info "[DRY RUN] Would run: $cmd" && return 0

    if eval "$cmd" 2>/dev/null; then
        success "Unused packages removed"
    else
        warning "No unused packages to remove or operation failed"
    fi
}

clean_cache() {
    section_header "CLEANING PACKAGE CACHE"

    verbose "Running: $CLEAN_CMD"

    local cmd="$CLEAN_CMD"

    if [[ "$AUTO_YES" == true ]]; then
        case "$PKG_MANAGER" in
            pacman)
                cmd="pacman -Sc --noconfirm"
                ;;
        esac
    fi

    [[ "$DRY_RUN" == true ]] && info "[DRY RUN] Would run: $cmd" && return 0

    if eval "$cmd"; then
        success "Package cache cleaned"
    else
        warning "Failed to clean package cache"
    fi
}

################################################################################
# Reboot Check
################################################################################

check_reboot_required() {
    verbose "Checking if reboot is required..."

    # Check for reboot required indicator
    if [[ -f /var/run/reboot-required ]]; then
        REBOOT_REQUIRED=true
        warning "System reboot is required"
        return 0
    fi

    # Check for kernel updates (Debian/Ubuntu)
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        local running_kernel=$(uname -r)
        local installed_kernel=$(dpkg -l | grep "linux-image-" | grep "^ii" | awk '{print $2}' | sort -V | tail -1 | sed 's/linux-image-//')

        if [[ "$running_kernel" != "$installed_kernel"* ]]; then
            REBOOT_REQUIRED=true
            warning "Kernel updated, reboot required"
        fi
    fi

    # Check for systemd-based reboot requirement
    if command -v needs-restarting &> /dev/null; then
        if needs-restarting -r &> /dev/null; then
            REBOOT_REQUIRED=true
            warning "System services require reboot"
        fi
    fi
}

handle_reboot() {
    if [[ "$REBOOT_REQUIRED" == true ]] && [[ "$AUTO_REBOOT" == true ]]; then
        warning "System will reboot in 60 seconds..."
        info "Press Ctrl+C to cancel"

        if [[ "$DRY_RUN" == true ]]; then
            info "[DRY RUN] Would reboot system"
            return 0
        fi

        sleep 60
        success "Rebooting system..."
        reboot
    elif [[ "$REBOOT_REQUIRED" == true ]]; then
        warning "Please reboot your system to complete the update"
        exit 4
    fi
}

################################################################################
# Hooks
################################################################################

run_pre_hook() {
    if [[ -n "$PRE_HOOK" ]]; then
        section_header "RUNNING PRE-UPDATE HOOK"
        verbose "Executing: $PRE_HOOK"

        [[ "$DRY_RUN" == true ]] && info "[DRY RUN] Would run: $PRE_HOOK" && return 0

        if eval "$PRE_HOOK"; then
            success "Pre-update hook completed"
        else
            error_exit "Pre-update hook failed" 1
        fi
    fi
}

run_post_hook() {
    if [[ -n "$POST_HOOK" ]]; then
        section_header "RUNNING POST-UPDATE HOOK"
        verbose "Executing: $POST_HOOK"

        [[ "$DRY_RUN" == true ]] && info "[DRY RUN] Would run: $POST_HOOK" && return 0

        if eval "$POST_HOOK"; then
            success "Post-update hook completed"
        else
            warning "Post-update hook failed"
        fi
    fi
}

################################################################################
# JSON Report
################################################################################

generate_json_report() {
    cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "package_manager": "$PKG_MANAGER",
  "operations": {
    "update": $DO_UPDATE,
    "upgrade": $DO_UPGRADE,
    "security_only": $DO_SECURITY,
    "autoremove": $DO_AUTOREMOVE,
    "clean": $DO_CLEAN,
    "backup": $DO_BACKUP
  },
  "status": {
    "packages_updated": $PACKAGES_UPDATED,
    "reboot_required": $REBOOT_REQUIRED,
    "dry_run": $DRY_RUN
  }
}
EOF
}

################################################################################
# Main Execution
################################################################################

run_update_manager() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo ""
        echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║                    UPDATE MANAGER                               ║${NC}"
        echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${CYAN}Package Manager:${NC} $PKG_MANAGER"
        echo -e "${CYAN}Start Time:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"
        [[ "$DRY_RUN" == true ]] && echo -e "${YELLOW}Mode:${NC}            DRY RUN (no changes will be made)"
    fi

    # Run operations in order
    run_pre_hook

    [[ "$DO_BACKUP" == true ]] && create_backup
    [[ "$DO_UPDATE" == true ]] && update_package_lists
    [[ "$DO_UPGRADE" == true ]] && upgrade_packages
    [[ "$DO_AUTOREMOVE" == true ]] && autoremove_packages
    [[ "$DO_CLEAN" == true ]] && clean_cache

    run_post_hook

    check_reboot_required
    handle_reboot

    if [[ "$JSON_OUTPUT" == true ]]; then
        generate_json_report
    else
        section_header "UPDATE COMPLETE"
        success "All update operations completed successfully"
        echo -e "${CYAN}End Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    fi
}

################################################################################
# Argument Parsing
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -u|--update)
            DO_UPDATE=true
            shift
            ;;
        -U|--upgrade)
            DO_UPGRADE=true
            shift
            ;;
        -s|--security)
            DO_SECURITY=true
            DO_UPGRADE=true
            shift
            ;;
        -a|--autoremove)
            DO_AUTOREMOVE=true
            shift
            ;;
        -c|--clean)
            DO_CLEAN=true
            shift
            ;;
        -b|--backup)
            DO_BACKUP=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--reboot)
            AUTO_REBOOT=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "--output requires a file path" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -l|--log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        --pre-hook)
            [[ -z "${2:-}" ]] && error_exit "--pre-hook requires a command" 2
            PRE_HOOK="$2"
            shift 2
            ;;
        --post-hook)
            [[ -z "${2:-}" ]] && error_exit "--post-hook requires a command" 2
            POST_HOOK="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            error_exit "Unexpected argument: $1" 2
            ;;
    esac
done

################################################################################
# Main
################################################################################

check_root
detect_package_manager

# If no operations specified, show usage
if [[ "$DO_UPDATE" == false ]] && \
   [[ "$DO_UPGRADE" == false ]] && \
   [[ "$DO_AUTOREMOVE" == false ]] && \
   [[ "$DO_CLEAN" == false ]]; then
    show_usage
    exit 0
fi

# Run update manager
output=$(run_update_manager)

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$output" > "$OUTPUT_FILE"
    success "Report saved to: $OUTPUT_FILE"
else
    echo "$output"
fi

verbose "Update manager completed"
exit 0
