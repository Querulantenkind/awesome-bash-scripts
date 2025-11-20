#!/bin/bash

################################################################################
# Script Name: backup-manager.sh
# Description: Comprehensive backup solution with full, incremental, and
#              differential backup support. Features compression, encryption,
#              rotation, verification, and restore capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./backup-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -c, --config FILE       Configuration file path
#   -s, --source DIR        Source directory to backup
#   -d, --destination DIR   Backup destination directory
#   -t, --type TYPE         Backup type (full|incremental|differential)
#   -n, --name NAME         Backup name/identifier
#   -m, --compress METHOD   Compression method (gzip|bzip2|xz|none)
#   -e, --encrypt           Enable encryption (requires gpg)
#   -k, --key EMAIL         GPG key email for encryption
#   -r, --rotate NUM        Keep last N backups (rotation)
#   -x, --exclude PATTERN   Exclude pattern (can be used multiple times)
#   --verify                Verify backup integrity
#   --restore FILE          Restore from backup file
#   --list                  List available backups
#   --dry-run               Show what would be backed up without doing it
#   -l, --log FILE          Log file path
#
# Examples:
#   ./backup-manager.sh -s /home/user -d /backup -t full
#   ./backup-manager.sh -s /var/www -d /backup -t incremental -m xz
#   ./backup-manager.sh -s /home -d /backup -e -k user@example.com
#   ./backup-manager.sh --restore /backup/full-2024-11-20.tar.gz -d /restore
#   ./backup-manager.sh --list -d /backup
#
# Dependencies:
#   - tar
#   - gzip/bzip2/xz (optional, for compression)
#   - gpg (optional, for encryption)
#   - sha256sum (for verification)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Backup failed
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
CONFIG_FILE=""
SOURCE_DIR=""
DEST_DIR=""
BACKUP_TYPE="full"
BACKUP_NAME=""
COMPRESS_METHOD="gzip"
ENABLE_ENCRYPT=false
GPG_KEY=""
ROTATION_COUNT=7
EXCLUDE_PATTERNS=()
VERIFY_BACKUP=false
RESTORE_FILE=""
LIST_BACKUPS=false
DRY_RUN=false
LOG_FILE=""
USE_COLOR=true

# Internal variables
BACKUP_DATE=$(date '+%Y-%m-%d_%H-%M-%S')
TEMP_DIR="/tmp/backup-$$"
METADATA_FILE=""

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    cleanup
    exit "${2:-1}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}" >&2
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
    if [[ -d "$TEMP_DIR" ]]; then
        verbose "Cleaning up temporary directory"
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

show_usage() {
    cat << EOF
${WHITE}Backup Manager - Comprehensive Backup Solution${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -c, --config FILE       Configuration file path
    -s, --source DIR        Source directory to backup
    -d, --destination DIR   Backup destination directory
    -t, --type TYPE         Backup type (full|incremental|differential)
    -n, --name NAME         Backup name/identifier
    -m, --compress METHOD   Compression (gzip|bzip2|xz|none, default: gzip)
    -e, --encrypt           Enable GPG encryption
    -k, --key EMAIL         GPG key email for encryption
    -r, --rotate NUM        Keep last N backups (default: 7)
    -x, --exclude PATTERN   Exclude pattern (can be used multiple times)
    --verify                Verify backup integrity after creation
    --restore FILE          Restore from backup file
    --list                  List available backups
    --dry-run               Show what would be backed up
    -l, --log FILE          Log file path

${CYAN}Examples:${NC}
    # Full backup with compression
    $SCRIPT_NAME -s /home/user -d /backup -t full -m xz

    # Incremental backup
    $SCRIPT_NAME -s /var/www -d /backup -t incremental

    # Encrypted backup
    $SCRIPT_NAME -s /home -d /backup -e -k user@example.com

    # Backup with exclusions
    $SCRIPT_NAME -s /home -d /backup -x "*.tmp" -x "*.cache"

    # Restore from backup
    $SCRIPT_NAME --restore /backup/full-2024-11-20.tar.gz -d /restore

    # List available backups
    $SCRIPT_NAME --list -d /backup

    # Dry run to see what would be backed up
    $SCRIPT_NAME -s /home/user -d /backup --dry-run

${CYAN}Backup Types:${NC}
    full          Complete backup of all files
    incremental   Only files changed since last backup
    differential  Files changed since last full backup

${CYAN}Features:${NC}
    • Multiple backup types (full, incremental, differential)
    • Compression support (gzip, bzip2, xz)
    • GPG encryption support
    • Backup rotation and cleanup
    • Integrity verification
    • Exclude patterns
    • Metadata tracking
    • Restore capabilities
    • Dry-run mode

EOF
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in tar sha256sum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi
    
    # Check compression tools
    case "$COMPRESS_METHOD" in
        gzip)
            if ! command -v gzip &> /dev/null; then
                error_exit "gzip not found" 3
            fi
            ;;
        bzip2)
            if ! command -v bzip2 &> /dev/null; then
                error_exit "bzip2 not found" 3
            fi
            ;;
        xz)
            if ! command -v xz &> /dev/null; then
                error_exit "xz not found" 3
            fi
            ;;
    esac
    
    # Check encryption
    if [[ "$ENABLE_ENCRYPT" == true ]]; then
        if ! command -v gpg &> /dev/null; then
            error_exit "gpg not found (required for encryption)" 3
        fi
        
        if [[ -z "$GPG_KEY" ]]; then
            error_exit "GPG key email required for encryption (use -k option)" 2
        fi
    fi
}

################################################################################
# Backup Functions
################################################################################

get_compress_extension() {
    case "$COMPRESS_METHOD" in
        gzip) echo ".gz" ;;
        bzip2) echo ".bz2" ;;
        xz) echo ".xz" ;;
        none) echo "" ;;
    esac
}

get_compress_flag() {
    case "$COMPRESS_METHOD" in
        gzip) echo "z" ;;
        bzip2) echo "j" ;;
        xz) echo "J" ;;
        none) echo "" ;;
    esac
}

generate_backup_filename() {
    local type="$1"
    local ext=$(get_compress_extension)
    
    if [[ -n "$BACKUP_NAME" ]]; then
        echo "${BACKUP_NAME}_${type}_${BACKUP_DATE}.tar${ext}"
    else
        echo "${type}_${BACKUP_DATE}.tar${ext}"
    fi
}

create_metadata_file() {
    local backup_file="$1"
    local metadata_file="${backup_file}.meta"
    
    cat > "$metadata_file" << EOF
backup_date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
backup_type=$BACKUP_TYPE
source_dir=$SOURCE_DIR
hostname=$(hostname)
user=$USER
compression=$COMPRESS_METHOD
encrypted=$ENABLE_ENCRYPT
file_count=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l)
total_size=$(du -sh "$SOURCE_DIR" 2>/dev/null | awk '{print $1}')
checksum=$(sha256sum "$backup_file" | awk '{print $1}')
EOF
    
    success "Created metadata file: $metadata_file"
}

get_last_backup() {
    local type="$1"
    local pattern="${DEST_DIR}/${type}_*.tar*"
    
    # Find most recent backup of this type
    local last_backup=$(ls -t $pattern 2>/dev/null | head -1)
    
    if [[ -n "$last_backup" ]]; then
        echo "$last_backup"
    fi
}

perform_full_backup() {
    info "Starting full backup..."
    
    local backup_file="${DEST_DIR}/$(generate_backup_filename "full")"
    local compress_flag=$(get_compress_flag)
    local tar_options="c${compress_flag}f"
    
    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done
    
    verbose "Backup file: $backup_file"
    verbose "Compression: $COMPRESS_METHOD"
    verbose "Source: $SOURCE_DIR"
    
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN - Would backup:"
        tar -c${compress_flag}v $exclude_opts -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")" 2>&1 | head -20
        echo "... (showing first 20 files)"
        return 0
    fi
    
    # Create backup
    if tar $tar_options "$backup_file" $exclude_opts -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")" 2>&1 | tee -a "$LOG_FILE"; then
        success "Full backup created: $backup_file"
        
        # Encrypt if requested
        if [[ "$ENABLE_ENCRYPT" == true ]]; then
            encrypt_backup "$backup_file"
        fi
        
        # Create metadata
        create_metadata_file "$backup_file"
        
        # Verify if requested
        if [[ "$VERIFY_BACKUP" == true ]]; then
            verify_backup "$backup_file"
        fi
        
        log_message "Full backup completed: $backup_file"
    else
        error_exit "Full backup failed" 4
    fi
}

perform_incremental_backup() {
    info "Starting incremental backup..."
    
    local last_backup=$(get_last_backup "incremental")
    
    if [[ -z "$last_backup" ]]; then
        last_backup=$(get_last_backup "full")
        if [[ -z "$last_backup" ]]; then
            warning "No previous backup found, performing full backup instead"
            perform_full_backup
            return
        fi
    fi
    
    verbose "Using reference: $last_backup"
    
    local backup_file="${DEST_DIR}/$(generate_backup_filename "incremental")"
    local compress_flag=$(get_compress_flag)
    local snapshot_file="${DEST_DIR}/.snapshot"
    
    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN - Would backup files newer than: $last_backup"
        find "$SOURCE_DIR" -type f -newer "$last_backup" 2>/dev/null | head -20
        echo "... (showing first 20 files)"
        return 0
    fi
    
    # Create incremental backup using snapshot
    if tar c${compress_flag}f "$backup_file" --listed-incremental="$snapshot_file" $exclude_opts -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")" 2>&1 | tee -a "$LOG_FILE"; then
        success "Incremental backup created: $backup_file"
        
        if [[ "$ENABLE_ENCRYPT" == true ]]; then
            encrypt_backup "$backup_file"
        fi
        
        create_metadata_file "$backup_file"
        
        if [[ "$VERIFY_BACKUP" == true ]]; then
            verify_backup "$backup_file"
        fi
        
        log_message "Incremental backup completed: $backup_file"
    else
        error_exit "Incremental backup failed" 4
    fi
}

perform_differential_backup() {
    info "Starting differential backup..."
    
    local last_full=$(get_last_backup "full")
    
    if [[ -z "$last_full" ]]; then
        warning "No full backup found, performing full backup instead"
        perform_full_backup
        return
    fi
    
    verbose "Using reference: $last_full"
    
    local backup_file="${DEST_DIR}/$(generate_backup_filename "differential")"
    local compress_flag=$(get_compress_flag)
    
    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN - Would backup files newer than: $last_full"
        find "$SOURCE_DIR" -type f -newer "$last_full" 2>/dev/null | head -20
        echo "... (showing first 20 files)"
        return 0
    fi
    
    # Create differential backup
    mkdir -p "$TEMP_DIR"
    find "$SOURCE_DIR" -type f -newer "$last_full" > "$TEMP_DIR/files.txt"
    
    if tar c${compress_flag}f "$backup_file" $exclude_opts -T "$TEMP_DIR/files.txt" 2>&1 | tee -a "$LOG_FILE"; then
        success "Differential backup created: $backup_file"
        
        if [[ "$ENABLE_ENCRYPT" == true ]]; then
            encrypt_backup "$backup_file"
        fi
        
        create_metadata_file "$backup_file"
        
        if [[ "$VERIFY_BACKUP" == true ]]; then
            verify_backup "$backup_file"
        fi
        
        log_message "Differential backup completed: $backup_file"
    else
        error_exit "Differential backup failed" 4
    fi
}

encrypt_backup() {
    local backup_file="$1"
    
    info "Encrypting backup with GPG..."
    
    if gpg --encrypt --recipient "$GPG_KEY" "$backup_file" 2>&1 | tee -a "$LOG_FILE"; then
        rm -f "$backup_file"
        success "Backup encrypted: ${backup_file}.gpg"
        log_message "Backup encrypted successfully"
    else
        error_exit "Encryption failed" 4
    fi
}

verify_backup() {
    local backup_file="$1"
    
    info "Verifying backup integrity..."
    
    if [[ "$backup_file" == *.gpg ]]; then
        warning "Cannot verify encrypted backup without decryption"
        return
    fi
    
    local compress_flag=$(get_compress_flag)
    
    if tar t${compress_flag}f "$backup_file" > /dev/null 2>&1; then
        success "Backup verification passed"
        log_message "Backup verified successfully"
    else
        warning "Backup verification failed!"
        log_message "WARNING: Backup verification failed"
    fi
}

restore_backup() {
    local backup_file="$RESTORE_FILE"
    local restore_dir="${DEST_DIR:-./restore}"
    
    info "Restoring from: $backup_file"
    info "Restore destination: $restore_dir"
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Backup file not found: $backup_file" 5
    fi
    
    mkdir -p "$restore_dir"
    
    # Handle encrypted backups
    if [[ "$backup_file" == *.gpg ]]; then
        info "Decrypting backup..."
        local decrypted="${TEMP_DIR}/backup.tar"
        mkdir -p "$TEMP_DIR"
        
        if ! gpg --decrypt "$backup_file" > "$decrypted" 2>&1 | tee -a "$LOG_FILE"; then
            error_exit "Decryption failed" 5
        fi
        
        backup_file="$decrypted"
    fi
    
    # Determine compression
    local compress_flag=""
    case "$backup_file" in
        *.tar.gz) compress_flag="z" ;;
        *.tar.bz2) compress_flag="j" ;;
        *.tar.xz) compress_flag="J" ;;
        *.tar) compress_flag="" ;;
    esac
    
    info "Extracting backup..."
    
    if tar x${compress_flag}vf "$backup_file" -C "$restore_dir" 2>&1 | tee -a "$LOG_FILE"; then
        success "Restore completed successfully"
        info "Files restored to: $restore_dir"
        log_message "Restore completed: $backup_file -> $restore_dir"
    else
        error_exit "Restore failed" 5
    fi
}

rotate_backups() {
    if [[ $ROTATION_COUNT -le 0 ]]; then
        return
    fi
    
    info "Rotating backups (keeping last $ROTATION_COUNT)..."
    
    for type in full incremental differential; do
        local pattern="${DEST_DIR}/${type}_*.tar*"
        local backups=$(ls -t $pattern 2>/dev/null)
        local count=0
        
        for backup in $backups; do
            ((count++))
            if [[ $count -gt $ROTATION_COUNT ]]; then
                verbose "Removing old backup: $backup"
                rm -f "$backup" "${backup}.meta" "${backup}.gpg"
                log_message "Removed old backup: $backup"
            fi
        done
    done
    
    success "Backup rotation completed"
}

list_available_backups() {
    info "Available backups in: $DEST_DIR"
    echo ""
    
    if [[ ! -d "$DEST_DIR" ]]; then
        warning "Backup directory does not exist: $DEST_DIR"
        return
    fi
    
    local backups=$(ls -t "$DEST_DIR"/*.tar* 2>/dev/null)
    
    if [[ -z "$backups" ]]; then
        warning "No backups found"
        return
    fi
    
    printf "${CYAN}%-30s %-12s %-10s %-s${NC}\n" "Filename" "Type" "Size" "Date"
    echo "────────────────────────────────────────────────────────────────────"
    
    for backup in $backups; do
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | awk '{print $1}')
        local date=$(stat -c '%y' "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        local type="unknown"
        
        if [[ "$filename" =~ ^full_ ]]; then
            type="full"
        elif [[ "$filename" =~ ^incremental_ ]]; then
            type="incremental"
        elif [[ "$filename" =~ ^differential_ ]]; then
            type="differential"
        fi
        
        printf "%-30s %-12s %-10s %-s\n" "${filename:0:30}" "$type" "$size" "$date"
        
        # Show metadata if available
        if [[ -f "${backup}.meta" ]]; then
            local checksum=$(grep "checksum=" "${backup}.meta" | cut -d'=' -f2)
            echo "  └─ Checksum: ${checksum:0:16}..."
        fi
    done
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
        -c|--config)
            [[ -z "${2:-}" ]] && error_exit "--config requires a file path" 2
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--source)
            [[ -z "${2:-}" ]] && error_exit "--source requires a directory path" 2
            SOURCE_DIR="$2"
            shift 2
            ;;
        -d|--destination)
            [[ -z "${2:-}" ]] && error_exit "--destination requires a directory path" 2
            DEST_DIR="$2"
            shift 2
            ;;
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "--type requires a backup type" 2
            BACKUP_TYPE="$2"
            shift 2
            ;;
        -n|--name)
            [[ -z "${2:-}" ]] && error_exit "--name requires a backup name" 2
            BACKUP_NAME="$2"
            shift 2
            ;;
        -m|--compress)
            [[ -z "${2:-}" ]] && error_exit "--compress requires a method" 2
            COMPRESS_METHOD="$2"
            shift 2
            ;;
        -e|--encrypt)
            ENABLE_ENCRYPT=true
            shift
            ;;
        -k|--key)
            [[ -z "${2:-}" ]] && error_exit "--key requires a GPG key email" 2
            GPG_KEY="$2"
            shift 2
            ;;
        -r|--rotate)
            [[ -z "${2:-}" ]] && error_exit "--rotate requires a number" 2
            ROTATION_COUNT="$2"
            shift 2
            ;;
        -x|--exclude)
            [[ -z "${2:-}" ]] && error_exit "--exclude requires a pattern" 2
            EXCLUDE_PATTERNS+=("$2")
            shift 2
            ;;
        --verify)
            VERIFY_BACKUP=true
            shift
            ;;
        --restore)
            [[ -z "${2:-}" ]] && error_exit "--restore requires a file path" 2
            RESTORE_FILE="$2"
            shift 2
            ;;
        --list)
            LIST_BACKUPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -l|--log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Handle special modes
if [[ "$LIST_BACKUPS" == true ]]; then
    [[ -z "$DEST_DIR" ]] && error_exit "Destination directory required (use -d)" 2
    list_available_backups
    exit 0
fi

if [[ -n "$RESTORE_FILE" ]]; then
    restore_backup
    exit 0
fi

# Validate required parameters for backup
if [[ -z "$SOURCE_DIR" ]]; then
    error_exit "Source directory required (use -s)" 2
fi

if [[ -z "$DEST_DIR" ]]; then
    error_exit "Destination directory required (use -d)" 2
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    error_exit "Source directory does not exist: $SOURCE_DIR" 2
fi

# Create destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

verbose "Configuration:"
verbose "  Source: $SOURCE_DIR"
verbose "  Destination: $DEST_DIR"
verbose "  Type: $BACKUP_TYPE"
verbose "  Compression: $COMPRESS_METHOD"
verbose "  Encryption: $ENABLE_ENCRYPT"
verbose "  Rotation: $ROTATION_COUNT"

log_message "Backup started - Type: $BACKUP_TYPE, Source: $SOURCE_DIR"

# Perform backup based on type
case "$BACKUP_TYPE" in
    full)
        perform_full_backup
        ;;
    incremental)
        perform_incremental_backup
        ;;
    differential)
        perform_differential_backup
        ;;
    *)
        error_exit "Invalid backup type: $BACKUP_TYPE (use full|incremental|differential)" 2
        ;;
esac

# Rotate old backups
rotate_backups

success "Backup operation completed successfully!"
log_message "Backup completed successfully"

