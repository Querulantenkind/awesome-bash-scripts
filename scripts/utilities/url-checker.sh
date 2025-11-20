#!/bin/bash

################################################################################
# Script Name: url-checker.sh
# Description: Bulk URL availability checker with HTTP status codes, response
#              time measurement, SSL validation, redirect following, and export.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./url-checker.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -v, --verbose           Verbose output
#   -u, --url URL           Single URL to check
#   -f, --file FILE         File containing URLs (one per line)
#   -t, --timeout SECONDS   Request timeout (default: 10)
#   --ssl                   Validate SSL certificates
#   --redirects             Follow redirects
#   -o, --output FILE       Output file
#   --format FORMAT         Output format (text|json|csv)
#   -j, --json              JSON output
#   --no-color              Disable colors
#
# Examples:
#   ./url-checker.sh --url https://example.com
#   ./url-checker.sh --file urls.txt
#   ./url-checker.sh --file urls.txt --json
#   ./url-checker.sh --file urls.txt --output results.csv --format csv
#
# Dependencies:
#   - curl
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
################################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

VERBOSE=false
URL=""
URL_FILE=""
TIMEOUT=10
VALIDATE_SSL=false
FOLLOW_REDIRECTS=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
USE_COLOR=true

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"; }
info() { [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"; }

show_usage() {
    cat << EOF
${WHITE}URL Checker - Bulk URL Availability Checker${NC}

${CYAN}Usage:${NC} $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help
    -v, --verbose           Verbose output
    -u, --url URL           Single URL to check
    -f, --file FILE         File with URLs
    -t, --timeout SECONDS   Timeout (default: 10)
    --ssl                   Validate SSL
    --redirects             Follow redirects
    -o, --output FILE       Output file
    --format FORMAT         Format (text|json|csv)
    -j, --json              JSON output
    --no-color              Disable colors

${CYAN}Examples:${NC}
    $(basename "$0") --url https://example.com
    $(basename "$0") --file urls.txt --json

EOF
}

check_dependencies() {
    command -v curl &> /dev/null || error_exit "curl not found" 3
}

check_url() {
    local url="$1"
    local curl_opts="-s -w %{http_code}:%{time_total}:%{redirect_url} -o /dev/null --max-time $TIMEOUT"
    
    [[ "$VALIDATE_SSL" == false ]] && curl_opts="$curl_opts -k"
    [[ "$FOLLOW_REDIRECTS" == true ]] && curl_opts="$curl_opts -L"
    
    local result=$(curl $curl_opts "$url" 2>/dev/null || echo "000:0:")
    IFS=':' read -r status time redirect <<< "$result"
    
    echo "$status|$time|$redirect"
}

process_urls() {
    local urls=()
    
    if [[ -n "$URL" ]]; then
        urls=("$URL")
    elif [[ -n "$URL_FILE" ]]; then
        [[ ! -f "$URL_FILE" ]] && error_exit "File not found: $URL_FILE" 2
        mapfile -t urls < "$URL_FILE"
    else
        error_exit "No URL or file specified" 2
    fi
    
    [[ "$OUTPUT_FORMAT" == "csv" ]] && echo "URL,Status,ResponseTime,Redirect"
    
    for url in "${urls[@]}"; do
        [[ -z "$url" || "$url" =~ ^# ]] && continue
        
        IFS='|' read -r status time redirect <<< "$(check_url "$url")"
        
        case "$OUTPUT_FORMAT" in
            csv)
                echo "$url,$status,$time,$redirect"
                ;;
            json)
                cat << EOF
{"url": "$url", "status": $status, "time": $time, "redirect": "$redirect"}
EOF
                ;;
            *)
                if [[ $status -ge 200 && $status -lt 400 ]]; then
                    success "$url - $status (${time}s)"
                else
                    echo -e "${RED}✗ $url - $status${NC}"
                fi
                ;;
        esac
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -u|--url) URL="$2"; shift 2 ;;
        -f|--file) URL_FILE="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        --ssl) VALIDATE_SSL=true; shift ;;
        --redirects) FOLLOW_REDIRECTS=true; shift ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        --format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -j|--json) OUTPUT_FORMAT="json"; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_dependencies

if [[ -n "$OUTPUT_FILE" ]]; then
    process_urls > "$OUTPUT_FILE"
    success "Results saved to $OUTPUT_FILE"
else
    process_urls
fi
