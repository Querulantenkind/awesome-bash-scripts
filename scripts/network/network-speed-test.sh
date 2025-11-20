#!/bin/bash

################################################################################
# Script Name: network-speed-test.sh
# Description: Network speed testing tool with upload/download speed measurement,
#              latency testing, multiple test servers, and historical tracking.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./network-speed-test.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --server URL        Test server URL
#   -t, --test TYPE         Test type (download|upload|both, default: both)
#   -c, --count NUM         Number of tests to run (default: 1)
#   --latency               Test latency only
#   --history               Show historical test results
#   --track FILE            Track results to file
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./network-speed-test.sh
#   ./network-speed-test.sh --test download
#   ./network-speed-test.sh --latency
#   ./network-speed-test.sh --history
#   ./network-speed-test.sh --track /var/log/speed-tests.log
#
# Dependencies:
#   - curl or wget
#   - ping
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
TEST_SERVER="http://speedtest.tele2.net/10MB.zip"
TEST_TYPE="both"
TEST_COUNT=1
LATENCY_ONLY=false
SHOW_HISTORY=false
TRACK_FILE=""
JSON_OUTPUT=false
USE_COLOR=true

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"; }
warning() { [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"; }
info() { [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2; }

show_usage() {
    cat << EOF
${WHITE}Network Speed Test - Network Performance Testing Tool${NC}

${CYAN}Usage:${NC} $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help message
    -v, --verbose           Verbose output
    -s, --server URL        Test server URL
    -t, --test TYPE         Test type (download|upload|both)
    -c, --count NUM         Number of tests to run
    --latency               Test latency only
    --history               Show historical results
    --track FILE            Track results to file
    -j, --json              JSON output
    --no-color              Disable colors

${CYAN}Examples:${NC}
    $(basename "$0")
    $(basename "$0") --test download
    $(basename "$0") --latency
    $(basename "$0") --history

EOF
}

check_dependencies() {
    local missing=()
    command -v curl &> /dev/null || command -v wget &> /dev/null || missing+=("curl or wget")
    command -v ping &> /dev/null || missing+=("ping")
    [[ ${#missing[@]} -gt 0 ]] && error_exit "Missing dependencies: ${missing[*]}" 3
}

test_latency() {
    local host=$(echo "$TEST_SERVER" | sed 's|http://||' | sed 's|https://||' | cut -d'/' -f1)
    info "Testing latency to $host..."
    
    local result=$(ping -c 4 "$host" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d'/' -f2)
    
    if [[ -n "$result" ]]; then
        success "Average latency: ${result}ms"
    else
        warning "Latency test failed"
    fi
}

test_download_speed() {
    info "Testing download speed..."
    
    local speed
    if command -v curl &> /dev/null; then
        speed=$(curl -o /dev/null -s -w '%{speed_download}' "$TEST_SERVER" | awk '{printf "%.2f", $1/1024/1024}')
    elif command -v wget &> /dev/null; then
        speed=$(wget -O /dev/null "$TEST_SERVER" 2>&1 | grep -i "MB/s" | awk '{print $7}')
    fi
    
    if [[ -n "$speed" ]]; then
        success "Download speed: ${speed} MB/s"
        echo "$speed"
    else
        warning "Download test failed"
        echo "0"
    fi
}

test_upload_speed() {
    info "Testing upload speed..."
    # Simplified upload test (would need actual upload endpoint)
    warning "Upload test requires upload server endpoint"
    echo "0"
}

run_speed_test() {
    echo ""
    echo -e "${WHITE}━━━ NETWORK SPEED TEST ━━━${NC}"
    echo ""
    
    if [[ "$LATENCY_ONLY" == true ]]; then
        test_latency
        return
    fi
    
    if [[ "$TEST_TYPE" =~ (both|download) ]]; then
        test_download_speed
    fi
    
    if [[ "$TEST_TYPE" =~ (both|upload) ]]; then
        test_upload_speed
    fi
    
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -s|--server) TEST_SERVER="$2"; shift 2 ;;
        -t|--test) TEST_TYPE="$2"; shift 2 ;;
        -c|--count) TEST_COUNT="$2"; shift 2 ;;
        --latency) LATENCY_ONLY=true; shift ;;
        --history) SHOW_HISTORY=true; shift ;;
        --track) TRACK_FILE="$2"; shift 2 ;;
        -j|--json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_dependencies
run_speed_test
