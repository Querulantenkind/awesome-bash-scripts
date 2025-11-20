#!/bin/bash

################################################################################
# Script Name: disk-space-analyzer.sh
# Description: Comprehensive disk usage analyzer with directory tree visualization,
#              largest file/directory detection, colorized output, sorting options,
#              file type filtering, and multiple export formats. Helps identify
#              disk space usage patterns and find space-consuming files.
# Author: Luca
# Created: 2025-11-20
# Modified: 2025-11-20
# Version: 1.0.0
#
# Usage: ./disk-space-analyzer.sh [options] [path]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -t, --tree              Show directory tree with sizes
#   -l, --largest NUM       Show NUM largest files/directories
#   -d, --depth NUM         Limit directory depth (default: unlimited)
#   -s, --sort METHOD       Sort by: size, name, type (default: size)
#   -f, --filter TYPE       Filter by file type (e.g., *.log, *.txt)
#   -e, --exclude PATTERN   Exclude directories/files matching pattern
#   -m, --min-size SIZE     Minimum size to display (e.g., 1M, 100K)
#   -j, --json              Output in JSON format
#   --csv                   Output in CSV format
#   -o, --output FILE       Save output to file
#   -l, --log FILE          Log operations to file
#   --no-color              Disable colored output
#   --human                 Human-readable sizes (default)
#   --bytes                 Show sizes in bytes
#   --files-only            Show files only
#   --dirs-only             Show directories only
#   --summary               Show summary statistics only
#
# Examples:
#   # Analyze current directory
#   ./disk-space-analyzer.sh
#
#   # Show directory tree with sizes
#   ./disk-space-analyzer.sh --tree /var/log
#
#   # Find 20 largest files
#   ./disk-space-analyzer.sh --largest 20 /home
#
#   # Analyze with depth limit
#   ./disk-space-analyzer.sh --tree --depth 3 /usr
#
#   # Filter log files larger than 10MB
#   ./disk-space-analyzer.sh --filter "*.log" --min-size 10M /var
#
#   # Export to JSON
#   ./disk-space-analyzer.sh --largest 50 --json -o report.json
#
#   # Exclude specific directories
#   ./disk-space-analyzer.sh --exclude "node_modules" --exclude ".git"
#
# Dependencies:
#   - du, find (standard utilities)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Path not found
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
JSON_OUTPUT=false
CSV_OUTPUT=false
OUTPUT_FILE=""
LOG_FILE=""
USE_COLOR=true
SHOW_TREE=false
LARGEST_N=0
DEPTH_LIMIT=""
SORT_METHOD="size"
FILTER_TYPE=""
EXCLUDE_PATTERNS=()
MIN_SIZE=""
MIN_SIZE_BYTES=0
HUMAN_READABLE=true
FILES_ONLY=false
DIRS_ONLY=false
SUMMARY_ONLY=false
TARGET_PATH="."

# Statistics
TOTAL_SIZE=0
TOTAL_FILES=0
TOTAL_DIRS=0
LARGEST_FILE=""
LARGEST_FILE_SIZE=0

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
        if [[ "$USE_COLOR" == true ]]; then
            echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
        else
            echo "[VERBOSE] $1" >&2
        fi
    fi
}

section_header() {
    if [[ "$JSON_OUTPUT" == false ]] && [[ "$CSV_OUTPUT" == false ]]; then
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
    cat << 'EOF'
Disk Space Analyzer - Advanced Disk Usage Analysis Tool

Usage:
    disk-space-analyzer.sh [OPTIONS] [PATH]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -t, --tree              Show directory tree with sizes
    -l, --largest NUM       Show NUM largest files/directories
    -d, --depth NUM         Limit directory depth
    -s, --sort METHOD       Sort by: size, name, type
    -f, --filter TYPE       Filter by file type (e.g., *.log)
    -e, --exclude PATTERN   Exclude pattern
    -m, --min-size SIZE     Minimum size (e.g., 1M, 100K)
    -j, --json              Output in JSON format
    --csv                   Output in CSV format
    -o, --output FILE       Save output to file
    --log FILE              Log operations to file
    --no-color              Disable colored output
    --human                 Human-readable sizes (default)
    --bytes                 Show sizes in bytes
    --files-only            Show files only
    --dirs-only             Show directories only
    --summary               Show summary statistics only

Examples:
    # Analyze current directory
    disk-space-analyzer.sh

    # Show directory tree with sizes
    disk-space-analyzer.sh --tree /var/log

    # Find 20 largest files
    disk-space-analyzer.sh --largest 20 /home

    # Analyze with depth limit
    disk-space-analyzer.sh --tree --depth 3 /usr

    # Filter log files larger than 10MB
    disk-space-analyzer.sh --filter "*.log" --min-size 10M /var

    # Export to JSON
    disk-space-analyzer.sh --largest 50 --json -o report.json

    # Exclude specific directories
    disk-space-analyzer.sh --exclude "node_modules" --exclude ".git"

Features:
    • Directory tree visualization
    • Find largest files and directories
    • Colorized output based on size
    • Multiple sorting options
    • File type filtering
    • Pattern exclusion
    • Depth limiting
    • Human-readable or byte output
    • JSON/CSV export
    • Summary statistics

EOF
}

################################################################################
# Size Conversion Functions
################################################################################

parse_size() {
    local size_str="$1"
    local size_bytes=0

    # Remove spaces
    size_str="${size_str// /}"

    # Extract number and unit
    if [[ "$size_str" =~ ^([0-9]+)([KMGT]?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"

        case "${unit^^}" in
            K)
                size_bytes=$((num * 1024))
                ;;
            M)
                size_bytes=$((num * 1024 * 1024))
                ;;
            G)
                size_bytes=$((num * 1024 * 1024 * 1024))
                ;;
            T)
                size_bytes=$((num * 1024 * 1024 * 1024 * 1024))
                ;;
            *)
                size_bytes=$num
                ;;
        esac

        echo "$size_bytes"
    else
        echo "0"
    fi
}

format_size() {
    local bytes="$1"

    if [[ "$HUMAN_READABLE" == false ]]; then
        echo "$bytes"
        return
    fi

    local units=("B" "K" "M" "G" "T")
    local unit=0
    local size=$bytes

    while (( size > 1024 && unit < 4 )); do
        size=$((size / 1024))
        ((unit++))
    done

    echo "${size}${units[$unit]}"
}

get_size_color() {
    local bytes="$1"

    if [[ "$USE_COLOR" == false ]]; then
        echo ""
        return
    fi

    # Color code based on size
    if (( bytes > 1073741824 )); then      # > 1GB
        echo "$RED"
    elif (( bytes > 104857600 )); then     # > 100MB
        echo "$YELLOW"
    elif (( bytes > 10485760 )); then      # > 10MB
        echo "$CYAN"
    else
        echo "$GREEN"
    fi
}

################################################################################
# Analysis Functions
################################################################################

collect_statistics() {
    local path="$1"

    verbose "Collecting statistics for: $path"

    # Count files and directories
    if [[ -d "$path" ]]; then
        TOTAL_FILES=$(find "$path" -type f 2>/dev/null | wc -l)
        TOTAL_DIRS=$(find "$path" -type d 2>/dev/null | wc -l)

        # Get total size
        TOTAL_SIZE=$(du -sb "$path" 2>/dev/null | awk '{print $1}')
    fi

    verbose "Total files: $TOTAL_FILES"
    verbose "Total directories: $TOTAL_DIRS"
    verbose "Total size: $TOTAL_SIZE bytes"
}

show_directory_tree() {
    local path="$1"

    section_header "DIRECTORY TREE: $path"

    verbose "Generating directory tree..."

    local du_opts="-h"
    [[ "$HUMAN_READABLE" == false ]] && du_opts="-b"

    local depth_opt=""
    [[ -n "$DEPTH_LIMIT" ]] && depth_opt="-d $DEPTH_LIMIT"

    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts --exclude=$pattern"
    done

    # Generate tree
    du $du_opts $depth_opt $exclude_opts "$path" 2>/dev/null | sort -rh | while read -r size item; do
        local bytes
        if [[ "$HUMAN_READABLE" == true ]]; then
            bytes=$(du -sb "$item" 2>/dev/null | awk '{print $1}')
        else
            bytes=$size
        fi

        local color=$(get_size_color "$bytes")
        local depth=$(($(echo "$item" | tr -cd '/' | wc -c) - $(echo "$path" | tr -cd '/' | wc -c)))
        local indent=$(printf '%*s' $((depth * 2)) '')

        if [[ -d "$item" ]]; then
            echo -e "${indent}${color}${size}${NC}  $(basename "$item")/"
        else
            echo -e "${indent}${color}${size}${NC}  $(basename "$item")"
        fi
    done
}

find_largest_items() {
    local path="$1"
    local num="$2"

    section_header "TOP $num LARGEST ITEMS"

    verbose "Finding largest items in: $path"

    # Build find command
    local find_type=""
    [[ "$FILES_ONLY" == true ]] && find_type="-type f"
    [[ "$DIRS_ONLY" == true ]] && find_type="-type d"

    local find_filter=""
    [[ -n "$FILTER_TYPE" ]] && find_filter="-name $FILTER_TYPE"

    # Build exclude options
    local exclude_opts=""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_opts="$exclude_opts ! -path *$pattern*"
    done

    if [[ "$CSV_OUTPUT" == true ]]; then
        echo "Size (bytes),Size,Type,Path"
    elif [[ "$JSON_OUTPUT" == false ]]; then
        printf "${CYAN}%-12s %-10s %-6s %-s${NC}\n" "Size" "Bytes" "Type" "Path"
    fi

    # Find and display largest items
    local items=()
    while IFS= read -r -d '' file; do
        local size_bytes=$(du -sb "$file" 2>/dev/null | awk '{print $1}')

        # Check minimum size
        if [[ $size_bytes -ge $MIN_SIZE_BYTES ]]; then
            items+=("$size_bytes|$file")
        fi
    done < <(find "$path" $find_type $find_filter $exclude_opts -print0 2>/dev/null)

    # Sort and display
    local count=0
    for item in $(printf '%s\n' "${items[@]}" | sort -t'|' -k1 -rn | head -n "$num"); do
        IFS='|' read -r size_bytes file <<< "$item"

        local size_human=$(format_size "$size_bytes")
        local color=$(get_size_color "$size_bytes")
        local item_type="file"
        [[ -d "$file" ]] && item_type="dir"

        if [[ "$JSON_OUTPUT" == true ]]; then
            [[ $count -gt 0 ]] && echo ","
            cat << JSONEOF
    {
      "size_bytes": $size_bytes,
      "size_human": "$size_human",
      "type": "$item_type",
      "path": "$file"
    }
JSONEOF
        elif [[ "$CSV_OUTPUT" == true ]]; then
            echo "$size_bytes,$size_human,$item_type,\"$file\""
        else
            printf "${color}%-12s${NC} %-10s %-6s %-s\n" "$size_human" "$size_bytes" "$item_type" "$file"
        fi

        ((count++))
    done
}

show_summary() {
    section_header "SUMMARY STATISTICS"

    local avg_file_size=0
    [[ $TOTAL_FILES -gt 0 ]] && avg_file_size=$((TOTAL_SIZE / TOTAL_FILES))

    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "path": "$TARGET_PATH",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "statistics": {
    "total_size_bytes": $TOTAL_SIZE,
    "total_size_human": "$(format_size $TOTAL_SIZE)",
    "total_files": $TOTAL_FILES,
    "total_directories": $TOTAL_DIRS,
    "average_file_size_bytes": $avg_file_size,
    "average_file_size_human": "$(format_size $avg_file_size)"
  }
}
EOF
    elif [[ "$CSV_OUTPUT" == true ]]; then
        echo "Metric,Value"
        echo "Path,\"$TARGET_PATH\""
        echo "Total Size (bytes),$TOTAL_SIZE"
        echo "Total Size,$(format_size $TOTAL_SIZE)"
        echo "Total Files,$TOTAL_FILES"
        echo "Total Directories,$TOTAL_DIRS"
        echo "Average File Size,$(format_size $avg_file_size)"
    else
        echo -e "${CYAN}Path:${NC}               $TARGET_PATH"
        echo -e "${CYAN}Total Size:${NC}         $(format_size $TOTAL_SIZE) ($TOTAL_SIZE bytes)"
        echo -e "${CYAN}Total Files:${NC}        $TOTAL_FILES"
        echo -e "${CYAN}Total Directories:${NC}  $TOTAL_DIRS"
        echo -e "${CYAN}Average File Size:${NC}  $(format_size $avg_file_size)"
    fi
}

analyze_file_types() {
    local path="$1"

    section_header "FILE TYPE DISTRIBUTION"

    verbose "Analyzing file types..."

    declare -A type_count
    declare -A type_size

    # Collect file type statistics
    while IFS= read -r -d '' file; do
        local ext="${file##*.}"
        [[ "$file" == "$ext" ]] && ext="no-extension"

        local size=$(du -sb "$file" 2>/dev/null | awk '{print $1}')

        type_count[$ext]=$((${type_count[$ext]:-0} + 1))
        type_size[$ext]=$((${type_size[$ext]:-0} + size))
    done < <(find "$path" -type f -print0 2>/dev/null)

    # Display results
    if [[ "$CSV_OUTPUT" == true ]]; then
        echo "Extension,Count,Total Size (bytes),Total Size"
    else
        printf "${CYAN}%-15s %-10s %-15s %-s${NC}\n" "Extension" "Count" "Total Size" "Size (bytes)"
    fi

    for ext in "${!type_count[@]}"; do
        local count=${type_count[$ext]}
        local size=${type_size[$ext]}
        local size_human=$(format_size $size)

        if [[ "$CSV_OUTPUT" == true ]]; then
            echo "$ext,$count,$size,$size_human"
        else
            printf "%-15s %-10s %-15s %-s\n" "$ext" "$count" "$size_human" "$size"
        fi
    done | sort -t',' -k3 -rn | head -20
}

################################################################################
# Main Analysis
################################################################################

run_analysis() {
    if [[ ! -e "$TARGET_PATH" ]]; then
        error_exit "Path not found: $TARGET_PATH" 3
    fi

    if [[ "$JSON_OUTPUT" == false ]] && [[ "$CSV_OUTPUT" == false ]]; then
        echo ""
        echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║               DISK SPACE ANALYZER                               ║${NC}"
        echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${CYAN}Target Path:${NC}  $TARGET_PATH"
        echo -e "${CYAN}Start Time:${NC}   $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    # Collect statistics
    collect_statistics "$TARGET_PATH"

    # Generate output based on options
    if [[ "$SUMMARY_ONLY" == true ]]; then
        show_summary
    elif [[ "$SHOW_TREE" == true ]]; then
        show_directory_tree "$TARGET_PATH"
        show_summary
    elif [[ $LARGEST_N -gt 0 ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            echo "{"
            echo "  \"largest_items\": ["
        fi

        find_largest_items "$TARGET_PATH" "$LARGEST_N"

        if [[ "$JSON_OUTPUT" == true ]]; then
            echo ""
            echo "  ],"
            echo "  \"summary\": $(show_summary)"
            echo "}"
        fi
    else
        # Default: show summary and file type distribution
        show_summary
        analyze_file_types "$TARGET_PATH"
    fi

    if [[ "$JSON_OUTPUT" == false ]] && [[ "$CSV_OUTPUT" == false ]]; then
        echo ""
        success "Analysis complete"
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
        -t|--tree)
            SHOW_TREE=true
            shift
            ;;
        -l|--largest)
            [[ -z "${2:-}" ]] && error_exit "--largest requires a number" 2
            LARGEST_N="$2"
            shift 2
            ;;
        -d|--depth)
            [[ -z "${2:-}" ]] && error_exit "--depth requires a number" 2
            DEPTH_LIMIT="$2"
            shift 2
            ;;
        -s|--sort)
            [[ -z "${2:-}" ]] && error_exit "--sort requires a method (size, name, type)" 2
            SORT_METHOD="$2"
            shift 2
            ;;
        -f|--filter)
            [[ -z "${2:-}" ]] && error_exit "--filter requires a file type pattern" 2
            FILTER_TYPE="$2"
            shift 2
            ;;
        -e|--exclude)
            [[ -z "${2:-}" ]] && error_exit "--exclude requires a pattern" 2
            EXCLUDE_PATTERNS+=("$2")
            shift 2
            ;;
        -m|--min-size)
            [[ -z "${2:-}" ]] && error_exit "--min-size requires a size (e.g., 1M)" 2
            MIN_SIZE="$2"
            MIN_SIZE_BYTES=$(parse_size "$MIN_SIZE")
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --csv)
            CSV_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "--output requires a file path" 2
            OUTPUT_FILE="$2"
            shift 2
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
        --human)
            HUMAN_READABLE=true
            shift
            ;;
        --bytes)
            HUMAN_READABLE=false
            shift
            ;;
        --files-only)
            FILES_ONLY=true
            shift
            ;;
        --dirs-only)
            DIRS_ONLY=true
            shift
            ;;
        --summary)
            SUMMARY_ONLY=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            TARGET_PATH="$1"
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

# Validate path
TARGET_PATH=$(realpath "$TARGET_PATH" 2>/dev/null || echo "$TARGET_PATH")

verbose "Starting disk space analysis..."
verbose "Target: $TARGET_PATH"

# Run analysis
output=$(run_analysis)

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$output" > "$OUTPUT_FILE"
    success "Report saved to: $OUTPUT_FILE"
else
    echo "$output"
fi

verbose "Disk space analysis completed"
exit 0
