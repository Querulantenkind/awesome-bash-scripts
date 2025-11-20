#!/bin/bash

################################################################################
# Script Name: sync-backup.sh
# Description: Rsync-based backup and synchronization tool with incremental
#              backups, bandwidth limiting, scheduling support, and remote
#              backup capabilities. Perfect for continuous backup strategies.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./sync-backup.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --source DIR        Source directory
#   -d, --destination DIR   Destination directory
#   -r, --remote HOST       Remote host for SSH backup
#   -u, --user USER         SSH username for remote backup
#   -p, --port PORT         SSH port (default: 22)
#   -x, --exclude PATTERN   Exclude pattern (can be used multiple times)
#   -b, --bandwidth LIMIT   Bandwidth limit in KB/s
#   -n, --dry-run           Show what would be synced without doing it
#   -D, --delete            Delete files in dest not in source
#   --backup-dir DIR        Store deleted/changed files in backup dir
#   --link-dest DIR         Use hardlinks for unchanged files
#   --compress              Enable compression during transfer
#   --checksum              Use checksum instead of mod-time & size
#   --progress              Show progress during transfer
#   -l, --log FILE          Log file path
#   -c, --config FILE       Use configuration file
#
# Examples:
#   ./sync-backup.sh -s /home/user -d /backup/home
#   ./sync-backup.sh -s /var/www -r backup.server.com -u backupuser
#   ./sync-backup.sh -s /data -d /backup -x "*.tmp" -x "cache/" --delete
#   ./sync-backup.sh -s /home -d /backup --backup-dir /backup/archive
#   ./sync-backup.sh --config /etc/sync-backup.conf
#
# Dependencies:
#   - rsync
#   - ssh (for remote backups)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Sync failed
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
SOURCE_DIR=""
DEST_DIR=""
REMOTE_HOST=""
REMOTE_USER=""
SSH_PORT=22
EXCLUDE_PATTERNS=()
BANDWIDTH_LIMIT=""
DRY_RUN=false
DELETE_REMOVED=false
BACKUP_DIR=""
LINK_DEST=""
ENABLE_COMPRESS=false
USE_CHECKSUM=false
SHOW_PROGRESS=false
LOG_FILE=""
CONFIG_FILE=""

# Statistics
TOTAL_FILES=0
TOTAL_SIZE=0
TRANSFERRED_FILES=0
TRANSFERRED_SIZE=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
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
        echo -e "[VERBOSE] $1" >&2
    fi
}

log_message() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}Sync Backup - Rsync-Based Backup and Synchronization${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -s, --source DIR        Source directory to backup
    -d, --destination DIR   Destination directory
    -r, --remote HOST       Remote host for SSH backup
    -u, --user USER         SSH username for remote backup
    -p, --port PORT         SSH port (default: 22)
    -x, --exclude PATTERN   Exclude pattern (can be used multiple times)
    -b, --bandwidth LIMIT   Bandwidth limit in KB/s
    -n, --dry-run           Show what would be synced without doing it
    -D, --delete            Delete files in dest not in source
    --backup-dir DIR        Store deleted/changed files in backup directory
    --link-dest DIR         Use hardlinks for unchanged files (incremental)
    --compress              Enable compression during transfer
    --checksum              Use checksum instead of mod-time & size
    --progress              Show detailed progress during transfer
    -l, --log FILE          Log file path
    -c, --config FILE       Use configuration file

${CYAN}Examples:${NC}
    # Local backup
    $SCRIPT_NAME -s /home/user -d /backup/home

    # Remote backup over SSH
    $SCRIPT_NAME -s /var/www -r backup.server.com -u backupuser

    # Sync with exclusions and deletion
    $SCRIPT_NAME -s /data -d /backup -x "*.tmp" -x "cache/" --delete

    # Incremental backup with archive
    $SCRIPT_NAME -s /home -d /backup/current --backup-dir /backup/archive

    # Bandwidth-limited remote backup
    $SCRIPT_NAME -s /data -r backup.host.com -b 1000 --compress

    # Hardlinked incremental backup
    $SCRIPT_NAME -s /home -d /backup/2024-11-20 --link-dest /backup/2024-11-19

${CYAN}Configuration File Format:${NC}
    SOURCE_DIR=/home/user
    DEST_DIR=/backup
    REMOTE_HOST=backup.server.com
    REMOTE_USER=backupuser
    EXCLUDE_PATTERNS=("*.tmp" "*.cache" ".git/")
    DELETE_REMOVED=true
    ENABLE_COMPRESS=true

${CYAN}Features:${NC}
    • Efficient incremental backups with rsync
    • Remote backups over SSH
    • Bandwidth limiting
    • File exclusion patterns
    • Hardlinked backups (space-efficient)
    • Archive directory for deleted files
    • Dry-run mode for testing
    • Detailed progress reporting
    • Checksum-based comparison
    • Configuration file support

${CYAN}Incremental Backup Strategy:${NC}
    Use --link-dest to create space-efficient incremental backups.
    Unchanged files are hardlinked to previous backup, using minimal space.

EOF
}

check_dependencies() {
    if ! command -v rsync &> /dev/null; then
        error_exit "rsync not found (required)" 3
    fi
    
    if [[ -n "$REMOTE_HOST" ]] && ! command -v ssh &> /dev/null; then
        error_exit "ssh not found (required for remote backups)" 3
    fi
}

load_config_file() {
    local config="$1"
    
    if [[ ! -f "$config" ]]; then
        error_exit "Configuration file not found: $config" 2
    fi
    
    verbose "Loading configuration from: $config"
    # shellcheck source=/dev/null
    source "$config"
    verbose "Configuration loaded successfully"
}

################################################################################
# Rsync Functions
################################################################################

build_rsync_options() {
    local options="-a"  # Archive mode (recursive, preserve everything)
    
    # Verbose output
    if [[ "$VERBOSE" == true ]]; then
        options="$options -v"
    fi
    
    # Progress display
    if [[ "$SHOW_PROGRESS" == true ]]; then
        options="$options --progress --stats"
    fi
    
    # Dry run
    if [[ "$DRY_RUN" == true ]]; then
        options="$options --dry-run"
    fi
    
    # Delete removed files
    if [[ "$DELETE_REMOVED" == true ]]; then
        options="$options --delete"
    fi
    
    # Compression
    if [[ "$ENABLE_COMPRESS" == true ]]; then
        options="$options --compress"
    fi
    
    # Checksum comparison
    if [[ "$USE_CHECKSUM" == true ]]; then
        options="$options --checksum"
    fi
    
    # Bandwidth limit
    if [[ -n "$BANDWIDTH_LIMIT" ]]; then
        options="$options --bwlimit=$BANDWIDTH_LIMIT"
    fi
    
    # Backup directory
    if [[ -n "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        options="$options --backup --backup-dir=$BACKUP_DIR"
    fi
    
    # Link destination (hardlinked incremental)
    if [[ -n "$LINK_DEST" ]]; then
        if [[ -d "$LINK_DEST" ]]; then
            options="$options --link-dest=$LINK_DEST"
        else
            warning "Link destination not found: $LINK_DEST"
        fi
    fi
    
    # SSH port for remote
    if [[ -n "$REMOTE_HOST" ]]; then
        options="$options -e 'ssh -p $SSH_PORT'"
    fi
    
    # Exclusions
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        options="$options --exclude=$pattern"
    done
    
    # Always exclude common temporary files
    options="$options --exclude=.DS_Store --exclude=Thumbs.db --exclude=desktop.ini"
    
    echo "$options"
}

perform_sync() {
    local source="$SOURCE_DIR"
    local dest="$DEST_DIR"
    
    # Ensure source path ends with / for proper sync
    [[ "$source" != */ ]] && source="${source}/"
    
    # Build destination path
    if [[ -n "$REMOTE_HOST" ]]; then
        if [[ -n "$REMOTE_USER" ]]; then
            dest="${REMOTE_USER}@${REMOTE_HOST}:${dest}"
        else
            dest="${REMOTE_HOST}:${dest}"
        fi
    fi
    
    info "Starting sync operation..."
    info "Source: $SOURCE_DIR"
    info "Destination: ${DEST_DIR}${REMOTE_HOST:+ (remote: $REMOTE_HOST)}"
    
    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY RUN MODE - No changes will be made"
    fi
    
    verbose "Building rsync command..."
    local rsync_opts=$(build_rsync_options)
    
    verbose "Rsync options: $rsync_opts"
    log_message "Sync started: $source -> $dest"
    
    # Execute rsync
    local start_time=$(date +%s)
    
    if eval rsync $rsync_opts "$source" "$dest" 2>&1 | tee -a "$LOG_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        success "Sync completed successfully"
        info "Duration: ${duration} seconds"
        
        log_message "Sync completed successfully in ${duration} seconds"
        
        return 0
    else
        local exit_code=$?
        error_exit "Sync failed with exit code: $exit_code" 4
    fi
}

show_sync_summary() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return
    fi
    
    info "Sync Summary:"
    
    # Extract statistics from rsync output in log
    if grep -q "Number of files:" "$LOG_FILE"; then
        local num_files=$(grep "Number of files:" "$LOG_FILE" | tail -1 | awk '{print $4}')
        local num_created=$(grep "Number of created files:" "$LOG_FILE" | tail -1 | awk '{print $5}')
        local num_deleted=$(grep "Number of deleted files:" "$LOG_FILE" | tail-1 | awk '{print $5}')
        local total_size=$(grep "Total file size:" "$LOG_FILE" | tail -1 | awk '{print $4}')
        local transferred=$(grep "Total transferred file size:" "$LOG_FILE" | tail -1 | awk '{print $5}')
        
        echo "  Files: $num_files"
        [[ -n "$num_created" ]] && echo "  Created: $num_created"
        [[ -n "$num_deleted" ]] && echo "  Deleted: $num_deleted"
        [[ -n "$total_size" ]] && echo "  Total size: $total_size"
        [[ -n "$transferred" ]] && echo "  Transferred: $transferred"
    fi
}

test_remote_connection() {
    local host="$1"
    local user="${2:-}"
    local port="${3:-22}"
    
    info "Testing remote connection to $host..."
    
    local ssh_cmd="ssh -p $port"
    [[ -n "$user" ]] && ssh_cmd="$ssh_cmd ${user}@${host}" || ssh_cmd="$ssh_cmd $host"
    
    if $ssh_cmd "echo 'Connection successful'" 2>/dev/null; then
        success "Remote connection test passed"
        return 0
    else
        warning "Remote connection test failed"
        return 1
    fi
}

estimate_sync_size() {
    info "Estimating sync size..."
    
    local source="$SOURCE_DIR"
    [[ "$source" != */ ]] && source="${source}/"
    
    local dest="$DEST_DIR"
    if [[ -n "$REMOTE_HOST" ]]; then
        if [[ -n "$REMOTE_USER" ]]; then
            dest="${REMOTE_USER}@${REMOTE_HOST}:${dest}"
        else
            dest="${REMOTE_HOST}:${dest}"
        fi
    fi
    
    local rsync_opts=$(build_rsync_options)
    rsync_opts="$rsync_opts --dry-run --stats"
    
    local stats=$(eval rsync $rsync_opts "$source" "$dest" 2>&1)
    
    echo "$stats" | grep -E "(Number of files|Total file size|Total transferred)"
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
            [[ -z "${2:-}" ]] && error_exit "--source requires a directory path" 2
            SOURCE_DIR="$2"
            shift 2
            ;;
        -d|--destination)
            [[ -z "${2:-}" ]] && error_exit "--destination requires a directory path" 2
            DEST_DIR="$2"
            shift 2
            ;;
        -r|--remote)
            [[ -z "${2:-}" ]] && error_exit "--remote requires a hostname" 2
            REMOTE_HOST="$2"
            shift 2
            ;;
        -u|--user)
            [[ -z "${2:-}" ]] && error_exit "--user requires a username" 2
            REMOTE_USER="$2"
            shift 2
            ;;
        -p|--port)
            [[ -z "${2:-}" ]] && error_exit "--port requires a port number" 2
            SSH_PORT="$2"
            shift 2
            ;;
        -x|--exclude)
            [[ -z "${2:-}" ]] && error_exit "--exclude requires a pattern" 2
            EXCLUDE_PATTERNS+=("$2")
            shift 2
            ;;
        -b|--bandwidth)
            [[ -z "${2:-}" ]] && error_exit "--bandwidth requires a limit in KB/s" 2
            BANDWIDTH_LIMIT="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -D|--delete)
            DELETE_REMOVED=true
            shift
            ;;
        --backup-dir)
            [[ -z "${2:-}" ]] && error_exit "--backup-dir requires a directory path" 2
            BACKUP_DIR="$2"
            shift 2
            ;;
        --link-dest)
            [[ -z "${2:-}" ]] && error_exit "--link-dest requires a directory path" 2
            LINK_DEST="$2"
            shift 2
            ;;
        --compress)
            ENABLE_COMPRESS=true
            shift
            ;;
        --checksum)
            USE_CHECKSUM=true
            shift
            ;;
        --progress)
            SHOW_PROGRESS=true
            shift
            ;;
        -l|--log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        -c|--config)
            [[ -z "${2:-}" ]] && error_exit "--config requires a file path" 2
            CONFIG_FILE="$2"
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

# Load configuration file if specified
if [[ -n "$CONFIG_FILE" ]]; then
    load_config_file "$CONFIG_FILE"
fi

# Validate required parameters
if [[ -z "$SOURCE_DIR" ]]; then
    error_exit "Source directory required (use -s)" 2
fi

if [[ -z "$DEST_DIR" ]]; then
    error_exit "Destination directory required (use -d)" 2
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    error_exit "Source directory does not exist: $SOURCE_DIR" 2
fi

check_dependencies

# Test remote connection if applicable
if [[ -n "$REMOTE_HOST" ]]; then
    if ! test_remote_connection "$REMOTE_HOST" "$REMOTE_USER" "$SSH_PORT"; then
        error_exit "Cannot connect to remote host: $REMOTE_HOST" 4
    fi
fi

verbose "Configuration:"
verbose "  Source: $SOURCE_DIR"
verbose "  Destination: $DEST_DIR"
verbose "  Remote Host: ${REMOTE_HOST:-none}"
verbose "  Bandwidth Limit: ${BANDWIDTH_LIMIT:-unlimited}"
verbose "  Compression: $ENABLE_COMPRESS"
verbose "  Delete Removed: $DELETE_REMOVED"
verbose "  Dry Run: $DRY_RUN"

# Estimate size if verbose
if [[ "$VERBOSE" == true ]] && [[ "$DRY_RUN" == false ]]; then
    estimate_sync_size
fi

# Perform sync
perform_sync

# Show summary if not dry run
if [[ "$DRY_RUN" == false ]] && [[ -n "$LOG_FILE" ]]; then
    show_sync_summary
fi

success "Sync backup operation completed successfully!"
log_message "Sync backup completed successfully"

