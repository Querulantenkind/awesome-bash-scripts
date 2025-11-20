#!/bin/bash

################################################################################
# Script Name: ssl-certificate-monitor.sh
# Description: SSL/TLS certificate monitoring and expiration tracking tool.
#              Monitors multiple domains, checks certificate validity, expiration
#              dates, and provides alerts for certificates nearing expiration.
#              Supports both remote domains and local certificate files.
# Author: Luca
# Created: 2025-11-20
# Modified: 2025-11-20
# Version: 1.0.0
#
# Usage: ./ssl-certificate-monitor.sh [options] [domain/file]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -d, --domain DOMAIN     Check specific domain
#   -f, --file CERTFILE     Check local certificate file
#   -l, --list FILE         Check domains from file (one per line)
#   -w, --warning DAYS      Warning threshold in days (default: 30)
#   -c, --critical DAYS     Critical threshold in days (default: 7)
#   -p, --port PORT         Port number (default: 443)
#   -j, --json              Output in JSON format
#   -o, --output FILE       Save output to file
#   --csv                   Output in CSV format
#   --watch INTERVAL        Continuous monitoring mode (seconds)
#   --log FILE              Log results to file
#   --no-color              Disable colored output
#   --timeout SECONDS       Connection timeout (default: 10)
#
# Examples:
#   # Check single domain
#   ./ssl-certificate-monitor.sh -d google.com
#
#   # Check multiple domains from file
#   ./ssl-certificate-monitor.sh -l domains.txt
#
#   # Check with custom thresholds
#   ./ssl-certificate-monitor.sh -d example.com -w 60 -c 14
#
#   # Watch mode with 5 minute intervals
#   ./ssl-certificate-monitor.sh -d example.com --watch 300
#
#   # Export to JSON
#   ./ssl-certificate-monitor.sh -l domains.txt --json -o report.json
#
#   # Check local certificate file
#   ./ssl-certificate-monitor.sh -f /etc/ssl/certs/cert.pem
#
# Dependencies:
#   - openssl (required)
#   - timeout (coreutils)
#
# Exit Codes:
#   0 - Success (all certificates valid)
#   1 - General error
#   2 - Invalid argument
#   3 - Certificate expired or expiring soon
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
DOMAINS=()
CERT_FILES=()
WARNING_DAYS=30
CRITICAL_DAYS=7
PORT=443
WATCH_MODE=false
WATCH_INTERVAL=300
TIMEOUT_SECONDS=10

# Statistics
TOTAL_CHECKED=0
VALID_CERTS=0
WARNING_CERTS=0
CRITICAL_CERTS=0
EXPIRED_CERTS=0
ERROR_COUNT=0

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
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
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
SSL Certificate Monitor - Certificate Expiration Tracking Tool

Usage:
    ssl-certificate-monitor.sh [OPTIONS]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --domain DOMAIN     Check specific domain
    -f, --file CERTFILE     Check local certificate file
    -l, --list FILE         Check domains from file
    -w, --warning DAYS      Warning threshold (default: 30)
    -c, --critical DAYS     Critical threshold (default: 7)
    -p, --port PORT         Port number (default: 443)
    -j, --json              Output in JSON format
    -o, --output FILE       Save output to file
    --csv                   Output in CSV format
    --watch INTERVAL        Continuous monitoring (seconds)
    --log FILE              Log results to file
    --no-color              Disable colored output
    --timeout SECONDS       Connection timeout (default: 10)

Examples:
    # Check single domain
    ssl-certificate-monitor.sh -d google.com

    # Check multiple domains from file
    ssl-certificate-monitor.sh -l domains.txt

    # Check with custom thresholds
    ssl-certificate-monitor.sh -d example.com -w 60 -c 14

    # Watch mode with 5 minute intervals
    ssl-certificate-monitor.sh -d example.com --watch 300

    # Export to JSON
    ssl-certificate-monitor.sh -l domains.txt --json -o report.json

    # Check local certificate file
    ssl-certificate-monitor.sh -f /etc/ssl/certs/cert.pem

    # Check with custom port
    ssl-certificate-monitor.sh -d example.com:8443

Features:
    • Remote domain certificate checking
    • Local certificate file validation
    • Configurable warning/critical thresholds
    • Continuous monitoring mode
    • Multiple output formats (text, JSON, CSV)
    • Certificate details (issuer, validity, SANs)
    • Batch domain checking
    • Connection timeout handling

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in openssl timeout; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 1
    fi
}

################################################################################
# Certificate Checking Functions
################################################################################

get_cert_from_domain() {
    local domain="$1"
    local port="${2:-443}"

    verbose "Connecting to $domain:$port"

    # Extract certificate
    timeout "$TIMEOUT_SECONDS" openssl s_client -connect "${domain}:${port}" \
        -servername "$domain" </dev/null 2>/dev/null | \
        openssl x509 -noout -text 2>/dev/null
}

get_cert_info() {
    local cert_text="$1"

    local issuer=$(echo "$cert_text" | grep "Issuer:" | sed 's/.*Issuer: //')
    local subject=$(echo "$cert_text" | grep "Subject:" | sed 's/.*Subject: //')
    local not_before=$(echo "$cert_text" | grep "Not Before:" | sed 's/.*Not Before: //')
    local not_after=$(echo "$cert_text" | grep "Not After :" | sed 's/.*Not After : //')

    # Get SANs
    local sans=$(echo "$cert_text" | grep -A1 "Subject Alternative Name:" | tail -1 | sed 's/DNS://g' | sed 's/, /,/g' || echo "N/A")

    echo "$issuer|$subject|$not_before|$not_after|$sans"
}

calculate_days_until_expiry() {
    local expiry_date="$1"

    # Convert to epoch time
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local current_epoch=$(date +%s)

    local diff_seconds=$((expiry_epoch - current_epoch))
    local days=$((diff_seconds / 86400))

    echo "$days"
}

check_domain_certificate() {
    local domain="$1"
    local port="${2:-443}"

    verbose "Checking certificate for $domain:$port"

    ((TOTAL_CHECKED++))

    # Get certificate
    local cert_text
    if ! cert_text=$(get_cert_from_domain "$domain" "$port" 2>&1); then
        ((ERROR_COUNT++))
        return 1
    fi

    if [[ -z "$cert_text" ]]; then
        warning "Failed to retrieve certificate from $domain:$port"
        ((ERROR_COUNT++))
        return 1
    fi

    # Parse certificate info
    local cert_info=$(get_cert_info "$cert_text")
    IFS='|' read -r issuer subject not_before not_after sans <<< "$cert_info"

    # Calculate days until expiry
    local days_left=$(calculate_days_until_expiry "$not_after")

    # Determine status
    local status="VALID"
    local status_color="$GREEN"

    if [[ $days_left -lt 0 ]]; then
        status="EXPIRED"
        status_color="$RED"
        ((EXPIRED_CERTS++))
    elif [[ $days_left -le $CRITICAL_DAYS ]]; then
        status="CRITICAL"
        status_color="$RED"
        ((CRITICAL_CERTS++))
    elif [[ $days_left -le $WARNING_DAYS ]]; then
        status="WARNING"
        status_color="$YELLOW"
        ((WARNING_CERTS++))
    else
        ((VALID_CERTS++))
    fi

    # Output result
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << JSONEOF
    {
      "domain": "$domain",
      "port": $port,
      "status": "$status",
      "days_remaining": $days_left,
      "issuer": "$issuer",
      "subject": "$subject",
      "valid_from": "$not_before",
      "valid_until": "$not_after",
      "sans": "$sans"
    }
JSONEOF
    elif [[ "$CSV_OUTPUT" == true ]]; then
        echo "$domain,$port,$status,$days_left,\"$issuer\",\"$not_after\""
    else
        echo -e "${status_color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}Domain:${NC}        $domain:$port"
        echo -e "${CYAN}Status:${NC}        ${status_color}${status}${NC}"
        echo -e "${CYAN}Days Left:${NC}     ${status_color}${days_left}${NC}"
        echo -e "${CYAN}Issuer:${NC}        $issuer"
        echo -e "${CYAN}Valid From:${NC}    $not_before"
        echo -e "${CYAN}Valid Until:${NC}   $not_after"
        [[ "$sans" != "N/A" ]] && echo -e "${CYAN}SANs:${NC}          $sans"
    fi

    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $domain:$port - $status - $days_left days" >> "$LOG_FILE"

    return 0
}

check_file_certificate() {
    local cert_file="$1"

    verbose "Checking certificate file: $cert_file"

    if [[ ! -f "$cert_file" ]]; then
        warning "Certificate file not found: $cert_file"
        ((ERROR_COUNT++))
        return 1
    fi

    ((TOTAL_CHECKED++))

    # Get certificate info
    local cert_text
    if ! cert_text=$(openssl x509 -in "$cert_file" -text -noout 2>&1); then
        warning "Failed to parse certificate file: $cert_file"
        ((ERROR_COUNT++))
        return 1
    fi

    # Parse certificate info
    local cert_info=$(get_cert_info "$cert_text")
    IFS='|' read -r issuer subject not_before not_after sans <<< "$cert_info"

    # Calculate days until expiry
    local days_left=$(calculate_days_until_expiry "$not_after")

    # Determine status
    local status="VALID"
    local status_color="$GREEN"

    if [[ $days_left -lt 0 ]]; then
        status="EXPIRED"
        status_color="$RED"
        ((EXPIRED_CERTS++))
    elif [[ $days_left -le $CRITICAL_DAYS ]]; then
        status="CRITICAL"
        status_color="$RED"
        ((CRITICAL_CERTS++))
    elif [[ $days_left -le $WARNING_DAYS ]]; then
        status="WARNING"
        status_color="$YELLOW"
        ((WARNING_CERTS++))
    else
        ((VALID_CERTS++))
    fi

    # Output result
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << JSONEOF
    {
      "file": "$cert_file",
      "status": "$status",
      "days_remaining": $days_left,
      "issuer": "$issuer",
      "subject": "$subject",
      "valid_from": "$not_before",
      "valid_until": "$not_after",
      "sans": "$sans"
    }
JSONEOF
    elif [[ "$CSV_OUTPUT" == true ]]; then
        echo "$cert_file,N/A,$status,$days_left,\"$issuer\",\"$not_after\""
    else
        echo -e "${status_color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}File:${NC}          $cert_file"
        echo -e "${CYAN}Status:${NC}        ${status_color}${status}${NC}"
        echo -e "${CYAN}Days Left:${NC}     ${status_color}${days_left}${NC}"
        echo -e "${CYAN}Issuer:${NC}        $issuer"
        echo -e "${CYAN}Subject:${NC}       $subject"
        echo -e "${CYAN}Valid From:${NC}    $not_before"
        echo -e "${CYAN}Valid Until:${NC}   $not_after"
        [[ "$sans" != "N/A" ]] && echo -e "${CYAN}SANs:${NC}          $sans"
    fi

    return 0
}

################################################################################
# Main Processing Functions
################################################################################

process_all_certificates() {
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","
        echo "  \"thresholds\": {"
        echo "    \"warning_days\": $WARNING_DAYS,"
        echo "    \"critical_days\": $CRITICAL_DAYS"
        echo "  },"
        echo "  \"certificates\": ["
    elif [[ "$CSV_OUTPUT" == true ]]; then
        echo "Domain/File,Port,Status,Days Remaining,Issuer,Expiry Date"
    else
        section_header "SSL CERTIFICATE MONITOR"
        echo -e "${CYAN}Scan Time:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${CYAN}Warning:${NC}       $WARNING_DAYS days"
        echo -e "${CYAN}Critical:${NC}      $CRITICAL_DAYS days"
        echo ""
    fi

    local first=true

    # Check domains
    for domain in "${DOMAINS[@]}"; do
        [[ "$JSON_OUTPUT" == true ]] && [[ "$first" == false ]] && echo ","
        first=false

        check_domain_certificate "$domain" "$PORT"
    done

    # Check certificate files
    for cert_file in "${CERT_FILES[@]}"; do
        [[ "$JSON_OUTPUT" == true ]] && [[ "$first" == false ]] && echo ","
        first=false

        check_file_certificate "$cert_file"
    done

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo ""
        echo "  ],"
        echo "  \"summary\": {"
        echo "    \"total_checked\": $TOTAL_CHECKED,"
        echo "    \"valid\": $VALID_CERTS,"
        echo "    \"warning\": $WARNING_CERTS,"
        echo "    \"critical\": $CRITICAL_CERTS,"
        echo "    \"expired\": $EXPIRED_CERTS,"
        echo "    \"errors\": $ERROR_COUNT"
        echo "  }"
        echo "}"
    elif [[ "$CSV_OUTPUT" == false ]]; then
        # Print summary
        section_header "SUMMARY"
        echo -e "${CYAN}Total Checked:${NC}  $TOTAL_CHECKED"
        echo -e "${GREEN}Valid:${NC}          $VALID_CERTS"
        echo -e "${YELLOW}Warning:${NC}        $WARNING_CERTS"
        echo -e "${RED}Critical:${NC}       $CRITICAL_CERTS"
        echo -e "${RED}Expired:${NC}        $EXPIRED_CERTS"
        [[ $ERROR_COUNT -gt 0 ]] && echo -e "${RED}Errors:${NC}         $ERROR_COUNT"
        echo ""

        # Overall status
        if [[ $EXPIRED_CERTS -gt 0 ]] || [[ $CRITICAL_CERTS -gt 0 ]]; then
            warning "Action required: Some certificates are expired or critical!"
        elif [[ $WARNING_CERTS -gt 0 ]]; then
            warning "Some certificates are nearing expiration"
        else
            success "All certificates are valid"
        fi
    fi
}

watch_certificates() {
    verbose "Starting watch mode (interval: ${WATCH_INTERVAL}s)"

    while true; do
        clear
        process_all_certificates
        verbose "Next check in ${WATCH_INTERVAL} seconds... (Press Ctrl+C to stop)"
        sleep "$WATCH_INTERVAL"

        # Reset counters
        TOTAL_CHECKED=0
        VALID_CERTS=0
        WARNING_CERTS=0
        CRITICAL_CERTS=0
        EXPIRED_CERTS=0
        ERROR_COUNT=0
    done
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
        -d|--domain)
            [[ -z "${2:-}" ]] && error_exit "--domain requires a domain name" 2
            DOMAINS+=("$2")
            shift 2
            ;;
        -f|--file)
            [[ -z "${2:-}" ]] && error_exit "--file requires a certificate file path" 2
            CERT_FILES+=("$2")
            shift 2
            ;;
        -l|--list)
            [[ -z "${2:-}" ]] && error_exit "--list requires a file path" 2
            if [[ ! -f "$2" ]]; then
                error_exit "Domain list file not found: $2" 1
            fi
            while IFS= read -r domain; do
                [[ -n "$domain" ]] && [[ ! "$domain" =~ ^# ]] && DOMAINS+=("$domain")
            done < "$2"
            shift 2
            ;;
        -w|--warning)
            [[ -z "${2:-}" ]] && error_exit "--warning requires number of days" 2
            WARNING_DAYS="$2"
            shift 2
            ;;
        -c|--critical)
            [[ -z "${2:-}" ]] && error_exit "--critical requires number of days" 2
            CRITICAL_DAYS="$2"
            shift 2
            ;;
        -p|--port)
            [[ -z "${2:-}" ]] && error_exit "--port requires a port number" 2
            PORT="$2"
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
        --watch)
            WATCH_MODE=true
            [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]] && WATCH_INTERVAL="$2" && shift
            shift
            ;;
        --timeout)
            [[ -z "${2:-}" ]] && error_exit "--timeout requires seconds" 2
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            DOMAINS+=("$1")
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Validate input
if [[ ${#DOMAINS[@]} -eq 0 ]] && [[ ${#CERT_FILES[@]} -eq 0 ]]; then
    error_exit "No domains or certificate files specified. Use -h for help." 2
fi

# Execute monitoring
if [[ "$WATCH_MODE" == true ]]; then
    watch_certificates
else
    output=$(process_all_certificates)

    # Output to file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output" > "$OUTPUT_FILE"
        success "Report saved to: $OUTPUT_FILE"
    else
        echo "$output"
    fi
fi

# Exit with appropriate code
if [[ $EXPIRED_CERTS -gt 0 ]] || [[ $CRITICAL_CERTS -gt 0 ]]; then
    exit 3
fi

verbose "Certificate monitoring completed"
exit 0
