#!/bin/bash

################################################################################
# Script Name: duplicate-finder.sh
# Description: Find and optionally remove duplicate files based on content
#              (MD5/SHA256 checksums). Supports interactive mode, automatic
#              deletion, and various selection strategies.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.1
#
# Usage: ./duplicate-finder.sh [options] [directory]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -r, --recursive         Search recursively
#   -d, --delete            Automatically delete duplicates
#   -i, --interactive       Interactive deletion mode
#   -k, --keep STRATEGY     Keep strategy (newest|oldest|smallest|largest|first)
#   -m, --min-size SIZE     Minimum file size to check
#   -a, --algorithm ALGO    Hash algorithm (md5|sha256, default: md5)
#   -o, --output FILE       Save results to file
#   --dry-run               Show what would be deleted
#   -l, --log FILE          Log file path
#
# Examples:
#   ./duplicate-finder.sh ~/Downloads
#   ./duplicate-finder.sh -r ~/Pictures --dry-run
#   ./duplicate-finder.sh -d -k newest ~/Documents
#   ./duplicate-finder.sh -i -m 1M ~/Videos
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

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
RECURSIVE=false
DELETE_DUPLICATES=false
INTERACTIVE=false
KEEP_STRATEGY="first"
MIN_SIZE="1K"
HASH_ALGO="md5"
OUTPUT_FILE=""
DRY_RUN=false
LOG_FILE=""
SEARCH_DIR="."

# Statistics
TOTAL_FILES=0
DUPLICATE_SETS=0
DUPLICATE_FILES=0
SPACE_SAVED=0
FILES_DELETED=0

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() { echo -e "${GREEN}✓ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2; }

show_usage() {
    cat << EOF
${WHITE}Duplicate Finder - Find and Remove Duplicate Files${NC}

${CYAN}Usage:${NC} $SCRIPT_NAME [OPTIONS] [DIRECTORY]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -r, --recursive         Search recursively in subdirectories
    -d, --delete            Automatically delete duplicates
    -i, --interactive       Interactive deletion mode
    -k, --keep STRATEGY     Which file to keep (newest|oldest|smallest|largest|first)
    -m, --min-size SIZE     Minimum file size to check (default: 1K)
    -a, --algorithm ALGO    Hash algorithm: md5 (fast) or sha256 (secure)
    -o, --output FILE       Save duplicate list to file
    --dry-run               Show what would be deleted without doing it
    -l, --log FILE          Log file path

${CYAN}Examples:${NC}
    # Find duplicates in Downloads
    $SCRIPT_NAME ~/Downloads

    # Find and show what would be deleted
    $SCRIPT_NAME -r ~/Pictures --dry-run

    # Delete duplicates automatically, keep newest
    $SCRIPT_NAME -d -k newest ~/Documents

    # Interactive mode for large files
    $SCRIPT_NAME -i -r -m 10M ~/Videos

    # Use SHA256 for critical files
    $SCRIPT_NAME -a sha256 ~/Important

${CYAN}Keep Strategies:${NC}
    newest    Keep the most recently modified file
    oldest    Keep the oldest file
    smallest  Keep the smallest file (same content)
    largest   Keep the largest file
    first     Keep the first file found (fastest)

EOF
}

calculate_hash() {
    local file="$1"
    if [[ "$HASH_ALGO" == "sha256" ]]; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    else
        md5sum "$file" 2>/dev/null | awk '{print $1}'
    fi
}

parse_size() {
    local size_str="$1"
    if [[ "$size_str" =~ ^([0-9]+)([KMG])?$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            K) echo $((num * 1024)) ;;
            M) echo $((num * 1048576)) ;;
            G) echo $((num * 1073741824)) ;;
            *) echo "$num" ;;
        esac
    else
        echo 0
    fi
}

find_duplicates() {
    local search_path="$1"
    info "Scanning for duplicate files in: $search_path"
    
    declare -A file_hashes
    declare -A hash_files
    
    local find_opts="-type f -size +$(parse_size "$MIN_SIZE")c"
    [[ "$RECURSIVE" == false ]] && find_opts="$find_opts -maxdepth 1"
    
    # Find and hash files
    while IFS= read -r -d '' file; do
        ((TOTAL_FILES++))
        verbose "Hashing: $file"
        
        local hash=$(calculate_hash "$file")
        if [[ -n "$hash" ]]; then
            if [[ -n "${hash_files[$hash]:-}" ]]; then
                hash_files[$hash]="${hash_files[$hash]}|$file"
            else
                hash_files[$hash]="$file"
            fi
        fi
    done < <(eval find "$search_path" $find_opts -print0 2>/dev/null)
    
    # Process duplicates
    for hash in "${!hash_files[@]}"; do
        local files="${hash_files[$hash]}"
        local file_count=$(echo "$files" | tr '|' '\n' | wc -l)
        
        if (( file_count > 1 )); then
            ((DUPLICATE_SETS++))
            ((DUPLICATE_FILES += file_count - 1))
            process_duplicate_set "$files"
        fi
    done
}

select_file_to_keep() {
    local files="$1"
    IFS='|' read -ra file_array <<< "$files"
    
    case "$KEEP_STRATEGY" in
        newest)
            local newest_file=""
            local newest_time=0
            for f in "${file_array[@]}"; do
                local mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
                if (( mtime > newest_time )); then
                    newest_time=$mtime
                    newest_file="$f"
                fi
            done
            echo "$newest_file"
            ;;
        oldest)
            local oldest_file=""
            local oldest_time=9999999999
            for f in "${file_array[@]}"; do
                local mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
                if (( mtime < oldest_time )); then
                    oldest_time=$mtime
                    oldest_file="$f"
                fi
            done
            echo "$oldest_file"
            ;;
        smallest|largest)
            local selected_file="${file_array[0]}"
            local selected_size=$(stat -c %s "$selected_file" 2>/dev/null || stat -f %z "$selected_file" 2>/dev/null)
            for f in "${file_array[@]}"; do
                local fsize=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null)
                if [[ "$KEEP_STRATEGY" == "smallest" ]] && (( fsize < selected_size )); then
                    selected_file="$f"
                    selected_size=$fsize
                elif [[ "$KEEP_STRATEGY" == "largest" ]] && (( fsize > selected_size )); then
                    selected_file="$f"
                    selected_size=$fsize
                fi
            done
            echo "$selected_file"
            ;;
        *)
            echo "${file_array[0]}"
            ;;
    esac
}

process_duplicate_set() {
    local files="$1"
    IFS='|' read -ra file_array <<< "$files"
    
    echo ""
    warning "Duplicate files found (${#file_array[@]} copies):"
    
    local keep_file=$(select_file_to_keep "$files")
    
    for file in "${file_array[@]}"; do
        local size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
        local size_human=$(du -h "$file" | awk '{print $1}')
        
        if [[ "$file" == "$keep_file" ]]; then
            echo -e "  ${GREEN}KEEP${NC} [$size_human] $file"
        else
            echo -e "  ${RED}DELETE${NC} [$size_human] $file"
            
            if [[ "$INTERACTIVE" == true ]]; then
                read -p "Delete this file? (y/N): " -n 1 -r
                echo
                [[ $REPLY =~ ^[Yy]$ ]] && delete_file "$file" "$size"
            elif [[ "$DELETE_DUPLICATES" == true ]]; then
                delete_file "$file" "$size"
            elif [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete: $file"
            fi
        fi
    done
}

delete_file() {
    local file="$1"
    local size="$2"
    
    if rm "$file"; then
        ((FILES_DELETED++))
        ((SPACE_SAVED += size))
        verbose "Deleted: $file"
        [[ -n "$LOG_FILE" ]] && echo "[$(date)] Deleted: $file" >> "$LOG_FILE"
    else
        warning "Failed to delete: $file"
    fi
}

format_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

show_summary() {
    echo ""
    info "Summary:"
    echo "  Total files scanned: $TOTAL_FILES"
    echo "  Duplicate sets found: $DUPLICATE_SETS"
    echo "  Duplicate files: $DUPLICATE_FILES"
    
    if [[ "$DELETE_DUPLICATES" == true ]] || [[ "$INTERACTIVE" == true ]]; then
        echo "  Files deleted: $FILES_DELETED"
        echo "  Space saved: $(format_size $SPACE_SAVED)"
    fi
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -r|--recursive) RECURSIVE=true; shift ;;
        -d|--delete) DELETE_DUPLICATES=true; shift ;;
        -i|--interactive) INTERACTIVE=true; shift ;;
        -k|--keep) KEEP_STRATEGY="$2"; shift 2 ;;
        -m|--min-size) MIN_SIZE="$2"; shift 2 ;;
        -a|--algorithm) HASH_ALGO="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -l|--log) LOG_FILE="$2"; shift 2 ;;
        -*) error_exit "Unknown option: $1" 2 ;;
        *) SEARCH_DIR="$1"; shift ;;
    esac
done

# Main execution
[[ ! -d "$SEARCH_DIR" ]] && error_exit "Directory not found: $SEARCH_DIR" 2

find_duplicates "$SEARCH_DIR"
show_summary

success "Scan completed!"

