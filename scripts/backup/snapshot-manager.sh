#!/bin/bash

################################################################################
# Script Name: snapshot-manager.sh
# Description: LVM and BTRFS snapshot management tool with automated scheduling,
#              rotation, space tracking, and rollback capabilities. Supports both
#              LVM thin provisioning and BTRFS subvolume snapshots.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./snapshot-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -t, --type TYPE         Snapshot type (lvm|btrfs, auto-detect)
#   -V, --volume PATH       Volume or subvolume path
#   -n, --name NAME         Snapshot name (auto-generated if not provided)
#   -c, --create            Create new snapshot
#   -d, --delete NAME       Delete snapshot
#   -l, --list              List all snapshots
#   -r, --rollback NAME     Rollback to snapshot
#   --rotate NUM            Keep last N snapshots (auto-cleanup)
#   --size SIZE             LVM snapshot size (e.g., 5G, 10G)
#   --schedule EXPR         Schedule automated snapshots (cron expression)
#   --space                 Show space usage
#   -j, --json              Output in JSON format
#   --log FILE              Log file path
#   --no-color              Disable colored output
#
# Examples:
#   ./snapshot-manager.sh --create --volume /dev/vg0/lv_data
#   ./snapshot-manager.sh --list --volume /mnt/btrfs
#   ./snapshot-manager.sh --rollback snap-20241120 --volume /dev/vg0/lv_data
#   ./snapshot-manager.sh --rotate 10 --volume /mnt/btrfs
#   ./snapshot-manager.sh --space --json
#
# Dependencies:
#   - lvm2 (for LVM snapshots)
#   - btrfs-progs (for BTRFS snapshots)
#   - bc (for calculations)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Insufficient permissions
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

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
SNAPSHOT_TYPE=""
VOLUME_PATH=""
SNAPSHOT_NAME=""
ACTION=""
DELETE_NAME=""
ROLLBACK_NAME=""
ROTATION_COUNT=0
SNAPSHOT_SIZE="5G"
SCHEDULE_EXPR=""
SHOW_SPACE=false
JSON_OUTPUT=false
LOG_FILE=""
USE_COLOR=true

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo "✓ $1"
    fi
}

warning() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}⚠ $1${NC}"
    else
        echo "⚠ $1"
    fi
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
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}Snapshot Manager - LVM/BTRFS Snapshot Management${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -t, --type TYPE         Snapshot type (lvm|btrfs, auto-detect)
    -V, --volume PATH       Volume or subvolume path
    -n, --name NAME         Snapshot name (auto-generated if not provided)
    -c, --create            Create new snapshot
    -d, --delete NAME       Delete snapshot
    -l, --list              List all snapshots
    -r, --rollback NAME     Rollback to snapshot
    --rotate NUM            Keep last N snapshots (auto-cleanup)
    --size SIZE             LVM snapshot size (default: 5G)
    --schedule EXPR         Schedule automated snapshots
    --space                 Show space usage
    -j, --json              Output in JSON format
    --log FILE              Log file path
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Create LVM snapshot
    $SCRIPT_NAME --create --volume /dev/vg0/lv_data --size 10G

    # Create BTRFS snapshot
    $SCRIPT_NAME --create --volume /mnt/btrfs/data

    # List all snapshots
    $SCRIPT_NAME --list --volume /dev/vg0/lv_data

    # Rollback to snapshot
    $SCRIPT_NAME --rollback snap-20241120 --volume /dev/vg0/lv_data

    # Rotate snapshots (keep last 10)
    $SCRIPT_NAME --rotate 10 --volume /mnt/btrfs

    # Show space usage
    $SCRIPT_NAME --space --volume /dev/vg0/lv_data

${CYAN}Features:${NC}
    • LVM thin provisioning snapshots
    • BTRFS subvolume snapshots
    • Automated snapshot rotation
    • Space usage tracking
    • Snapshot rollback
    • Scheduled snapshots
    • JSON export

${CYAN}Notes:${NC}
    • Requires root privileges for most operations
    • LVM snapshots require thin provisioning
    • BTRFS snapshots are read-only by default

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root" 4
    fi
}

check_dependencies() {
    if [[ -z "$SNAPSHOT_TYPE" ]]; then
        # Auto-detect type based on volume path
        if [[ "$VOLUME_PATH" =~ ^/dev/ ]]; then
            SNAPSHOT_TYPE="lvm"
        elif [[ -d "$VOLUME_PATH" ]]; then
            # Check if it's a BTRFS filesystem
            if command -v btrfs &> /dev/null && btrfs filesystem show "$VOLUME_PATH" &> /dev/null; then
                SNAPSHOT_TYPE="btrfs"
            fi
        fi
    fi

    verbose "Snapshot type: $SNAPSHOT_TYPE"

    case "$SNAPSHOT_TYPE" in
        lvm)
            if ! command -v lvm &> /dev/null; then
                error_exit "lvm command not found. Please install lvm2." 3
            fi
            ;;
        btrfs)
            if ! command -v btrfs &> /dev/null; then
                error_exit "btrfs command not found. Please install btrfs-progs." 3
            fi
            ;;
        *)
            error_exit "Could not detect snapshot type. Please specify with --type" 2
            ;;
    esac

    if ! command -v bc &> /dev/null; then
        verbose "bc not found - some calculations may be limited"
    fi
}

################################################################################
# LVM Functions
################################################################################

lvm_create_snapshot() {
    local volume="$1"
    local snap_name="$2"
    local size="$SNAPSHOT_SIZE"

    info "Creating LVM snapshot: $snap_name"
    verbose "Volume: $volume, Size: $size"

    if lvcreate -s -n "$snap_name" -L "$size" "$volume" 2>&1 | tee -a "$LOG_FILE"; then
        success "LVM snapshot created: $snap_name"
        log_message "Created LVM snapshot: $snap_name"
        return 0
    else
        error_exit "Failed to create LVM snapshot" 1
    fi
}

lvm_list_snapshots() {
    local volume="$1"
    local vg_name=$(echo "$volume" | cut -d'/' -f3)
    local lv_name=$(echo "$volume" | cut -d'/' -f4)

    verbose "Listing snapshots for $vg_name/$lv_name"

    if [[ "$JSON_OUTPUT" == true ]]; then
        lvs --reportformat json -o lv_name,lv_size,lv_attr,origin,snap_percent "$vg_name" 2>/dev/null | \
            grep -A 20 "\"origin\" : \"$lv_name\""
    else
        echo ""
        echo -e "${WHITE}━━━ LVM SNAPSHOTS ━━━${NC}"
        printf "${CYAN}%-30s %-10s %-10s %-10s${NC}\n" "SNAPSHOT" "SIZE" "ORIGIN" "USED%"
        echo "────────────────────────────────────────────────────────────────"

        lvs -o lv_name,lv_size,origin,snap_percent --noheadings "$vg_name" 2>/dev/null | \
        grep "$lv_name" | while read -r name size origin percent; do
            if [[ "$origin" == "$lv_name" ]]; then
                printf "%-30s %-10s %-10s %-10s\n" "$name" "$size" "$origin" "$percent"
            fi
        done
        echo ""
    fi
}

lvm_delete_snapshot() {
    local snap_name="$1"
    local volume="$2"
    local vg_name=$(echo "$volume" | cut -d'/' -f3)

    warning "Deleting LVM snapshot: $snap_name"

    if lvremove -f "/dev/$vg_name/$snap_name" 2>&1 | tee -a "$LOG_FILE"; then
        success "LVM snapshot deleted: $snap_name"
        log_message "Deleted LVM snapshot: $snap_name"
        return 0
    else
        error_exit "Failed to delete LVM snapshot" 1
    fi
}

lvm_rollback_snapshot() {
    local snap_name="$1"
    local volume="$2"

    warning "Rolling back to LVM snapshot: $snap_name"
    warning "This will merge the snapshot back to the origin volume"

    if lvconvert --merge "/dev/$(echo $volume | cut -d'/' -f3)/$snap_name" 2>&1 | tee -a "$LOG_FILE"; then
        success "LVM snapshot merge initiated"
        info "Note: Merge will complete on next activation (may require reboot)"
        log_message "Initiated LVM snapshot rollback: $snap_name"
        return 0
    else
        error_exit "Failed to rollback LVM snapshot" 1
    fi
}

lvm_space_usage() {
    local volume="$1"
    local vg_name=$(echo "$volume" | cut -d'/' -f3)

    echo ""
    echo -e "${WHITE}━━━ LVM SPACE USAGE ━━━${NC}"

    vgs "$vg_name" -o vg_name,vg_size,vg_free --units g
    echo ""

    echo -e "${CYAN}Snapshot Space Usage:${NC}"
    lvs -o lv_name,lv_size,snap_percent --units g "$vg_name" | grep -v "^  LV"
    echo ""
}

################################################################################
# BTRFS Functions
################################################################################

btrfs_create_snapshot() {
    local subvolume="$1"
    local snap_name="$2"
    local snap_path="$(dirname "$subvolume")/.snapshots/$snap_name"

    mkdir -p "$(dirname "$snap_path")"

    info "Creating BTRFS snapshot: $snap_name"
    verbose "Subvolume: $subvolume"

    if btrfs subvolume snapshot -r "$subvolume" "$snap_path" 2>&1 | tee -a "$LOG_FILE"; then
        success "BTRFS snapshot created: $snap_path"
        log_message "Created BTRFS snapshot: $snap_path"
        return 0
    else
        error_exit "Failed to create BTRFS snapshot" 1
    fi
}

btrfs_list_snapshots() {
    local path="$1"
    local snap_dir="$(dirname "$path")/.snapshots"

    if [[ ! -d "$snap_dir" ]]; then
        warning "No snapshots found at $snap_dir"
        return 0
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        btrfs subvolume list -s "$snap_dir" -o json 2>/dev/null || \
            btrfs subvolume list -s "$snap_dir" 2>/dev/null
    else
        echo ""
        echo -e "${WHITE}━━━ BTRFS SNAPSHOTS ━━━${NC}"
        printf "${CYAN}%-30s %-20s %-10s${NC}\n" "SNAPSHOT" "CREATION TIME" "PATH"
        echo "────────────────────────────────────────────────────────────────"

        btrfs subvolume list -s "$snap_dir" 2>/dev/null | while read -r line; do
            local id=$(echo "$line" | awk '{print $2}')
            local path=$(echo "$line" | awk '{print $NF}')
            local name=$(basename "$path")
            local create_time=$(btrfs subvolume show "$snap_dir/$name" 2>/dev/null | grep "Creation time:" | cut -d: -f2- | xargs)

            printf "%-30s %-20s %-s\n" "$name" "${create_time:0:19}" "$path"
        done
        echo ""
    fi
}

btrfs_delete_snapshot() {
    local snap_name="$1"
    local path="$2"
    local snap_path="$(dirname "$path")/.snapshots/$snap_name"

    if [[ ! -d "$snap_path" ]]; then
        error_exit "Snapshot not found: $snap_path" 1
    fi

    warning "Deleting BTRFS snapshot: $snap_name"

    if btrfs subvolume delete "$snap_path" 2>&1 | tee -a "$LOG_FILE"; then
        success "BTRFS snapshot deleted: $snap_name"
        log_message "Deleted BTRFS snapshot: $snap_name"
        return 0
    else
        error_exit "Failed to delete BTRFS snapshot" 1
    fi
}

btrfs_rollback_snapshot() {
    local snap_name="$1"
    local path="$2"
    local snap_path="$(dirname "$path")/.snapshots/$snap_name"

    if [[ ! -d "$snap_path" ]]; then
        error_exit "Snapshot not found: $snap_path" 1
    fi

    warning "Rolling back to BTRFS snapshot: $snap_name"
    warning "This will move current subvolume and restore snapshot"

    local backup_name="$(basename "$path").backup-$(date +%Y%m%d%H%M%S)"
    local backup_path="$(dirname "$path")/$backup_name"

    # Move current subvolume
    if mv "$path" "$backup_path"; then
        verbose "Backed up current subvolume to: $backup_path"

        # Create writable snapshot from read-only snapshot
        if btrfs subvolume snapshot "$snap_path" "$path" 2>&1 | tee -a "$LOG_FILE"; then
            success "Rollback completed successfully"
            info "Previous subvolume backed up to: $backup_path"
            log_message "Rolled back to BTRFS snapshot: $snap_name"
            return 0
        else
            # Restore if snapshot creation failed
            mv "$backup_path" "$path"
            error_exit "Failed to create snapshot for rollback" 1
        fi
    else
        error_exit "Failed to backup current subvolume" 1
    fi
}

btrfs_space_usage() {
    local path="$1"

    echo ""
    echo -e "${WHITE}━━━ BTRFS SPACE USAGE ━━━${NC}"

    btrfs filesystem df "$path"
    echo ""

    echo -e "${CYAN}Subvolume Usage:${NC}"
    btrfs qgroup show "$path" 2>/dev/null || echo "Quota not enabled"
    echo ""
}

################################################################################
# Common Functions
################################################################################

rotate_snapshots() {
    local count=$ROTATION_COUNT
    local path="$VOLUME_PATH"

    if [[ $count -le 0 ]]; then
        return 0
    fi

    info "Rotating snapshots (keeping last $count)"

    case "$SNAPSHOT_TYPE" in
        lvm)
            local vg_name=$(echo "$path" | cut -d'/' -f3)
            local lv_name=$(echo "$path" | cut -d'/' -f4)

            local snapshots=($(lvs -o lv_name --noheadings "$vg_name" 2>/dev/null | \
                grep -v "^  $lv_name$" | sort -r))

            local idx=0
            for snap in "${snapshots[@]}"; do
                ((idx++))
                if [[ $idx -gt $count ]]; then
                    verbose "Removing old snapshot: $snap"
                    lvm_delete_snapshot "$snap" "$path"
                fi
            done
            ;;

        btrfs)
            local snap_dir="$(dirname "$path")/.snapshots"

            if [[ -d "$snap_dir" ]]; then
                local snapshots=($(ls -1t "$snap_dir" 2>/dev/null))

                local idx=0
                for snap in "${snapshots[@]}"; do
                    ((idx++))
                    if [[ $idx -gt $count ]]; then
                        verbose "Removing old snapshot: $snap"
                        btrfs_delete_snapshot "$snap" "$path"
                    fi
                done
            fi
            ;;
    esac

    success "Snapshot rotation completed"
}

generate_snapshot_name() {
    if [[ -n "$SNAPSHOT_NAME" ]]; then
        echo "$SNAPSHOT_NAME"
    else
        echo "snap-$(date +%Y%m%d-%H%M%S)"
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
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "--type requires a type (lvm|btrfs)" 2
            SNAPSHOT_TYPE="$2"
            shift 2
            ;;
        -V|--volume)
            [[ -z "${2:-}" ]] && error_exit "--volume requires a path" 2
            VOLUME_PATH="$2"
            shift 2
            ;;
        -n|--name)
            [[ -z "${2:-}" ]] && error_exit "--name requires a name" 2
            SNAPSHOT_NAME="$2"
            shift 2
            ;;
        -c|--create)
            ACTION="create"
            shift
            ;;
        -d|--delete)
            [[ -z "${2:-}" ]] && error_exit "--delete requires a snapshot name" 2
            ACTION="delete"
            DELETE_NAME="$2"
            shift 2
            ;;
        -l|--list)
            ACTION="list"
            shift
            ;;
        -r|--rollback)
            [[ -z "${2:-}" ]] && error_exit "--rollback requires a snapshot name" 2
            ACTION="rollback"
            ROLLBACK_NAME="$2"
            shift 2
            ;;
        --rotate)
            [[ -z "${2:-}" ]] && error_exit "--rotate requires a number" 2
            ROTATION_COUNT="$2"
            shift 2
            ;;
        --size)
            [[ -z "${2:-}" ]] && error_exit "--size requires a size value" 2
            SNAPSHOT_SIZE="$2"
            shift 2
            ;;
        --schedule)
            [[ -z "${2:-}" ]] && error_exit "--schedule requires a cron expression" 2
            SCHEDULE_EXPR="$2"
            shift 2
            ;;
        --space)
            SHOW_SPACE=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        *)
            error_exit "Unknown option: $1\nUse -h or --help for usage information." 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_root
check_dependencies

[[ -z "$VOLUME_PATH" ]] && error_exit "Volume path required (use -V or --volume)" 2

verbose "Volume: $VOLUME_PATH"
verbose "Type: $SNAPSHOT_TYPE"

log_message "Snapshot manager started - Action: ${ACTION:-none}, Volume: $VOLUME_PATH"

# Execute action
case "$ACTION" in
    create)
        local snap_name=$(generate_snapshot_name)
        case "$SNAPSHOT_TYPE" in
            lvm)
                lvm_create_snapshot "$VOLUME_PATH" "$snap_name"
                ;;
            btrfs)
                btrfs_create_snapshot "$VOLUME_PATH" "$snap_name"
                ;;
        esac

        if [[ $ROTATION_COUNT -gt 0 ]]; then
            rotate_snapshots
        fi
        ;;

    delete)
        case "$SNAPSHOT_TYPE" in
            lvm)
                lvm_delete_snapshot "$DELETE_NAME" "$VOLUME_PATH"
                ;;
            btrfs)
                btrfs_delete_snapshot "$DELETE_NAME" "$VOLUME_PATH"
                ;;
        esac
        ;;

    list)
        case "$SNAPSHOT_TYPE" in
            lvm)
                lvm_list_snapshots "$VOLUME_PATH"
                ;;
            btrfs)
                btrfs_list_snapshots "$VOLUME_PATH"
                ;;
        esac
        ;;

    rollback)
        case "$SNAPSHOT_TYPE" in
            lvm)
                lvm_rollback_snapshot "$ROLLBACK_NAME" "$VOLUME_PATH"
                ;;
            btrfs)
                btrfs_rollback_snapshot "$ROLLBACK_NAME" "$VOLUME_PATH"
                ;;
        esac
        ;;

    "")
        # No action specified, show space or list
        if [[ "$SHOW_SPACE" == true ]]; then
            case "$SNAPSHOT_TYPE" in
                lvm)
                    lvm_space_usage "$VOLUME_PATH"
                    ;;
                btrfs)
                    btrfs_space_usage "$VOLUME_PATH"
                    ;;
            esac
        else
            # Default to list
            case "$SNAPSHOT_TYPE" in
                lvm)
                    lvm_list_snapshots "$VOLUME_PATH"
                    ;;
                btrfs)
                    btrfs_list_snapshots "$VOLUME_PATH"
                    ;;
            esac
        fi
        ;;
esac

log_message "Snapshot manager completed successfully"
success "Operation completed successfully"
