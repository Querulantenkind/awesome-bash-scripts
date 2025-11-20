#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: text-processor.sh
# Description: Advanced text manipulation with CSV/JSON/XML parsing, find/replace,
#              column extraction, and format conversion.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

ACTION=""
INPUT_FILE=""
OUTPUT_FILE=""
PATTERN=""
REPLACEMENT=""
DELIMITER=","
COLUMN=""

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --extract-column) ACTION="extract"; COLUMN="$2"; shift 2 ;;
        --replace) ACTION="replace"; PATTERN="$2"; REPLACEMENT="$3"; shift 3 ;;
        -i|--input) INPUT_FILE="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -d|--delimiter) DELIMITER="$2"; shift 2 ;;
        -h|--help) echo "Text Processor Tool"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]] && error_exit "Input file required" 2

case "$ACTION" in
    extract)
        awk -F"$DELIMITER" "{print \$$COLUMN}" "$INPUT_FILE" > "${OUTPUT_FILE:-/dev/stdout}"
        ;;
    replace)
        sed "s/$PATTERN/$REPLACEMENT/g" "$INPUT_FILE" > "${OUTPUT_FILE:-/dev/stdout}"
        ;;
    *)
        cat "$INPUT_FILE"
        ;;
esac

success "Processing complete"
