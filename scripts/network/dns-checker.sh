#!/bin/bash

################################################################################
# Script Name: dns-checker.sh
# Description: DNS resolution testing and diagnostics tool
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./dns-checker.sh [options] [domain]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -d, --domain DOMAIN     Domain to check
#   -f, --file FILE         Check domains from file (one per line)
#   -s, --server SERVER     Use specific DNS server
#   -t, --type TYPE         Record type (A, AAAA, MX, NS, TXT, etc.)
#   -w, --watch SECONDS     Continuous monitoring mode
#   -c, --compare           Compare multiple DNS servers
#   --trace                 Trace DNS resolution path
#   --reverse IP            Reverse DNS lookup
#   -j, --json              Output in JSON format
#   --timeout SECONDS       Query timeout (default: 5)
#   --no-color              Disable colored output
#
# Examples:
#   ./dns-checker.sh example.com
#   ./dns-checker.sh -d example.com -t MX
#   ./dns-checker.sh -d example.com -s 8.8.8.8 --compare
#   ./dns-checker.sh --file domains.txt --json
#   ./dns-checker.sh --reverse 8.8.8.8
#
# Dependencies:
#   - dig or nslookup
#   - host (optional)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - DNS resolution failed
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
LOG_FILE=""
JSON_OUTPUT=false
WATCH_MODE=false
WATCH_INTERVAL=5
COMPARE_MODE=false
TRACE_MODE=false
REVERSE_LOOKUP=""
USE_COLOR=true
TIMEOUT=5

DOMAIN=""
DOMAINS_FILE=""
DNS_SERVER=""
RECORD_TYPE="A"

# DNS servers for comparison
DEFAULT_DNS_SERVERS=("8.8.8.8" "1.1.1.1" "208.67.222.222" "9.9.9.9")

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"
}

warning() {
    [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"
}

info() {
    [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"
}

verbose() {
    [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2
}

log_message() {
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

show_usage() {
    cat << EOF
${WHITE}DNS Checker - DNS Resolution Testing and Diagnostics${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS] [DOMAIN]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -d, --domain DOMAIN     Domain to check
    -f, --file FILE         Check domains from file (one per line)
    -s, --server SERVER     Use specific DNS server
    -t, --type TYPE         Record type (A, AAAA, MX, NS, TXT, CNAME, SOA)
    -w, --watch SECONDS     Continuous monitoring mode
    -c, --compare           Compare multiple DNS servers
    --trace                 Trace DNS resolution path
    --reverse IP            Reverse DNS lookup
    -j, --json              Output in JSON format
    --timeout SECONDS       Query timeout (default: 5)
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Basic DNS lookup
    $SCRIPT_NAME example.com

    # Check MX records
    $SCRIPT_NAME -d example.com -t MX

    # Use specific DNS server
    $SCRIPT_NAME -d example.com -s 8.8.8.8

    # Compare across multiple DNS servers
    $SCRIPT_NAME -d example.com --compare

    # Check multiple domains from file
    $SCRIPT_NAME --file domains.txt --json

    # Reverse DNS lookup
    $SCRIPT_NAME --reverse 8.8.8.8

    # Continuous monitoring
    $SCRIPT_NAME -d example.com --watch 10

EOF
}

check_dependencies() {
    local missing_deps=()

    if ! command -v dig &> /dev/null && ! command -v nslookup &> /dev/null; then
        missing_deps+=("dig or nslookup")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}\nInstall with: sudo apt install dnsutils" 3
    fi
}

################################################################################
# DNS Query Functions
################################################################################

query_dns_dig() {
    local domain="$1"
    local type="$2"
    local server="${3:-}"

    local dig_cmd="dig +time=$TIMEOUT"

    [[ -n "$server" ]] && dig_cmd="$dig_cmd @$server"
    dig_cmd="$dig_cmd $domain $type +short"

    verbose "Running: $dig_cmd"

    local result
    result=$(eval "$dig_cmd" 2>&1) || return 1

    echo "$result"
}

query_dns_nslookup() {
    local domain="$1"
    local type="$2"
    local server="${3:-}"

    local nslookup_cmd="nslookup -timeout=$TIMEOUT -type=$type $domain"

    [[ -n "$server" ]] && nslookup_cmd="$nslookup_cmd $server"

    verbose "Running: $nslookup_cmd"

    local result
    result=$(eval "$nslookup_cmd" 2>&1 | grep -A 10 "Name:" | grep -v "Name:" | grep -v "^$" | awk '{print $NF}') || return 1

    echo "$result"
}

query_dns() {
    local domain="$1"
    local type="${2:-A}"
    local server="${3:-}"

    if command -v dig &> /dev/null; then
        query_dns_dig "$domain" "$type" "$server"
    elif command -v nslookup &> /dev/null; then
        query_dns_nslookup "$domain" "$type" "$server"
    else
        error_exit "No DNS query tool available" 3
    fi
}

reverse_dns_lookup() {
    local ip="$1"

    info "Reverse DNS lookup for: $ip"

    if command -v dig &> /dev/null; then
        local result=$(dig +short -x "$ip")
    else
        local result=$(nslookup "$ip" | grep "name =" | awk '{print $NF}')
    fi

    if [[ -n "$result" ]]; then
        success "PTR record: $result"
        log_message "Reverse lookup $ip: $result"
    else
        warning "No PTR record found for $ip"
        log_message "Reverse lookup $ip: No record"
    fi
}

trace_dns_path() {
    local domain="$1"

    info "Tracing DNS resolution path for: $domain"

    if command -v dig &> /dev/null; then
        dig +trace "$domain" | grep -E "^(;;|[a-zA-Z])" | head -20
    else
        warning "DNS tracing requires dig command"
    fi
}

################################################################################
# Analysis Functions
################################################################################

check_domain() {
    local domain="$1"
    local server="${2:-}"

    echo ""
    if [[ -n "$server" ]]; then
        info "Checking $domain using DNS server: $server"
    else
        info "Checking $domain using system DNS"
    fi
    echo "=========================================="

    # Query DNS
    local result
    result=$(query_dns "$domain" "$RECORD_TYPE" "$server")

    if [[ -z "$result" ]]; then
        warning "No $RECORD_TYPE records found for $domain"
        log_message "DNS check failed: $domain ($RECORD_TYPE)"
        return 1
    fi

    success "DNS resolution successful"
    echo "$result" | while read -r line; do
        echo "  $RECORD_TYPE: $line"
    done

    log_message "DNS check success: $domain ($RECORD_TYPE): $result"

    # Additional checks
    if [[ "$RECORD_TYPE" == "A" ]]; then
        check_response_time "$domain" "$server"
    fi
}

check_response_time() {
    local domain="$1"
    local server="${2:-}"

    if ! command -v dig &> /dev/null; then
        return 0
    fi

    local dig_cmd="dig +time=$TIMEOUT"
    [[ -n "$server" ]] && dig_cmd="$dig_cmd @$server"
    dig_cmd="$dig_cmd $domain A"

    local query_time=$(eval "$dig_cmd" 2>/dev/null | grep "Query time:" | awk '{print $4}')

    if [[ -n "$query_time" ]]; then
        if [[ $query_time -lt 50 ]]; then
            success "Response time: ${query_time}ms (excellent)"
        elif [[ $query_time -lt 100 ]]; then
            info "Response time: ${query_time}ms (good)"
        elif [[ $query_time -lt 200 ]]; then
            warning "Response time: ${query_time}ms (slow)"
        else
            warning "Response time: ${query_time}ms (very slow)"
        fi
    fi
}

compare_dns_servers() {
    local domain="$1"

    echo ""
    info "Comparing DNS servers for: $domain"
    echo "=========================================="

    for server in "${DEFAULT_DNS_SERVERS[@]}"; do
        echo ""
        echo "Server: $server"

        local start_time=$(date +%s%N)
        local result=$(query_dns "$domain" "$RECORD_TYPE" "$server" 2>/dev/null)
        local end_time=$(date +%s%N)

        if [[ -n "$result" ]]; then
            local duration=$(( (end_time - start_time) / 1000000 ))
            success "Response: $duration ms"
            echo "$result" | head -3 | while read -r line; do
                echo "  $line"
            done
        else
            warning "Failed to resolve"
        fi
    done

    echo "=========================================="
}

################################################################################
# Batch Processing
################################################################################

process_domains_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        error_exit "File not found: $file" 2
    fi

    info "Processing domains from: $file"

    local total=0
    local success_count=0
    local failed_count=0

    while IFS= read -r domain; do
        # Skip empty lines and comments
        [[ -z "$domain" ]] || [[ "$domain" =~ ^# ]] && continue

        ((total++))

        if check_domain "$domain" "$DNS_SERVER" &>/dev/null; then
            ((success_count++))
        else
            ((failed_count++))
        fi
    done < "$file"

    echo ""
    echo "=========================================="
    info "Total domains: $total"
    success "Successful: $success_count"
    [[ $failed_count -gt 0 ]] && warning "Failed: $failed_count" || info "Failed: 0"
    echo "=========================================="
}

################################################################################
# Main Function
################################################################################

main() {
    check_dependencies

    # Reverse lookup
    if [[ -n "$REVERSE_LOOKUP" ]]; then
        reverse_dns_lookup "$REVERSE_LOOKUP"
        exit 0
    fi

    # Trace mode
    if [[ "$TRACE_MODE" == true ]] && [[ -n "$DOMAIN" ]]; then
        trace_dns_path "$DOMAIN"
        exit 0
    fi

    # File processing
    if [[ -n "$DOMAINS_FILE" ]]; then
        process_domains_file "$DOMAINS_FILE"
        exit 0
    fi

    # Single domain check
    if [[ -n "$DOMAIN" ]]; then
        if [[ "$COMPARE_MODE" == true ]]; then
            compare_dns_servers "$DOMAIN"
        elif [[ "$WATCH_MODE" == true ]]; then
            info "Starting continuous monitoring (interval: ${WATCH_INTERVAL}s, press Ctrl+C to stop)..."
            while true; do
                clear
                check_domain "$DOMAIN" "$DNS_SERVER"
                sleep "$WATCH_INTERVAL"
            done
        else
            check_domain "$DOMAIN" "$DNS_SERVER"
        fi
    else
        error_exit "No domain specified. Use -d/--domain or provide domain as argument" 2
    fi
}

################################################################################
# Argument Parsing
################################################################################

# Handle positional argument
if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
    DOMAIN="$1"
    shift
fi

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
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -f|--file)
            DOMAINS_FILE="$2"
            shift 2
            ;;
        -s|--server)
            DNS_SERVER="$2"
            shift 2
            ;;
        -t|--type)
            RECORD_TYPE="${2^^}"
            shift 2
            ;;
        -w|--watch)
            WATCH_MODE=true
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -c|--compare)
            COMPARE_MODE=true
            shift
            ;;
        --trace)
            TRACE_MODE=true
            shift
            ;;
        --reverse)
            REVERSE_LOOKUP="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        *)
            error_exit "Unknown option: $1\nUse -h or --help for usage information." 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

main

exit 0
