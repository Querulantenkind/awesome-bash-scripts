#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: media-metadata.sh
# Description: Extract and edit media file metadata (ID3 tags, EXIF) with bulk
#              operations and JSON/CSV export.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

FILE=""
ACTION="show"
TAG_NAME=""
TAG_VALUE=""
OUTPUT_FORMAT="text"

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

show_metadata() {
    local file="$1"
    
    if command -v exiftool &> /dev/null; then
        exiftool "$file"
    elif command -v ffprobe &> /dev/null; then
        ffprobe -v quiet -print_format json -show_format "$file"
    else
        error_exit "No metadata tool found (install exiftool or ffmpeg)" 3
    fi
}

set_metadata() {
    local file="$1"
    local tag="$2"
    local value="$3"
    
    command -v exiftool &> /dev/null || error_exit "exiftool not found" 3
    
    exiftool "-$tag=$value" "$file"
    success "Metadata updated"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file) FILE="$2"; shift 2 ;;
        --show) ACTION="show"; shift ;;
        --set) ACTION="set"; TAG_NAME="$2"; TAG_VALUE="$3"; shift 3 ;;
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) echo "Media Metadata Tool"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$FILE" || ! -f "$FILE" ]] && error_exit "File required" 2

case "$ACTION" in
    show) show_metadata "$FILE" ;;
    set) set_metadata "$FILE" "$TAG_NAME" "$TAG_VALUE" ;;
esac
