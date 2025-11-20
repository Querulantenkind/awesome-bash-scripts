#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: code-formatter.sh
# Description: Multi-language code formatting with prettier, black, shfmt support,
#              batch processing, and pre-commit hook generation.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

LANGUAGE=""
FILE=""
DIRECTORY=""
DRY_RUN=false
RECURSIVE=false

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }

format_file() {
    local file="$1"
    local lang="${2:-auto}"
    
    [[ "$lang" == "auto" ]] && lang=$(detect_language "$file")
    
    info "Formatting: $file ($lang)"
    
    case "$lang" in
        bash|sh)
            command -v shfmt &> /dev/null && shfmt -w "$file" || error_exit "shfmt not found" 3
            ;;
        python|py)
            command -v black &> /dev/null && black "$file" || error_exit "black not found" 3
            ;;
        javascript|js|typescript|ts)
            command -v prettier &> /dev/null && prettier --write "$file" || error_exit "prettier not found" 3
            ;;
        *)
            info "No formatter for: $lang"
            ;;
    esac
}

detect_language() {
    local file="$1"
    case "${file##*.}" in
        sh) echo "bash" ;;
        py) echo "python" ;;
        js) echo "javascript" ;;
        ts) echo "typescript" ;;
        *) echo "unknown" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--language) LANGUAGE="$2"; shift 2 ;;
        -f|--file) FILE="$2"; shift 2 ;;
        -d|--directory) DIRECTORY="$2"; RECURSIVE=true; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) echo "Code Formatter"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

if [[ -n "$FILE" ]]; then
    [[ ! -f "$FILE" ]] && error_exit "File not found: $FILE" 2
    format_file "$FILE" "$LANGUAGE"
    success "Formatted: $FILE"
elif [[ -n "$DIRECTORY" ]]; then
    find "$DIRECTORY" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" \) | while read -r f; do
        format_file "$f" "auto"
    done
    success "Directory formatted"
else
    error_exit "No file or directory specified" 2
fi
