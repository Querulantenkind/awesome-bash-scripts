#!/bin/bash

################################################################################
# Script Name: bulk-renamer.sh
# Description: Powerful bulk file renaming tool with pattern matching, regex
#              support, case conversion, sequential numbering, and undo capability.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.1
#
# Usage: ./bulk-renamer.sh [options] [files...]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -p, --pattern PATTERN   File pattern to match (e.g., "*.jpg")
#   -f, --find TEXT         Text to find in filenames
#   -r, --replace TEXT      Text to replace with
#   -x, --regex PATTERN     Use regex for find/replace
#   -l, --lowercase         Convert to lowercase
#   -u, --uppercase         Convert to uppercase
#   -t, --titlecase         Convert to title case
#   -s, --seq-start NUM     Sequential numbering start
#   -w, --seq-width NUM     Sequential number width (padding)
#   --prefix TEXT           Add prefix to filenames
#   --suffix TEXT           Add suffix to filenames
#   --remove-spaces         Replace spaces with underscores
#   --dry-run               Preview changes without renaming
#   --undo FILE             Undo from index file
#   -i, --interactive       Ask before each rename
#   -d, --directory DIR     Target directory
#   -R, --recursive         Process subdirectories
#
# Examples:
#   ./bulk-renamer.sh -p "*.txt" -f "old" -r "new"
#   ./bulk-renamer.sh -p "*.jpg" -s 1 -w 3 --prefix "photo_"
#   ./bulk-renamer.sh -p "*" -l --remove-spaces
#   ./bulk-renamer.sh -x "([0-9]+)" -r "num_\1" *.log
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
PATTERN=""
FIND_TEXT=""
REPLACE_TEXT=""
USE_REGEX=false
LOWERCASE=false
UPPERCASE=false
TITLECASE=false
SEQ_START=0
SEQ_WIDTH=0
PREFIX=""
SUFFIX=""
REMOVE_SPACES=false
DRY_RUN=false
UNDO_FILE=""
INTERACTIVE=false
TARGET_DIR="."
RECURSIVE=false
FILES=()

# Statistics
FILES_RENAMED=0
INDEX_FILE="rename_index_$(date +%Y%m%d_%H%M%S').txt"

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1"; }

show_usage() {
    cat << 'EOF'
Bulk Renamer - Advanced Batch File Renaming Tool

Usage: bulk-renamer.sh [OPTIONS] [FILES...]

Options:
    -h, --help              Show this help message
    -p, --pattern PATTERN   File pattern (e.g., "*.jpg", "IMG_*")
    -f, --find TEXT         Find this text in filenames
    -r, --replace TEXT      Replace with this text
    -x, --regex PATTERN     Use regex for find/replace
    -l, --lowercase         Convert to lowercase
    -u, --uppercase         Convert to UPPERCASE
    -t, --titlecase         Convert To Title Case
    -s, --seq-start NUM     Start sequential numbering
    -w, --seq-width NUM     Number width with zero padding
    --prefix TEXT           Add prefix to filenames
    --suffix TEXT           Add suffix (before extension)
    --remove-spaces         Replace spaces with underscores
    --dry-run               Preview without renaming
    --undo FILE             Undo using index file
    -i, --interactive       Confirm each rename
    -d, --directory DIR     Target directory
    -R, --recursive         Process subdirectories

Examples:
    # Replace text in JPG files
    bulk-renamer.sh -p "*.jpg" -f "IMG" -r "Photo"

    # Sequential numbering with padding
    bulk-renamer.sh -p "*.mp3" -s 1 -w 3 --prefix "track_"

    # Lowercase and remove spaces
    bulk-renamer.sh -p "*" -l --remove-spaces

    # Regex replacement
    bulk-renamer.sh -x "([0-9]{4})" -r "year_\1" *.txt

EOF
}

transform_filename() {
    local filename="$1"
    local seq_num="${2:-0}"
    local basename="${filename%.*}"
    local extension="${filename##*.}"
    [[ "$basename" == "$extension" ]] && extension=""
    
    # Find/replace
    if [[ -n "$FIND_TEXT" ]]; then
        if [[ "$USE_REGEX" == true ]]; then
            basename=$(echo "$basename" | sed -E "s/$FIND_TEXT/$REPLACE_TEXT/g")
        else
            basename="${basename//$FIND_TEXT/$REPLACE_TEXT}"
        fi
    fi
    
    # Case conversion
    [[ "$LOWERCASE" == true ]] && basename=$(echo "$basename" | tr '[:upper:]' '[:lower:]')
    [[ "$UPPERCASE" == true ]] && basename=$(echo "$basename" | tr '[:lower:]' '[:upper:]')
    if [[ "$TITLECASE" == true ]]; then
        basename=$(echo "$basename" | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')
    fi
    
    # Remove spaces
    [[ "$REMOVE_SPACES" == true ]] && basename="${basename// /_}"
    
    # Sequential numbering
    if (( SEQ_WIDTH > 0 )); then
        local num=$(printf "%0${SEQ_WIDTH}d" "$seq_num")
        basename="${basename}_${num}"
    fi
    
    # Prefix/suffix
    basename="${PREFIX}${basename}${SUFFIX}"
    
    # Reconstruct
    [[ -n "$extension" ]] && echo "${basename}.${extension}" || echo "$basename"
}

rename_file() {
    local old_path="$1"
    local new_name="$2"
    local dir=$(dirname "$old_path")
    local new_path="${dir}/${new_name}"
    
    if [[ "$old_path" == "$new_path" ]]; then
        verbose "Unchanged: $(basename "$old_path")"
        return 0
    fi
    
    if [[ -e "$new_path" ]]; then
        echo -e "${YELLOW}⚠ Target exists: $new_path${NC}"
        return 1
    fi
    
    echo -e "  ${CYAN}$(basename "$old_path")${NC} → ${GREEN}$new_name${NC}"
    
    if [[ "$INTERACTIVE" == true ]]; then
        read -p "Rename? (y/N): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        if mv "$old_path" "$new_path"; then
            ((FILES_RENAMED++))
            echo "$new_path|$old_path" >> "$INDEX_FILE"
        fi
    fi
}

process_files() {
    local file_list=("$@")
    local seq=$SEQ_START
    
    for file in "${file_list[@]}"; do
        [[ ! -f "$file" ]] && continue
        
        local filename=$(basename "$file")
        local new_name=$(transform_filename "$filename" "$seq")
        
        rename_file "$file" "$new_name"
        ((seq++))
    done
}

undo_renames() {
    [[ ! -f "$UNDO_FILE" ]] && error_exit "Index file not found: $UNDO_FILE" 2
    
    info "Undoing renames from: $UNDO_FILE"
    local count=0
    
    while IFS='|' read -r new_path old_path; do
        if [[ -f "$new_path" ]]; then
            if mv "$new_path" "$old_path"; then
                ((count++))
                verbose "Restored: $new_path → $old_path"
            fi
        fi
    done < "$UNDO_FILE"
    
    success "Undo completed: $count files restored"
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -p|--pattern) PATTERN="$2"; shift 2 ;;
        -f|--find) FIND_TEXT="$2"; shift 2 ;;
        -r|--replace) REPLACE_TEXT="$2"; shift 2 ;;
        -x|--regex) USE_REGEX=true; FIND_TEXT="$2"; shift 2 ;;
        -l|--lowercase) LOWERCASE=true; shift ;;
        -u|--uppercase) UPPERCASE=true; shift ;;
        -t|--titlecase) TITLECASE=true; shift ;;
        -s|--seq-start) SEQ_START="$2"; shift 2 ;;
        -w|--seq-width) SEQ_WIDTH="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --suffix) SUFFIX="$2"; shift 2 ;;
        --remove-spaces) REMOVE_SPACES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --undo) UNDO_FILE="$2"; shift 2 ;;
        -i|--interactive) INTERACTIVE=true; shift ;;
        -d|--directory) TARGET_DIR="$2"; shift 2 ;;
        -R|--recursive) RECURSIVE=true; shift ;;
        -*) error_exit "Unknown option: $1" 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

# Main execution
[[ -n "$UNDO_FILE" ]] && { undo_renames; exit 0; }

[[ ! -d "$TARGET_DIR" ]] && error_exit "Directory not found: $TARGET_DIR" 2

# Collect files
if [[ ${#FILES[@]} -eq 0 ]]; then
    if [[ -n "$PATTERN" ]]; then
        if [[ "$RECURSIVE" == true ]]; then
            mapfile -t FILES < <(find "$TARGET_DIR" -type f -name "$PATTERN")
        else
            mapfile -t FILES < <(find "$TARGET_DIR" -maxdepth 1 -type f -name "$PATTERN")
        fi
    else
        error_exit "No files specified. Use -p for pattern or provide file names" 2
    fi
fi

[[ ${#FILES[@]} -eq 0 ]] && error_exit "No files found matching criteria" 2

info "Processing ${#FILES[@]} files..."
[[ "$DRY_RUN" == true ]] && info "DRY RUN MODE"

process_files "${FILES[@]}"

echo ""
success "Renamed $FILES_RENAMED files"
[[ "$DRY_RUN" == false ]] && info "Index file: $INDEX_FILE"

