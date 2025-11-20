#!/bin/bash

################################################################################
# Script Name: argument-parsing.sh
# Description: Demonstrates various argument parsing techniques
# Usage: ./argument-parsing.sh [OPTIONS] [ARGUMENTS]
################################################################################

set -euo pipefail

# Default values
VERBOSE=false
OUTPUT_FILE=""
INPUT_FILES=()

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [FILES...]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -o, --output FILE       Specify output file

Examples:
    $(basename "$0") -v file1.txt file2.txt
    $(basename "$0") --output result.txt input.txt

EOF
}

# Parse arguments
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
        -o|--output)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --output requires an argument" >&2
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            show_usage
            exit 1
            ;;
        *)
            INPUT_FILES+=("$1")
            shift
            ;;
    esac
done

# Main logic
main() {
    echo "Verbose: $VERBOSE"
    echo "Output file: ${OUTPUT_FILE:-<none>}"
    echo "Input files: ${INPUT_FILES[*]:-<none>}"
}

main

