#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: hash-calculator.sh
# Description: File integrity checking with multiple hash algorithms, verification,
#              recursive directory hashing, and checksum file generation.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

ALGORITHM="sha256"
FILE=""
DIRECTORY=""
VERIFY_FILE=""
RECURSIVE=false
GENERATE_FILE=false

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

calculate_hash() {
    local file="$1"
    local algo="$2"
    
    case "$algo" in
        md5) md5sum "$file" 2>/dev/null || error_exit "Failed to calculate MD5" ;;
        sha1) sha1sum "$file" 2>/dev/null || error_exit "Failed to calculate SHA1" ;;
        sha256) sha256sum "$file" 2>/dev/null || error_exit "Failed to calculate SHA256" ;;
        sha512) sha512sum "$file" 2>/dev/null || error_exit "Failed to calculate SHA512" ;;
        *) error_exit "Unknown algorithm: $algo" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--algorithm) ALGORITHM="$2"; shift 2 ;;
        -f|--file) FILE="$2"; shift 2 ;;
        -d|--directory) DIRECTORY="$2"; RECURSIVE=true; shift 2 ;;
        --verify) VERIFY_FILE="$2"; shift 2 ;;
        --generate) GENERATE_FILE=true; shift ;;
        -h|--help) echo "Hash Calculator"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

if [[ -n "$FILE" ]]; then
    calculate_hash "$FILE" "$ALGORITHM"
elif [[ -n "$DIRECTORY" ]]; then
    find "$DIRECTORY" -type f -exec sh -c 'sha256sum "$1"' _ {} \;
elif [[ -n "$VERIFY_FILE" ]]; then
    "${ALGORITHM}sum" -c "$VERIFY_FILE" && success "Verification passed"
else
    error_exit "No file or directory specified" 2
fi
