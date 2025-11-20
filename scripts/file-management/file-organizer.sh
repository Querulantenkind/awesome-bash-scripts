#!/bin/bash

################################################################################
# Script Name: file-organizer.sh
# Description: Intelligent file organization tool that sorts files by type,
#              date, size, or custom rules. Supports dry-run mode, undo
#              functionality, and custom organization schemes.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./file-organizer.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --source DIR        Source directory to organize
#   -d, --destination DIR   Destination directory for organized files
#   -o, --organize-by TYPE  Organization type (type|date|size|extension)
#   -p, --pattern PATTERN   File pattern to match (e.g., "*.jpg")
#   -m, --move              Move files instead of copy
#   -n, --dry-run           Show what would be done without doing it
#   -r, --recursive         Process subdirectories recursively
#   --min-size SIZE         Minimum file size (e.g., 1M, 100K)
#   --max-size SIZE         Maximum file size
#   --older-than DAYS       Only process files older than N days
#   --newer-than DAYS       Only process files newer than N days
#   --create-index          Create an index file of operations
#   --undo FILE             Undo operations from index file
#   -l, --log FILE          Log file path
#
# Examples:
#   ./file-organizer.sh -s ~/Downloads -o type
#   ./file-organizer.sh -s ~/Pictures -o date -m
#   ./file-organizer.sh -s ~/Documents -o extension -r
#   ./file-organizer.sh -s . -o size --min-size 10M
#   ./file-organizer.sh --undo /path/to/index.txt
#
# Dependencies:
#   - Standard GNU utilities
#   - file (for MIME type detection)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
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
ORGANIZE_BY="type"
FILE_PATTERN="*"
MOVE_FILES=false
DRY_RUN=false
RECURSIVE=false
MIN_SIZE=""
MAX_SIZE=""
OLDER_THAN=""
NEWER_THAN=""
CREATE_INDEX=false
UNDO_FILE=""
LOG_FILE=""

# Statistics
FILES_PROCESSED=0
FILES_MOVED=0
FILES_COPIED=0
DIRS_CREATED=0

# Index file for undo
INDEX_FILE=""

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
    cat << 'EOF'
File Organizer - Intelligent File Organization Tool

Usage:
    file-organizer.sh [OPTIONS]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -s, --source DIR        Source directory to organize
    -d, --destination DIR   Destination directory (default: source_organized)
    -o, --organize-by TYPE  Organization type:
                              type       - By file type (documents, images, etc.)
                              date       - By modification date (YYYY/MM)
                              size       - By file size ranges
                              extension  - By file extension
    -p, --pattern PATTERN   File pattern to match (e.g., "*.jpg", "*.pdf")
    -m, --move              Move files instead of copy
    -n, --dry-run           Show what would be done without doing it
    -r, --recursive         Process subdirectories recursively
    --min-size SIZE         Minimum file size (e.g., 1M, 100K, 1G)
    --max-size SIZE         Maximum file size
    --older-than DAYS       Only process files older than N days
    --newer-than DAYS       Only process files newer than N days
    --create-index          Create index file for undo capability
    --undo FILE             Undo operations from index file
    -l, --log FILE          Log file path

Examples:
    # Organize Downloads by file type
    file-organizer.sh -s ~/Downloads -o type

    # Organize Pictures by date (move, not copy)
    file-organizer.sh -s ~/Pictures -o date -m

    # Organize recursively by extension
    file-organizer.sh -s ~/Documents -o extension -r

    # Organize large files only
    file-organizer.sh -s . -o size --min-size 10M

    # Organize old files by type
    file-organizer.sh -s ~/Downloads -o type --older-than 30

    # Dry run to preview changes
    file-organizer.sh -s ~/Downloads -o type --dry-run

    # Organize with undo capability
    file-organizer.sh -s ~/Downloads -o type --create-index

    # Undo previous organization
    file-organizer.sh --undo /path/to/index.txt

Organization Types:
    type       Groups: documents, images, videos, audio, archives, code, other
    date       Format: YYYY/MM/filename
    size       Ranges: tiny(<1MB), small(1-10MB), medium(10-100MB), large(>100MB)
    extension  Groups: .jpg, .pdf, .txt, etc.

EOF
}

################################################################################
# File Type Detection Functions
################################################################################

get_file_category() {
    local file="$1"
    local mime_type=""
    
    if command -v file &> /dev/null; then
        mime_type=$(file --mime-type -b "$file" 2>/dev/null)
    fi
    
    local extension="${file##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    
    # Categorize by MIME type first
    case "$mime_type" in
        image/*)
            echo "images"
            ;;
        video/*)
            echo "videos"
            ;;
        audio/*)
            echo "audio"
            ;;
        application/pdf|application/*document*)
            echo "documents"
            ;;
        application/*zip*|application/*tar*|application/*compressed*|application/*archive*)
            echo "archives"
            ;;
        text/*)
            echo "documents"
            ;;
        *)
            # Fall back to extension
            case "$extension" in
                jpg|jpeg|png|gif|bmp|svg|webp|ico)
                    echo "images"
                    ;;
                mp4|avi|mkv|mov|wmv|flv|webm|m4v)
                    echo "videos"
                    ;;
                mp3|wav|flac|aac|ogg|wma|m4a)
                    echo "audio"
                    ;;
                pdf|doc|docx|odt|txt|rtf|tex|md)
                    echo "documents"
                    ;;
                xls|xlsx|ods|csv)
                    echo "spreadsheets"
                    ;;
                ppt|pptx|odp)
                    echo "presentations"
                    ;;
                zip|tar|gz|bz2|xz|7z|rar)
                    echo "archives"
                    ;;
                sh|bash|py|java|c|cpp|h|js|ts|go|rs|php|rb|pl)
                    echo "code"
                    ;;
                exe|msi|deb|rpm|dmg|app)
                    echo "executables"
                    ;;
                *)
                    echo "other"
                    ;;
            esac
            ;;
    esac
}

get_file_date_path() {
    local file="$1"
    local timestamp=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
    local year=$(date -d "@$timestamp" '+%Y' 2>/dev/null || date -r "$timestamp" '+%Y' 2>/dev/null)
    local month=$(date -d "@$timestamp" '+%m' 2>/dev/null || date -r "$timestamp" '+%m' 2>/dev/null)
    
    echo "${year}/${month}"
}

get_file_size_category() {
    local file="$1"
    local size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
    
    # Size in bytes
    if (( size < 1048576 )); then
        echo "tiny"  # < 1MB
    elif (( size < 10485760 )); then
        echo "small"  # 1-10MB
    elif (( size < 104857600 )); then
        echo "medium"  # 10-100MB
    else
        echo "large"  # > 100MB
    fi
}

get_file_extension() {
    local file="$1"
    local basename=$(basename "$file")
    
    if [[ "$basename" == *.* ]]; then
        local ext="${basename##*.}"
        echo $(echo "$ext" | tr '[:upper:]' '[:lower:]')
    else
        echo "no-extension"
    fi
}

################################################################################
# Filter Functions
################################################################################

parse_size() {
    local size_str="$1"
    local multiplier=1
    
    if [[ "$size_str" =~ ([0-9]+)([KMG])$ ]]; then
        local number="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        case "$unit" in
            K) multiplier=1024 ;;
            M) multiplier=1048576 ;;
            G) multiplier=1073741824 ;;
        esac
        
        echo $((number * multiplier))
    else
        echo "$size_str"
    fi
}

should_process_file() {
    local file="$1"
    
    # Check if regular file
    [[ ! -f "$file" ]] && return 1
    
    # Check pattern
    if [[ "$FILE_PATTERN" != "*" ]]; then
        [[ ! "$file" == $FILE_PATTERN ]] && return 1
    fi
    
    # Check size constraints
    if [[ -n "$MIN_SIZE" ]]; then
        local file_size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
        local min_bytes=$(parse_size "$MIN_SIZE")
        (( file_size < min_bytes )) && return 1
    fi
    
    if [[ -n "$MAX_SIZE" ]]; then
        local file_size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
        local max_bytes=$(parse_size "$MAX_SIZE")
        (( file_size > max_bytes )) && return 1
    fi
    
    # Check age constraints
    if [[ -n "$OLDER_THAN" ]]; then
        local age_seconds=$((OLDER_THAN * 86400))
        local current_time=$(date +%s)
        local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
        local file_age=$((current_time - file_time))
        (( file_age < age_seconds )) && return 1
    fi
    
    if [[ -n "$NEWER_THAN" ]]; then
        local age_seconds=$((NEWER_THAN * 86400))
        local current_time=$(date +%s)
        local file_time=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
        local file_age=$((current_time - file_time))
        (( file_age > age_seconds )) && return 1
    fi
    
    return 0
}

################################################################################
# Organization Functions
################################################################################

get_destination_path() {
    local file="$1"
    local dest_base="$DEST_DIR"
    local subdir=""
    
    case "$ORGANIZE_BY" in
        type)
            subdir=$(get_file_category "$file")
            ;;
        date)
            subdir=$(get_file_date_path "$file")
            ;;
        size)
            subdir=$(get_file_size_category "$file")
            ;;
        extension)
            subdir=$(get_file_extension "$file")
            ;;
        *)
            subdir="other"
            ;;
    esac
    
    echo "${dest_base}/${subdir}"
}

organize_file() {
    local file="$1"
    local dest_dir=$(get_destination_path "$file")
    local filename=$(basename "$file")
    local dest_file="${dest_dir}/${filename}"
    
    ((FILES_PROCESSED++))
    
    # Handle duplicate filenames
    if [[ -f "$dest_file" ]]; then
        local base="${filename%.*}"
        local ext="${filename##*.}"
        local counter=1
        
        if [[ "$base" == "$ext" ]]; then
            # No extension
            while [[ -f "${dest_dir}/${filename}_${counter}" ]]; do
                ((counter++))
            done
            dest_file="${dest_dir}/${filename}_${counter}"
        else
            while [[ -f "${dest_dir}/${base}_${counter}.${ext}" ]]; do
                ((counter++))
            done
            dest_file="${dest_dir}/${base}_${counter}.${ext}"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] $(basename "$file") → $(basename "$dest_dir")"
        return 0
    fi
    
    # Create destination directory
    if [[ ! -d "$dest_dir" ]]; then
        mkdir -p "$dest_dir"
        ((DIRS_CREATED++))
        verbose "Created directory: $dest_dir"
    fi
    
    # Move or copy file
    if [[ "$MOVE_FILES" == true ]]; then
        if mv "$file" "$dest_file"; then
            ((FILES_MOVED++))
            verbose "Moved: $file → $dest_file"
            
            # Log to index file if enabled
            if [[ "$CREATE_INDEX" == true ]]; then
                echo "MOVE|$dest_file|$file" >> "$INDEX_FILE"
            fi
            
            log_message "Moved: $file → $dest_file"
        fi
    else
        if cp "$file" "$dest_file"; then
            ((FILES_COPIED++))
            verbose "Copied: $file → $dest_file"
            
            if [[ "$CREATE_INDEX" == true ]]; then
                echo "COPY|$dest_file|$file" >> "$INDEX_FILE"
            fi
            
            log_message "Copied: $file → $dest_file"
        fi
    fi
}

process_directory() {
    local dir="$1"
    
    info "Processing directory: $dir"
    
    if [[ "$RECURSIVE" == true ]]; then
        while IFS= read -r -d '' file; do
            if should_process_file "$file"; then
                organize_file "$file"
            fi
        done < <(find "$dir" -type f -print0)
    else
        for file in "$dir"/*; do
            [[ ! -f "$file" ]] && continue
            if should_process_file "$file"; then
                organize_file "$file"
            fi
        done
    fi
}

undo_organization() {
    local index_file="$1"
    
    if [[ ! -f "$index_file" ]]; then
        error_exit "Index file not found: $index_file" 2
    fi
    
    info "Undoing operations from: $index_file"
    
    local count=0
    while IFS='|' read -r operation dest_file source_file; do
        case "$operation" in
            MOVE)
                if [[ -f "$dest_file" ]]; then
                    if mv "$dest_file" "$source_file"; then
                        ((count++))
                        verbose "Restored: $dest_file → $source_file"
                    fi
                fi
                ;;
            COPY)
                if [[ -f "$dest_file" ]]; then
                    if rm "$dest_file"; then
                        ((count++))
                        verbose "Removed copy: $dest_file"
                    fi
                fi
                ;;
        esac
    done < "$index_file"
    
    success "Undo completed: $count operations reversed"
}

show_summary() {
    echo ""
    info "Organization Summary:"
    echo "  Files processed: $FILES_PROCESSED"
    
    if [[ "$MOVE_FILES" == true ]]; then
        echo "  Files moved: $FILES_MOVED"
    else
        echo "  Files copied: $FILES_COPIED"
    fi
    
    echo "  Directories created: $DIRS_CREATED"
    
    if [[ "$CREATE_INDEX" == true ]] && [[ -n "$INDEX_FILE" ]]; then
        echo "  Index file: $INDEX_FILE"
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
        -o|--organize-by)
            [[ -z "${2:-}" ]] && error_exit "--organize-by requires a type" 2
            ORGANIZE_BY="$2"
            shift 2
            ;;
        -p|--pattern)
            [[ -z "${2:-}" ]] && error_exit "--pattern requires a pattern" 2
            FILE_PATTERN="$2"
            shift 2
            ;;
        -m|--move)
            MOVE_FILES=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        --min-size)
            [[ -z "${2:-}" ]] && error_exit "--min-size requires a size" 2
            MIN_SIZE="$2"
            shift 2
            ;;
        --max-size)
            [[ -z "${2:-}" ]] && error_exit "--max-size requires a size" 2
            MAX_SIZE="$2"
            shift 2
            ;;
        --older-than)
            [[ -z "${2:-}" ]] && error_exit "--older-than requires days" 2
            OLDER_THAN="$2"
            shift 2
            ;;
        --newer-than)
            [[ -z "${2:-}" ]] && error_exit "--newer-than requires days" 2
            NEWER_THAN="$2"
            shift 2
            ;;
        --create-index)
            CREATE_INDEX=true
            shift
            ;;
        --undo)
            [[ -z "${2:-}" ]] && error_exit "--undo requires a file path" 2
            UNDO_FILE="$2"
            shift 2
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

# Handle undo mode
if [[ -n "$UNDO_FILE" ]]; then
    undo_organization "$UNDO_FILE"
    exit 0
fi

# Validate required parameters
if [[ -z "$SOURCE_DIR" ]]; then
    error_exit "Source directory required (use -s)" 2
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
    error_exit "Source directory does not exist: $SOURCE_DIR" 2
fi

# Set default destination if not specified
if [[ -z "$DEST_DIR" ]]; then
    DEST_DIR="${SOURCE_DIR}_organized"
fi

# Create index file if requested
if [[ "$CREATE_INDEX" == true ]]; then
    INDEX_FILE="${DEST_DIR}/organization_index_$(date '+%Y%m%d_%H%M%S').txt"
    mkdir -p "$(dirname "$INDEX_FILE")"
    touch "$INDEX_FILE"
fi

info "File Organization Tool"
info "Source: $SOURCE_DIR"
info "Destination: $DEST_DIR"
info "Organize by: $ORGANIZE_BY"
info "Action: $([ "$MOVE_FILES" == true ] && echo "Move" || echo "Copy")"

if [[ "$DRY_RUN" == true ]]; then
    warning "DRY RUN MODE - No changes will be made"
fi

log_message "Organization started: $SOURCE_DIR → $DEST_DIR (by $ORGANIZE_BY)"

# Process files
process_directory "$SOURCE_DIR"

# Show summary
show_summary

success "Organization completed successfully!"
log_message "Organization completed: $FILES_PROCESSED files processed"

