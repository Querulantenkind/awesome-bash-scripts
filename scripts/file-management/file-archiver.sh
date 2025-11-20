#!/bin/bash

################################################################################
# Script Name: file-archiver.sh
# Description: Intelligent file archiving tool that archives old files by age,
#              access time, or custom tags. Features compression, dry-run mode,
#              and restoration capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./file-archiver.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --source DIR        Source directory to archive from
#   -d, --archive-dir DIR   Archive destination directory
#   -a, --age DAYS          Archive files older than N days (default: 90)
#   --atime DAYS            Archive by access time instead of modify time
#   -p, --pattern PATTERN   File pattern to archive (e.g., *.log)
#   -t, --tag TAG           Tag-based archiving
#   -c, --compress          Compress archived files
#   -m, --method METHOD     Compression method (gzip|bzip2|xz, default: gzip)
#   --restore FILE          Restore file from archive
#   --dry-run               Show what would be archived without doing it
#   --delete                Delete original files after archiving
#   -j, --json              Output in JSON format
#   -l, --log FILE          Log file path
#   --no-color              Disable colored output
#
# Examples:
#   ./file-archiver.sh --source /var/log --age 30 --pattern "*.log"
#   ./file-archiver.sh --source /data --age 90 --compress --delete
#   ./file-archiver.sh --dry-run --source /tmp --age 7
#   ./file-archiver.sh --restore /archive/2024/file.txt.gz
#   ./file-archiver.sh --source /docs --tag "old-projects" --compress
#
# Dependencies:
#   - find
#   - gzip/bzip2/xz (optional, for compression)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
SOURCE_DIR=""
ARCHIVE_DIR=""
AGE_DAYS=90
USE_ATIME=false
FILE_PATTERN="*"
TAG=""
COMPRESS=false
COMPRESS_METHOD="gzip"
RESTORE_FILE=""
DRY_RUN=false
DELETE_AFTER=false
JSON_OUTPUT=false
LOG_FILE=""
USE_COLOR=true

# Statistics
ARCHIVED_COUNT=0
ARCHIVED_SIZE=0

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"
}

warning() {
    [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"
}

info() {
    [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"
}

verbose() {
    [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2
}

log_message() {
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

show_usage() {
    cat << EOF
${WHITE}File Archiver - Intelligent File Archiving Tool${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -s, --source DIR        Source directory to archive from
    -d, --archive-dir DIR   Archive destination directory
    -a, --age DAYS          Archive files older than N days (default: 90)
    --atime DAYS            Use access time instead of modify time
    -p, --pattern PATTERN   File pattern to archive (e.g., *.log)
    -t, --tag TAG           Tag for archived files
    -c, --compress          Compress archived files
    -m, --method METHOD     Compression method (gzip|bzip2|xz)
    --restore FILE          Restore file from archive
    --dry-run               Preview without executing
    --delete                Delete original files after archiving
    -j, --json              Output in JSON format
    -l, --log FILE          Log file path
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Archive old log files
    $SCRIPT_NAME --source /var/log --age 30 --pattern "*.log" --compress

    # Dry run to see what would be archived
    $SCRIPT_NAME --dry-run --source /tmp --age 7

    # Archive and delete old files
    $SCRIPT_NAME --source /data --age 90 --compress --delete

    # Restore archived file
    $SCRIPT_NAME --restore /archive/2024/file.txt.gz

    # Tag-based archiving
    $SCRIPT_NAME --source /docs --tag "old-projects" --compress

${CYAN}Features:${NC}
    • Age-based archiving
    • Access time archiving
    • Pattern matching
    • Compression support
    • Dry-run mode
    • File restoration
    • Tag support
    • JSON output

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in find; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    [[ ${#missing_deps[@]} -gt 0 ]] && error_exit "Missing dependencies: ${missing_deps[*]}" 3

    if [[ "$COMPRESS" == true ]]; then
        case "$COMPRESS_METHOD" in
            gzip) command -v gzip &> /dev/null || error_exit "gzip not found" 3 ;;
            bzip2) command -v bzip2 &> /dev/null || error_exit "bzip2 not found" 3 ;;
            xz) command -v xz &> /dev/null || error_exit "xz not found" 3 ;;
        esac
    fi
}

get_compress_extension() {
    case "$COMPRESS_METHOD" in
        gzip) echo ".gz" ;;
        bzip2) echo ".bz2" ;;
        xz) echo ".xz" ;;
        *) echo "" ;;
    esac
}

compress_file() {
    local file="$1"
    local output="$2"

    case "$COMPRESS_METHOD" in
        gzip) gzip -c "$file" > "$output" ;;
        bzip2) bzip2 -c "$file" > "$output" ;;
        xz) xz -c "$file" > "$output" ;;
    esac
}

decompress_file() {
    local file="$1"
    local output="$2"

    case "$file" in
        *.gz) gzip -dc "$file" > "$output" ;;
        *.bz2) bzip2 -dc "$file" > "$output" ;;
        *.xz) xz -dc "$file" > "$output" ;;
        *) cp "$file" "$output" ;;
    esac
}

archive_file() {
    local file="$1"
    local relative_path="${file#$SOURCE_DIR/}"
    local archive_path="$ARCHIVE_DIR/$(date +%Y)/$(date +%m)/$relative_path"

    if [[ "$COMPRESS" == true ]]; then
        archive_path="${archive_path}$(get_compress_extension)"
    fi

    mkdir -p "$(dirname "$archive_path")"

    if [[ "$DRY_RUN" == true ]]; then
        echo "Would archive: $file -> $archive_path"
        return 0
    fi

    if [[ "$COMPRESS" == true ]]; then
        if compress_file "$file" "$archive_path"; then
            verbose "Compressed and archived: $file"
        else
            warning "Failed to compress: $file"
            return 1
        fi
    else
        if cp -p "$file" "$archive_path"; then
            verbose "Archived: $file"
        else
            warning "Failed to archive: $file"
            return 1
        fi
    fi

    if [[ "$DELETE_AFTER" == true ]]; then
        rm -f "$file"
        verbose "Deleted original: $file"
    fi

    ((ARCHIVED_COUNT++))
    ARCHIVED_SIZE=$((ARCHIVED_SIZE + $(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)))

    log_message "Archived: $file -> $archive_path"
    return 0
}

find_files_to_archive() {
    local find_opts="-type f -name $FILE_PATTERN"

    if [[ "$USE_ATIME" == true ]]; then
        find_opts="$find_opts -atime +$AGE_DAYS"
    else
        find_opts="$find_opts -mtime +$AGE_DAYS"
    fi

    find "$SOURCE_DIR" $find_opts 2>/dev/null
}

run_archiving() {
    info "Starting archiving process..."
    verbose "Source: $SOURCE_DIR"
    verbose "Archive: $ARCHIVE_DIR"
    verbose "Age: $AGE_DAYS days"
    verbose "Pattern: $FILE_PATTERN"

    local files=$(find_files_to_archive)

    if [[ -z "$files" ]]; then
        info "No files found matching criteria"
        return 0
    fi

    local total=$(echo "$files" | wc -l)
    info "Found $total files to archive"

    while IFS= read -r file; do
        archive_file "$file"
    done <<< "$files"

    if [[ "$DRY_RUN" != true ]]; then
        success "Archived $ARCHIVED_COUNT files"
        info "Total size: $(numfmt --to=iec $ARCHIVED_SIZE 2>/dev/null || echo $ARCHIVED_SIZE bytes)"
    fi
}

restore_from_archive() {
    local archived_file="$1"
    local restore_dir="${2:-.}"

    if [[ ! -f "$archived_file" ]]; then
        error_exit "Archived file not found: $archived_file" 2
    fi

    local filename=$(basename "$archived_file")
    filename="${filename%.gz}"
    filename="${filename%.bz2}"
    filename="${filename%.xz}"

    local output="$restore_dir/$filename"

    info "Restoring: $archived_file"
    info "To: $output"

    mkdir -p "$(dirname "$output")"

    if decompress_file "$archived_file" "$output"; then
        success "File restored successfully"
        log_message "Restored: $archived_file -> $output"
    else
        error_exit "Failed to restore file" 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -s|--source) SOURCE_DIR="$2"; shift 2 ;;
        -d|--archive-dir) ARCHIVE_DIR="$2"; shift 2 ;;
        -a|--age) AGE_DAYS="$2"; shift 2 ;;
        --atime) USE_ATIME=true; AGE_DAYS="${2:-$AGE_DAYS}"; shift; shift ;;
        -p|--pattern) FILE_PATTERN="$2"; shift 2 ;;
        -t|--tag) TAG="$2"; shift 2 ;;
        -c|--compress) COMPRESS=true; shift ;;
        -m|--method) COMPRESS_METHOD="$2"; shift 2 ;;
        --restore) RESTORE_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --delete) DELETE_AFTER=true; shift ;;
        -j|--json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        -l|--log) LOG_FILE="$2"; shift 2 ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_dependencies

if [[ -n "$RESTORE_FILE" ]]; then
    restore_from_archive "$RESTORE_FILE"
else
    [[ -z "$SOURCE_DIR" ]] && error_exit "Source directory required (use -s)" 2
    [[ -z "$ARCHIVE_DIR" ]] && ARCHIVE_DIR="${SOURCE_DIR}/.archive"
    [[ ! -d "$SOURCE_DIR" ]] && error_exit "Source directory not found: $SOURCE_DIR" 2

    mkdir -p "$ARCHIVE_DIR"
    run_archiving
fi

log_message "File archiver completed"
