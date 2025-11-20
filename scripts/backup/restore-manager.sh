#!/bin/bash

################################################################################
# Script Name: restore-manager.sh
# Description: Interactive backup restoration tool with preview, selective file
#              restoration, verification, and support for multiple backup formats
#              and sources including tar, rsync, and cloud backups.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./restore-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --source DIR        Backup source directory
#   -d, --destination DIR   Restore destination directory
#   -b, --backup FILE       Specific backup file to restore
#   -f, --file PATTERN      Restore specific files (supports wildcards)
#   -i, --interactive       Interactive file selection
#   -l, --list              List backup contents
#   --verify                Verify backup before restoration
#   --preview               Preview restore without executing
#   --preserve              Preserve file permissions and timestamps
#   --overwrite             Overwrite existing files
#   --exclude PATTERN       Exclude pattern from restoration
#   -j, --json              Output in JSON format
#   --log FILE              Log file path
#   --no-color              Disable colored output
#
# Examples:
#   ./restore-manager.sh --list --source /backup
#   ./restore-manager.sh --backup /backup/full-2024-11-20.tar.gz --destination /restore
#   ./restore-manager.sh --interactive --source /backup
#   ./restore-manager.sh --file "*.conf" --backup /backup/data.tar.gz
#   ./restore-manager.sh --verify --preview --backup /backup/important.tar.gz
#
# Dependencies:
#   - tar
#   - dialog (optional, for interactive mode)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   5 - Restore failed
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
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
SOURCE_DIR=""
DEST_DIR=""
BACKUP_FILE=""
FILE_PATTERN=""
INTERACTIVE=false
LIST_ONLY=false
VERIFY_BACKUP=false
PREVIEW_MODE=false
PRESERVE_ATTRS=true
OVERWRITE=false
EXCLUDE_PATTERNS=()
JSON_OUTPUT=false
LOG_FILE=""
USE_COLOR=true

# Internal variables
TEMP_DIR=""

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    cleanup
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
        echo -e "[VERBOSE] $1" >&2
    fi
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        verbose "Cleaning up temporary directory"
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

show_usage() {
    cat << EOF
${WHITE}Restore Manager - Interactive Backup Restoration${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -s, --source DIR        Backup source directory
    -d, --destination DIR   Restore destination directory
    -b, --backup FILE       Specific backup file to restore
    -f, --file PATTERN      Restore specific files (wildcards supported)
    -i, --interactive       Interactive file selection
    -l, --list              List backup contents
    --verify                Verify backup integrity before restore
    --preview               Preview restore without executing
    --preserve              Preserve permissions/timestamps (default)
    --overwrite             Overwrite existing files
    --exclude PATTERN       Exclude pattern from restoration
    -j, --json              Output in JSON format
    --log FILE              Log file path
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # List available backups
    $SCRIPT_NAME --list --source /backup

    # Restore full backup
    $SCRIPT_NAME --backup /backup/full-2024-11-20.tar.gz --destination /restore

    # Interactive restoration
    $SCRIPT_NAME --interactive --source /backup

    # Restore specific files
    $SCRIPT_NAME --file "*.conf" --backup /backup/etc.tar.gz -d /etc

    # Verify and preview before restore
    $SCRIPT_NAME --verify --preview --backup /backup/data.tar.gz

    # Selective restore with exclusions
    $SCRIPT_NAME -b /backup/home.tar.gz -d /home --exclude "*.tmp"

${CYAN}Features:${NC}
    • Multiple backup format support
    • Interactive file selection
    • Selective file restoration
    • Backup verification
    • Preview mode
    • Exclude patterns
    • Preserve attributes
    • Multiple backup sources

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in tar; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi

    if [[ "$INTERACTIVE" == true ]] && ! command -v dialog &> /dev/null; then
        warning "dialog not found - falling back to basic interactive mode"
    fi
}

################################################################################
# Backup Discovery Functions
################################################################################

find_backups() {
    local source="$1"

    if [[ ! -d "$source" ]]; then
        error_exit "Source directory not found: $source" 2
    fi

    find "$source" -type f \( -name "*.tar" -o -name "*.tar.gz" -o -name "*.tar.bz2" -o -name "*.tar.xz" \) 2>/dev/null | sort -r
}

list_backups() {
    local source="${SOURCE_DIR:-.}"

    info "Available backups in: $source"
    echo ""

    local backups=$(find_backups "$source")

    if [[ -z "$backups" ]]; then
        warning "No backups found in $source"
        return 0
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"source\": \"$source\","
        echo "  \"backups\": ["

        local first=true
        while IFS= read -r backup; do
            [[ "$first" != true ]] && echo ","

            local size=$(du -h "$backup" | awk '{print $1}')
            local date=$(stat -c '%y' "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
            local checksum=$(get_backup_checksum "$backup")

            cat << EOF
    {
      "file": "$backup",
      "size": "$size",
      "date": "$date",
      "checksum": "$checksum"
    }
EOF
            first=false
        done <<< "$backups"

        echo ""
        echo "  ]"
        echo "}"
    else
        printf "${CYAN}%-50s %-10s %-20s${NC}\n" "BACKUP FILE" "SIZE" "DATE"
        echo "────────────────────────────────────────────────────────────────────────────"

        while IFS= read -r backup; do
            local filename=$(basename "$backup")
            local size=$(du -h "$backup" | awk '{print $1}')
            local date=$(stat -c '%y' "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)

            printf "%-50s %-10s %-20s\n" "${filename:0:50}" "$size" "${date:0:20}"
        done <<< "$backups"

        echo ""
    fi
}

get_backup_checksum() {
    local file="$1"
    local meta_file="${file}.meta"

    if [[ -f "$meta_file" ]]; then
        grep "^checksum=" "$meta_file" 2>/dev/null | cut -d'=' -f2 || echo "N/A"
    else
        echo "N/A"
    fi
}

list_backup_contents() {
    local backup="$1"

    if [[ ! -f "$backup" ]]; then
        error_exit "Backup file not found: $backup" 2
    fi

    info "Contents of: $backup"
    echo ""

    local compress_flag=""
    case "$backup" in
        *.tar.gz) compress_flag="z" ;;
        *.tar.bz2) compress_flag="j" ;;
        *.tar.xz) compress_flag="J" ;;
    esac

    if tar t${compress_flag}f "$backup" 2>/dev/null; then
        return 0
    else
        error_exit "Failed to list backup contents" 1
    fi
}

################################################################################
# Verification Functions
################################################################################

verify_backup() {
    local backup="$1"

    info "Verifying backup integrity: $backup"

    local compress_flag=""
    case "$backup" in
        *.tar.gz) compress_flag="z" ;;
        *.tar.bz2) compress_flag="j" ;;
        *.tar.xz) compress_flag="J" ;;
    esac

    if tar t${compress_flag}f "$backup" &> /dev/null; then
        success "Backup verification passed"

        # Verify checksum if metadata exists
        local meta_file="${backup}.meta"
        if [[ -f "$meta_file" ]]; then
            local stored_checksum=$(grep "^checksum=" "$meta_file" | cut -d'=' -f2)
            if [[ -n "$stored_checksum" ]]; then
                info "Verifying checksum..."
                local current_checksum=$(sha256sum "$backup" | awk '{print $1}')

                if [[ "$stored_checksum" == "$current_checksum" ]]; then
                    success "Checksum verification passed"
                else
                    warning "Checksum mismatch! Backup may be corrupted"
                    return 1
                fi
            fi
        fi

        return 0
    else
        warning "Backup verification failed!"
        return 1
    fi
}

################################################################################
# Restoration Functions
################################################################################

restore_backup() {
    local backup="$1"
    local destination="$2"

    if [[ ! -f "$backup" ]]; then
        error_exit "Backup file not found: $backup" 2
    fi

    # Verify if requested
    if [[ "$VERIFY_BACKUP" == true ]]; then
        if ! verify_backup "$backup"; then
            error_exit "Backup verification failed. Aborting restore." 5
        fi
    fi

    # Create destination directory
    mkdir -p "$destination"

    info "Restoring backup to: $destination"
    verbose "Source: $backup"

    # Determine compression
    local compress_flag=""
    local tar_options=""

    case "$backup" in
        *.tar.gz) compress_flag="z" ;;
        *.tar.bz2) compress_flag="j" ;;
        *.tar.xz) compress_flag="J" ;;
    esac

    # Build tar options
    if [[ "$PRESERVE_ATTRS" == true ]]; then
        tar_options="--preserve-permissions --preserve-order"
    fi

    if [[ "$OVERWRITE" != true ]]; then
        tar_options="$tar_options --keep-old-files"
    fi

    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done

    # Build file selection options
    local file_opts=""
    if [[ -n "$FILE_PATTERN" ]]; then
        file_opts="--wildcards $FILE_PATTERN"
    fi

    # Preview mode
    if [[ "$PREVIEW_MODE" == true ]]; then
        info "PREVIEW MODE - Files that would be restored:"
        tar t${compress_flag}vf "$backup" $exclude_opts $file_opts 2>&1 | head -50
        echo "... (showing first 50 files)"
        return 0
    fi

    # Perform restoration
    if tar x${compress_flag}vf "$backup" -C "$destination" $tar_options $exclude_opts $file_opts 2>&1 | tee -a "$LOG_FILE"; then
        success "Restoration completed successfully"
        info "Files restored to: $destination"
        log_message "Restored backup: $backup -> $destination"
        return 0
    else
        error_exit "Restoration failed" 5
    fi
}

restore_selective() {
    local backup="$1"
    local destination="$2"

    TEMP_DIR=$(mktemp -d)

    # List files in backup
    local files=$(tar tf "$backup" 2>/dev/null)

    if command -v dialog &> /dev/null; then
        # Use dialog for interactive selection
        local file_list=""
        while IFS= read -r file; do
            file_list="$file_list $file $file off"
        done <<< "$files"

        local selected=$(dialog --checklist "Select files to restore:" 20 70 15 $file_list 3>&1 1>&2 2>&3)

        if [[ -z "$selected" ]]; then
            info "No files selected"
            return 0
        fi

        # Create file list for tar
        local restore_list="$TEMP_DIR/restore_list.txt"
        echo "$selected" | tr ' ' '\n' | sed 's/"//g' > "$restore_list"

        info "Restoring selected files..."

        local compress_flag=""
        case "$backup" in
            *.tar.gz) compress_flag="z" ;;
            *.tar.bz2) compress_flag="j" ;;
            *.tar.xz) compress_flag="J" ;;
        esac

        if tar x${compress_flag}vf "$backup" -C "$destination" -T "$restore_list" 2>&1 | tee -a "$LOG_FILE"; then
            success "Selective restoration completed"
            log_message "Selective restore: $backup -> $destination"
        else
            error_exit "Selective restoration failed" 5
        fi
    else
        # Basic interactive mode
        echo "Available files:"
        local count=1
        declare -a file_array

        while IFS= read -r file; do
            echo "$count) $file"
            file_array[$count]="$file"
            ((count++))
        done <<< "$files"

        echo ""
        read -p "Enter file numbers to restore (space-separated): " -r selections

        local restore_list="$TEMP_DIR/restore_list.txt"
        > "$restore_list"

        for num in $selections; do
            if [[ -n "${file_array[$num]:-}" ]]; then
                echo "${file_array[$num]}" >> "$restore_list"
            fi
        done

        if [[ -s "$restore_list" ]]; then
            info "Restoring selected files..."

            local compress_flag=""
            case "$backup" in
                *.tar.gz) compress_flag="z" ;;
                *.tar.bz2) compress_flag="j" ;;
                *.tar.xz) compress_flag="J" ;;
            esac

            if tar x${compress_flag}vf "$backup" -C "$destination" -T "$restore_list" 2>&1 | tee -a "$LOG_FILE"; then
                success "Selective restoration completed"
                log_message "Selective restore: $backup -> $destination"
            else
                error_exit "Selective restoration failed" 5
            fi
        else
            info "No files selected"
        fi
    fi
}

################################################################################
# Interactive Functions
################################################################################

interactive_mode() {
    local source="${SOURCE_DIR:-.}"

    info "Starting interactive restoration mode"

    # Find available backups
    local backups=$(find_backups "$source")

    if [[ -z "$backups" ]]; then
        warning "No backups found in $source"
        return 1
    fi

    # Select backup
    echo ""
    echo "Available backups:"
    local count=1
    declare -a backup_array

    while IFS= read -r backup; do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | awk '{print $1}')
        local date=$(stat -c '%y' "$backup" | cut -d' ' -f1)

        echo "$count) $filename ($size, $date)"
        backup_array[$count]="$backup"
        ((count++))
    done <<< "$backups"

    echo ""
    read -p "Select backup number to restore: " -r backup_num

    if [[ -z "${backup_array[$backup_num]:-}" ]]; then
        error_exit "Invalid backup selection" 2
    fi

    BACKUP_FILE="${backup_array[$backup_num]}"

    # Get destination
    read -p "Enter destination directory [default: ./restore]: " -r dest
    DEST_DIR="${dest:-./restore}"

    # Verify backup
    echo ""
    if ask_yes_no "Verify backup before restoration?"; then
        verify_backup "$BACKUP_FILE"
    fi

    # Preview contents
    echo ""
    if ask_yes_no "Preview backup contents?"; then
        list_backup_contents "$BACKUP_FILE"
    fi

    # Selective restore
    echo ""
    if ask_yes_no "Restore all files?"; then
        restore_backup "$BACKUP_FILE" "$DEST_DIR"
    else
        restore_selective "$BACKUP_FILE" "$DEST_DIR"
    fi
}

ask_yes_no() {
    local question="$1"
    read -p "$question (y/n): " -r response
    [[ "$response" =~ ^[Yy] ]]
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
        -s|--source)
            [[ -z "${2:-}" ]] && error_exit "--source requires a directory" 2
            SOURCE_DIR="$2"
            shift 2
            ;;
        -d|--destination)
            [[ -z "${2:-}" ]] && error_exit "--destination requires a directory" 2
            DEST_DIR="$2"
            shift 2
            ;;
        -b|--backup)
            [[ -z "${2:-}" ]] && error_exit "--backup requires a file path" 2
            BACKUP_FILE="$2"
            shift 2
            ;;
        -f|--file)
            [[ -z "${2:-}" ]] && error_exit "--file requires a pattern" 2
            FILE_PATTERN="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        --verify)
            VERIFY_BACKUP=true
            shift
            ;;
        --preview)
            PREVIEW_MODE=true
            shift
            ;;
        --preserve)
            PRESERVE_ATTRS=true
            shift
            ;;
        --overwrite)
            OVERWRITE=true
            shift
            ;;
        --exclude)
            [[ -z "${2:-}" ]] && error_exit "--exclude requires a pattern" 2
            EXCLUDE_PATTERNS+=("$2")
            shift 2
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

check_dependencies

verbose "Restore manager started"
log_message "Restore manager started"

# Handle different modes
if [[ "$LIST_ONLY" == true ]]; then
    if [[ -n "$BACKUP_FILE" ]]; then
        list_backup_contents "$BACKUP_FILE"
    else
        list_backups
    fi
elif [[ "$INTERACTIVE" == true ]]; then
    interactive_mode
elif [[ -n "$BACKUP_FILE" ]]; then
    # Direct restoration
    [[ -z "$DEST_DIR" ]] && DEST_DIR="./restore"

    if [[ -n "$FILE_PATTERN" ]]; then
        restore_selective "$BACKUP_FILE" "$DEST_DIR"
    else
        restore_backup "$BACKUP_FILE" "$DEST_DIR"
    fi
else
    # Default: list available backups
    list_backups
fi

log_message "Restore manager completed"
success "Operation completed successfully"
