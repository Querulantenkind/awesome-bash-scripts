#!/bin/bash

################################################################################
# Script Name: log-analyzer.sh
# Description: Advanced log file analyzer with real-time monitoring, pattern
#              detection, error tracking, and alert capabilities. Supports
#              multiple log formats and provides statistical analysis.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./log-analyzer.sh [options] [logfile]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -f, --follow            Follow log file (like tail -f)
#   -n, --lines NUM         Number of lines to analyze (default: 1000)
#   -p, --pattern PATTERN   Search for specific pattern (regex)
#   -e, --errors            Show only errors and warnings
#   -s, --stats             Display statistical analysis
#   -t, --time-range START-END  Analyze logs within time range
#   -l, --level LEVEL       Filter by log level (ERROR, WARN, INFO, DEBUG)
#   -o, --output FILE       Save report to file
#   -j, --json              Output in JSON format
#   --tail NUM              Show last N lines (default: 100)
#   --ip IP                 Filter by IP address
#   --http-codes            Show HTTP status code distribution
#   --top-ips NUM           Show top N IP addresses
#   --alert-on PATTERN      Alert when pattern is found
#
# Examples:
#   ./log-analyzer.sh /var/log/syslog
#   ./log-analyzer.sh --follow --errors /var/log/nginx/error.log
#   ./log-analyzer.sh --stats --http-codes /var/log/nginx/access.log
#   ./log-analyzer.sh --pattern "authentication failure" /var/log/auth.log
#   ./log-analyzer.sh --top-ips 10 --http-codes /var/log/apache2/access.log
#
# Dependencies:
#   - awk, sed, grep (standard utilities)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - File not found
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
FOLLOW_MODE=false
NUM_LINES=1000
SEARCH_PATTERN=""
ERRORS_ONLY=false
SHOW_STATS=false
TIME_RANGE=""
LOG_LEVEL=""
OUTPUT_FILE=""
JSON_OUTPUT=false
TAIL_LINES=100
FILTER_IP=""
SHOW_HTTP_CODES=false
TOP_IPS=0
ALERT_PATTERN=""
LOG_FILE=""
USE_COLOR=true

# Statistics variables
TOTAL_LINES=0
ERROR_COUNT=0
WARN_COUNT=0
INFO_COUNT=0
DEBUG_COUNT=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

show_usage() {
    cat << 'EOF'
Log Analyzer - Advanced Log File Analysis and Monitoring

Usage:
    log-analyzer.sh [OPTIONS] LOGFILE

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --follow            Follow log file in real-time
    -n, --lines NUM         Number of lines to analyze (default: 1000)
    -p, --pattern PATTERN   Search for specific pattern (regex)
    -e, --errors            Show only errors and warnings
    -s, --stats             Display statistical analysis
    -t, --time-range RANGE  Time range (e.g., "2024-11-20 10:00-11:00")
    -l, --level LEVEL       Filter by log level (ERROR|WARN|INFO|DEBUG)
    -o, --output FILE       Save report to file
    -j, --json              Output in JSON format
    --tail NUM              Show last N lines (default: 100)
    --ip IP                 Filter by IP address
    --http-codes            Show HTTP status code distribution
    --top-ips NUM           Show top N IP addresses
    --alert-on PATTERN      Alert when pattern is found

Examples:
    # Analyze system log
    log-analyzer.sh /var/log/syslog

    # Follow error log in real-time
    log-analyzer.sh --follow --errors /var/log/nginx/error.log

    # Analyze with statistics
    log-analyzer.sh --stats /var/log/application.log

    # Search for specific pattern
    log-analyzer.sh --pattern "failed login" /var/log/auth.log

    # Nginx access log analysis
    log-analyzer.sh --http-codes --top-ips 20 /var/log/nginx/access.log

    # Filter by time range
    log-analyzer.sh --time-range "2024-11-20 10:00-11:00" /var/log/syslog

    # Alert on specific pattern
    log-analyzer.sh --follow --alert-on "CRITICAL" /var/log/app.log

Log Format Support:
    • Syslog format
    • Apache/Nginx access logs
    • Nginx error logs
    • Application logs (JSON and plain text)
    • Custom formats with pattern matching

EOF
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in awk sed grep tail; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi
}

################################################################################
# Log Analysis Functions
################################################################################

detect_log_format() {
    local file="$1"
    local sample
    
    sample=$(head -n 10 "$file" 2>/dev/null || echo "")
    
    if [[ "$sample" =~ \"request\":.*\"response\": ]]; then
        echo "json"
    elif [[ "$sample" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}.*HTTP ]]; then
        echo "apache_access"
    elif [[ "$sample" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}.*\[error\] ]]; then
        echo "nginx_error"
    elif [[ "$sample" =~ ^[A-Z][a-z]{2}[[:space:]]+[0-9]{1,2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        echo "syslog"
    else
        echo "generic"
    fi
}

count_log_levels() {
    local content="$1"
    
    ERROR_COUNT=$(echo "$content" | grep -ciE "(error|err|fatal|critical)" || echo 0)
    WARN_COUNT=$(echo "$content" | grep -ciE "(warn|warning)" || echo 0)
    INFO_COUNT=$(echo "$content" | grep -ciE "(info|information)" || echo 0)
    DEBUG_COUNT=$(echo "$content" | grep -ciE "(debug|trace)" || echo 0)
    TOTAL_LINES=$(echo "$content" | wc -l)
}

extract_timestamps() {
    local content="$1"
    
    # Try different timestamp formats
    echo "$content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1
}

analyze_http_codes() {
    local content="$1"
    
    echo -e "\n${WHITE}━━━ HTTP STATUS CODE DISTRIBUTION ━━━${NC}"
    
    local codes
    codes=$(echo "$content" | grep -oE ' [0-9]{3} ' | sort | uniq -c | sort -rn)
    
    if [[ -z "$codes" ]]; then
        echo "No HTTP status codes found"
        return
    fi
    
    printf "${CYAN}%-10s %-10s %-s${NC}\n" "Count" "Code" "Description"
    
    while IFS= read -r line; do
        local count=$(echo "$line" | awk '{print $1}')
        local code=$(echo "$line" | awk '{print $2}')
        local desc=$(get_http_description "$code")
        
        # Color code based on status
        if [[ "$code" =~ ^2 ]]; then
            printf "${GREEN}%-10s %-10s %-s${NC}\n" "$count" "$code" "$desc"
        elif [[ "$code" =~ ^3 ]]; then
            printf "${CYAN}%-10s %-10s %-s${NC}\n" "$count" "$code" "$desc"
        elif [[ "$code" =~ ^4 ]]; then
            printf "${YELLOW}%-10s %-10s %-s${NC}\n" "$count" "$code" "$desc"
        elif [[ "$code" =~ ^5 ]]; then
            printf "${RED}%-10s %-10s %-s${NC}\n" "$count" "$code" "$desc"
        fi
    done <<< "$codes"
}

get_http_description() {
    local code="$1"
    
    case "$code" in
        200) echo "OK" ;;
        201) echo "Created" ;;
        204) echo "No Content" ;;
        301) echo "Moved Permanently" ;;
        302) echo "Found" ;;
        304) echo "Not Modified" ;;
        400) echo "Bad Request" ;;
        401) echo "Unauthorized" ;;
        403) echo "Forbidden" ;;
        404) echo "Not Found" ;;
        405) echo "Method Not Allowed" ;;
        500) echo "Internal Server Error" ;;
        502) echo "Bad Gateway" ;;
        503) echo "Service Unavailable" ;;
        504) echo "Gateway Timeout" ;;
        *) echo "Unknown" ;;
    esac
}

analyze_top_ips() {
    local content="$1"
    local count="$2"
    
    echo -e "\n${WHITE}━━━ TOP $count IP ADDRESSES ━━━${NC}"
    
    local ips
    ips=$(echo "$content" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort | uniq -c | sort -rn | head -n "$count")
    
    if [[ -z "$ips" ]]; then
        echo "No IP addresses found"
        return
    fi
    
    printf "${CYAN}%-10s %-s${NC}\n" "Requests" "IP Address"
    
    while IFS= read -r line; do
        local requests=$(echo "$line" | awk '{print $1}')
        local ip=$(echo "$line" | awk '{print $2}')
        printf "%-10s %-s\n" "$requests" "$ip"
    done <<< "$ips"
}

search_pattern() {
    local content="$1"
    local pattern="$2"
    
    echo -e "\n${WHITE}━━━ PATTERN MATCHES: $pattern ━━━${NC}"
    
    local matches
    matches=$(echo "$content" | grep -iE "$pattern" | head -n 50)
    
    if [[ -z "$matches" ]]; then
        echo "No matches found"
        return 0
    fi
    
    local count=$(echo "$matches" | wc -l)
    echo -e "${YELLOW}Found $count matches (showing first 50):${NC}\n"
    
    echo "$matches" | while IFS= read -r line; do
        # Highlight the pattern in the output
        echo "$line" | sed -E "s/($pattern)/${RED}\1${NC}/gi"
    done
}

filter_by_level() {
    local content="$1"
    local level="$2"
    
    case "${level^^}" in
        ERROR|ERR)
            echo "$content" | grep -iE "(error|err|fatal|critical)"
            ;;
        WARN|WARNING)
            echo "$content" | grep -iE "(warn|warning)"
            ;;
        INFO|INFORMATION)
            echo "$content" | grep -iE "(info|information)"
            ;;
        DEBUG)
            echo "$content" | grep -iE "(debug|trace)"
            ;;
        *)
            echo "$content"
            ;;
    esac
}

################################################################################
# Display Functions
################################################################################

display_header() {
    local format=$(detect_log_format "$LOG_FILE")
    local file_size=$(du -h "$LOG_FILE" | awk '{print $1}')
    local line_count=$(wc -l < "$LOG_FILE")
    
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                    LOG ANALYZER                                 ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}File:${NC}         $LOG_FILE"
    echo -e "${CYAN}Format:${NC}       $format"
    echo -e "${CYAN}Size:${NC}         $file_size"
    echo -e "${CYAN}Total Lines:${NC}  $line_count"
    echo -e "${CYAN}Analyzing:${NC}    $NUM_LINES lines"
    echo -e "${CYAN}Timestamp:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

display_statistics() {
    local content="$1"
    
    count_log_levels "$content"
    
    echo -e "${WHITE}━━━ LOG STATISTICS ━━━${NC}"
    echo -e "${CYAN}Total Lines:${NC}      $TOTAL_LINES"
    echo -e "${RED}Errors:${NC}           $ERROR_COUNT ($(echo "scale=2; $ERROR_COUNT * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo 0)%)"
    echo -e "${YELLOW}Warnings:${NC}         $WARN_COUNT ($(echo "scale=2; $WARN_COUNT * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo 0)%)"
    echo -e "${GREEN}Info:${NC}             $INFO_COUNT ($(echo "scale=2; $INFO_COUNT * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo 0)%)"
    echo -e "${BLUE}Debug:${NC}            $DEBUG_COUNT ($(echo "scale=2; $DEBUG_COUNT * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo 0)%)"
    
    # Time range
    local first_ts=$(echo "$content" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1 || echo "N/A")
    local last_ts=$(echo "$content" | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1 || echo "N/A")
    
    if [[ "$first_ts" != "N/A" ]]; then
        echo -e "${CYAN}Time Range:${NC}       $first_ts → $last_ts"
    fi
    echo ""
}

display_errors() {
    local content="$1"
    
    echo -e "${WHITE}━━━ ERRORS AND WARNINGS ━━━${NC}"
    
    local errors
    errors=$(echo "$content" | grep -iE "(error|err|warn|warning|fatal|critical)" | head -n 50)
    
    if [[ -z "$errors" ]]; then
        success "No errors or warnings found!"
        return
    fi
    
    local count=$(echo "$errors" | wc -l)
    echo -e "${YELLOW}Showing first 50 errors/warnings (found $count):${NC}\n"
    
    echo "$errors" | while IFS= read -r line; do
        if [[ "$line" =~ [Ee][Rr][Rr][Oo][Rr]|[Ff][Aa][Tt][Aa][Ll]|[Cc][Rr][Ii][Tt][Ii][Cc][Aa][Ll] ]]; then
            echo -e "${RED}✗${NC} $line"
        else
            echo -e "${YELLOW}⚠${NC} $line"
        fi
    done
    echo ""
}

display_tail() {
    local content="$1"
    local lines="${2:-100}"
    
    echo -e "${WHITE}━━━ LAST $lines LINES ━━━${NC}"
    echo "$content" | tail -n "$lines"
    echo ""
}

generate_json_report() {
    local content="$1"
    
    count_log_levels "$content"
    
    cat << EOF
{
  "file": "$LOG_FILE",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "analysis": {
    "total_lines": $TOTAL_LINES,
    "errors": $ERROR_COUNT,
    "warnings": $WARN_COUNT,
    "info": $INFO_COUNT,
    "debug": $DEBUG_COUNT
  },
  "format": "$(detect_log_format "$LOG_FILE")"
}
EOF
}

follow_log() {
    echo -e "${CYAN}Following log file: $LOG_FILE${NC}"
    echo -e "${CYAN}Press Ctrl+C to stop${NC}\n"
    
    tail -f "$LOG_FILE" | while IFS= read -r line; do
        # Color code based on content
        if [[ "$line" =~ [Ee][Rr][Rr][Oo][Rr]|[Ff][Aa][Tt][Aa][Ll]|[Cc][Rr][Ii][Tt][Ii][Cc][Aa][Ll] ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ "$line" =~ [Ww][Aa][Rr][Nn] ]]; then
            echo -e "${YELLOW}$line${NC}"
        else
            echo "$line"
        fi
        
        # Alert if pattern matches
        if [[ -n "$ALERT_PATTERN" ]] && [[ "$line" =~ $ALERT_PATTERN ]]; then
            echo -e "\n${RED}━━━ ALERT: Pattern matched! ━━━${NC}"
            echo -e "${RED}$line${NC}\n"
        fi
    done
}

################################################################################
# Main Analysis Function
################################################################################

run_analysis() {
    local content
    
    # Read log content
    verbose "Reading last $NUM_LINES lines from $LOG_FILE"
    content=$(tail -n "$NUM_LINES" "$LOG_FILE")
    
    # Filter by IP if specified
    if [[ -n "$FILTER_IP" ]]; then
        verbose "Filtering by IP: $FILTER_IP"
        content=$(echo "$content" | grep "$FILTER_IP")
    fi
    
    # Filter by log level
    if [[ -n "$LOG_LEVEL" ]]; then
        verbose "Filtering by log level: $LOG_LEVEL"
        content=$(filter_by_level "$content" "$LOG_LEVEL")
    fi
    
    # Generate output
    if [[ "$JSON_OUTPUT" == true ]]; then
        generate_json_report "$content"
    else
        display_header
        
        if [[ "$SHOW_STATS" == true ]]; then
            display_statistics "$content"
        fi
        
        if [[ "$ERRORS_ONLY" == true ]]; then
            display_errors "$content"
        fi
        
        if [[ -n "$SEARCH_PATTERN" ]]; then
            search_pattern "$content" "$SEARCH_PATTERN"
        fi
        
        if [[ "$SHOW_HTTP_CODES" == true ]]; then
            analyze_http_codes "$content"
        fi
        
        if [[ $TOP_IPS -gt 0 ]]; then
            analyze_top_ips "$content" "$TOP_IPS"
        fi
        
        if [[ "$SHOW_STATS" == false ]] && [[ "$ERRORS_ONLY" == false ]] && [[ -z "$SEARCH_PATTERN" ]]; then
            display_tail "$content" "$TAIL_LINES"
        fi
    fi
    
    # Save to file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_json_report "$content" > "$OUTPUT_FILE"
        else
            run_analysis > "$OUTPUT_FILE" 2>&1
        fi
        success "Report saved to $OUTPUT_FILE"
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
        -f|--follow)
            FOLLOW_MODE=true
            shift
            ;;
        -n|--lines)
            [[ -z "${2:-}" ]] && error_exit "--lines requires a number" 2
            NUM_LINES="$2"
            shift 2
            ;;
        -p|--pattern)
            [[ -z "${2:-}" ]] && error_exit "--pattern requires a pattern argument" 2
            SEARCH_PATTERN="$2"
            shift 2
            ;;
        -e|--errors)
            ERRORS_ONLY=true
            shift
            ;;
        -s|--stats)
            SHOW_STATS=true
            shift
            ;;
        -l|--level)
            [[ -z "${2:-}" ]] && error_exit "--level requires a log level" 2
            LOG_LEVEL="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "--output requires a file path" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --tail)
            [[ -z "${2:-}" ]] && error_exit "--tail requires a number" 2
            TAIL_LINES="$2"
            shift 2
            ;;
        --ip)
            [[ -z "${2:-}" ]] && error_exit "--ip requires an IP address" 2
            FILTER_IP="$2"
            shift 2
            ;;
        --http-codes)
            SHOW_HTTP_CODES=true
            shift
            ;;
        --top-ips)
            [[ -z "${2:-}" ]] && error_exit "--top-ips requires a number" 2
            TOP_IPS="$2"
            shift 2
            ;;
        --alert-on)
            [[ -z "${2:-}" ]] && error_exit "--alert-on requires a pattern" 2
            ALERT_PATTERN="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            LOG_FILE="$1"
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Validate log file
if [[ -z "$LOG_FILE" ]]; then
    error_exit "No log file specified. Use -h for help." 2
fi

if [[ ! -f "$LOG_FILE" ]]; then
    error_exit "Log file not found: $LOG_FILE" 3
fi

if [[ ! -r "$LOG_FILE" ]]; then
    error_exit "Cannot read log file: $LOG_FILE (permission denied)" 1
fi

verbose "Analyzing log file: $LOG_FILE"

# Run analysis or follow mode
if [[ "$FOLLOW_MODE" == true ]]; then
    follow_log
else
    run_analysis
fi

verbose "Analysis complete"

