#!/bin/bash

################################################################################
# Script Name: log-aggregator.sh
# Description: Multi-source log aggregator that collects, parses, filters, and
#              correlates logs from various sources (files, syslog, journald,
#              remote hosts) with real-time monitoring and alerting.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./log-aggregator.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -s, --source TYPE       Log source: file, syslog, journald, remote
#   -f, --file PATH         Log file path (can specify multiple)
#   -r, --remote HOST       Remote host (SSH)
#   -p, --pattern REGEX     Filter by regex pattern
#   -l, --level LEVEL       Filter by log level (ERROR, WARN, INFO, DEBUG)
#   --since TIME            Show logs since time (e.g., "1 hour ago", "2024-01-01")
#   --until TIME            Show logs until time
#   -t, --tail              Follow logs in real-time
#   -n, --lines N           Number of lines to show (default: 100)
#   --aggregate             Aggregate and summarize logs
#   --stats                 Show log statistics
#   --correlate             Correlate logs across sources
#   -o, --output FILE       Save output to file
#   -f, --format FORMAT     Output format: text, json, csv, html
#   --alert PATTERN         Alert on pattern match
#   --alert-email EMAIL     Email for alerts
#   -v, --verbose           Verbose output
#
# Examples:
#   ./log-aggregator.sh -s file -f /var/log/syslog --level ERROR
#   ./log-aggregator.sh -s journald --since "1 hour ago" --tail
#   ./log-aggregator.sh -s remote -r server.com -p "nginx" --stats
#   ./log-aggregator.sh --aggregate --format json -o report.json
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

LOG_SOURCES=()
LOG_FILES=()
REMOTE_HOSTS=()
FILTER_PATTERN=""
FILTER_LEVEL=""
SINCE_TIME=""
UNTIL_TIME=""
TAIL_MODE=false
NUM_LINES=100
AGGREGATE_MODE=false
SHOW_STATS=false
CORRELATE_MODE=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
ALERT_PATTERN=""
ALERT_EMAIL=""
VERBOSE=false

# Temp files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Statistics
declare -A LOG_COUNTS
declare -A ERROR_COUNTS
declare -A HOST_COUNTS

################################################################################
# Log Collection Functions
################################################################################

collect_file_logs() {
    local file="$1"
    local output="$TEMP_DIR/$(basename "$file").collected"
    
    if [[ ! -f "$file" ]]; then
        warning "Log file not found: $file"
        return 1
    fi
    
    if [[ "$TAIL_MODE" == true ]]; then
        tail -n "$NUM_LINES" -f "$file" > "$output" &
        echo $! >> "$TEMP_DIR/pids"
    else
        tail -n "$NUM_LINES" "$file" > "$output"
    fi
    
    echo "$output"
}

collect_syslog() {
    local output="$TEMP_DIR/syslog.collected"
    
    if command_exists journalctl; then
        collect_journald
        return
    fi
    
    local syslog_file="/var/log/syslog"
    [[ ! -f "$syslog_file" ]] && syslog_file="/var/log/messages"
    
    if [[ -f "$syslog_file" ]]; then
        collect_file_logs "$syslog_file"
    else
        error_exit "Syslog not found" 1
    fi
}

collect_journald() {
    local output="$TEMP_DIR/journald.collected"
    
    require_command journalctl systemd
    
    local cmd="journalctl -n $NUM_LINES"
    [[ -n "$SINCE_TIME" ]] && cmd+=" --since '$SINCE_TIME'"
    [[ -n "$UNTIL_TIME" ]] && cmd+=" --until '$UNTIL_TIME'"
    [[ "$TAIL_MODE" == true ]] && cmd+=" -f"
    
    if [[ "$TAIL_MODE" == true ]]; then
        $cmd > "$output" &
        echo $! >> "$TEMP_DIR/pids"
    else
        $cmd > "$output"
    fi
    
    echo "$output"
}

collect_remote_logs() {
    local host="$1"
    local output="$TEMP_DIR/${host//[.:\/]/_}.collected"
    
    require_command ssh openssh-client
    
    info "Collecting logs from remote host: $host"
    
    # Collect via SSH
    ssh "$host" "tail -n $NUM_LINES /var/log/syslog 2>/dev/null || tail -n $NUM_LINES /var/log/messages 2>/dev/null || journalctl -n $NUM_LINES" > "$output" 2>/dev/null || {
        warning "Failed to collect logs from $host"
        return 1
    }
    
    echo "$output"
}

################################################################################
# Log Parsing and Filtering
################################################################################

parse_log_line() {
    local line="$1"
    local source="$2"
    
    # Extract timestamp, level, message
    local timestamp=""
    local level="INFO"
    local message="$line"
    
    # Common log patterns
    if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        timestamp="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^([A-Z][a-z]{2}\ +[0-9]{1,2}\ +[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
        timestamp="${BASH_REMATCH[1]}"
    fi
    
    # Extract log level
    if [[ "$line" =~ (ERROR|ERRO|ERR) ]]; then
        level="ERROR"
    elif [[ "$line" =~ (WARN|WARNING) ]]; then
        level="WARN"
    elif [[ "$line" =~ (INFO|INFORMATION) ]]; then
        level="INFO"
    elif [[ "$line" =~ (DEBUG|DBG) ]]; then
        level="DEBUG"
    elif [[ "$line" =~ (FATAL|CRIT|CRITICAL) ]]; then
        level="FATAL"
    fi
    
    # Update statistics
    ((LOG_COUNTS["$source"]++)) || LOG_COUNTS["$source"]=1
    [[ "$level" == "ERROR" ]] && ((ERROR_COUNTS["$source"]++)) || ERROR_COUNTS["$source"]=0
    
    echo "$timestamp|$level|$source|$message"
}

apply_filters() {
    local line="$1"
    
    IFS='|' read -r timestamp level source message <<< "$line"
    
    # Level filter
    if [[ -n "$FILTER_LEVEL" ]] && [[ "$level" != "$FILTER_LEVEL" ]]; then
        return 1
    fi
    
    # Pattern filter
    if [[ -n "$FILTER_PATTERN" ]] && ! echo "$message" | grep -qE "$FILTER_PATTERN"; then
        return 1
    fi
    
    # Alert check
    if [[ -n "$ALERT_PATTERN" ]] && echo "$message" | grep -qE "$ALERT_PATTERN"; then
        send_alert "$line"
    fi
    
    return 0
}

################################################################################
# Analysis Functions
################################################################################

aggregate_logs() {
    print_header "LOG AGGREGATION SUMMARY" 70
    echo
    
    # Time range
    local first_time last_time
    first_time=$(find "$TEMP_DIR" -name "*.collected" -exec head -1 {} \; | head -1 | cut -d'|' -f1)
    last_time=$(find "$TEMP_DIR" -name "*.collected" -exec tail -1 {} \; | tail -1 | cut -d'|' -f1)
    
    echo -e "${BOLD_CYAN}Time Range:${NC}"
    echo "  From: $first_time"
    echo "  To:   $last_time"
    echo
    
    # Log counts by source
    echo -e "${BOLD_CYAN}Logs by Source:${NC}"
    for source in "${!LOG_COUNTS[@]}"; do
        printf "  %-20s %10d logs\n" "$source:" "${LOG_COUNTS[$source]}"
    done
    echo
    
    # Error counts
    echo -e "${BOLD_CYAN}Errors by Source:${NC}"
    local total_errors=0
    for source in "${!ERROR_COUNTS[@]}"; do
        printf "  %-20s %10d errors\n" "$source:" "${ERROR_COUNTS[$source]}"
        ((total_errors += ERROR_COUNTS[$source]))
    done
    echo "  Total Errors: $total_errors"
    echo
    
    # Top error messages
    echo -e "${BOLD_CYAN}Top 10 Error Messages:${NC}"
    find "$TEMP_DIR" -name "*.collected" -exec grep -h "ERROR" {} \; 2>/dev/null | \
        sed 's/[0-9]\+/N/g' | \
        sort | uniq -c | sort -rn | head -10 | \
        awk '{count=$1; $1=""; printf "  [%5d] %s\n", count, $0}'
}

show_statistics() {
    print_header "LOG STATISTICS" 70
    echo
    
    local total_lines=0
    local total_files=0
    
    for file in "$TEMP_DIR"/*.collected; do
        [[ -f "$file" ]] || continue
        ((total_files++))
        local lines=$(wc -l < "$file")
        ((total_lines += lines))
        
        local source=$(basename "$file" .collected)
        printf "%-30s %10d lines\n" "$source:" "$lines"
    done
    
    echo
    echo "Total Sources: $total_files"
    echo "Total Lines:   $total_lines"
    echo
    
    # Log level distribution
    echo -e "${BOLD_CYAN}Log Level Distribution:${NC}"
    find "$TEMP_DIR" -name "*.collected" -exec cat {} \; 2>/dev/null | \
        grep -oE "(ERROR|WARN|INFO|DEBUG|FATAL)" | \
        sort | uniq -c | sort -rn | \
        awk '{printf "  %-10s %10d (%5.1f%%)\n", $2":", $1, 100*$1/total}' total="$total_lines"
}

correlate_logs() {
    print_header "LOG CORRELATION ANALYSIS" 70
    echo
    
    echo -e "${BOLD_CYAN}Common Error Patterns Across Sources:${NC}"
    
    # Find common error patterns
    local temp_errors="$TEMP_DIR/all_errors"
    find "$TEMP_DIR" -name "*.collected" -exec grep -h "ERROR" {} \; 2>/dev/null | \
        sed 's/[0-9]\+/N/g' | sed 's/[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}/UUID/g' \
        > "$temp_errors"
    
    if [[ -s "$temp_errors" ]]; then
        sort "$temp_errors" | uniq -c | sort -rn | head -10 | \
            awk '{count=$1; $1=""; printf "  [%5d] %s\n", count, $0}'
    else
        echo "  No errors found"
    fi
    echo
    
    echo -e "${BOLD_CYAN}Timeline of Critical Events:${NC}"
    find "$TEMP_DIR" -name "*.collected" -exec grep -h "ERROR\|FATAL\|CRITICAL" {} \; 2>/dev/null | \
        grep -oE "^[^ ]+ [^ ]+ [^ ]+" | sort | uniq -c | \
        awk '{printf "  %s: %d events\n", substr($0, index($0,$2)), $1}' | head -20
}

################################################################################
# Alert Functions
################################################################################

send_alert() {
    local log_entry="$1"
    
    warning "ALERT: Pattern matched - $log_entry"
    
    if [[ -n "$ALERT_EMAIL" ]] && command_exists mail; then
        echo "Alert triggered at $(date)" | mail -s "Log Alert: $ALERT_PATTERN" "$ALERT_EMAIL"
    fi
}

################################################################################
# Output Functions
################################################################################

output_text() {
    local files=("$@")
    
    print_header "AGGREGATED LOGS" 70
    echo
    
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        
        local source=$(basename "$file" .collected)
        echo -e "${BOLD_CYAN}=== $source ===${NC}"
        
        while IFS= read -r line; do
            local parsed=$(parse_log_line "$line" "$source")
            if apply_filters "$parsed"; then
                IFS='|' read -r timestamp level source_name message <<< "$parsed"
                
                # Color by level
                case "$level" in
                    ERROR|FATAL)
                        echo -e "${RED}[$timestamp] [$level] $message${NC}"
                        ;;
                    WARN)
                        echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
                        ;;
                    *)
                        echo "[$timestamp] [$level] $message"
                        ;;
                esac
            fi
        done < "$file"
        echo
    done
}

output_json() {
    local files=("$@")
    
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"sources\": ["
    
    local first=true
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        
        [[ "$first" == false ]] && echo ","
        first=false
        
        local source=$(basename "$file" .collected)
        echo "    {"
        echo "      \"name\": \"$source\","
        echo "      \"logs\": ["
        
        local first_log=true
        while IFS= read -r line; do
            local parsed=$(parse_log_line "$line" "$source")
            if apply_filters "$parsed"; then
                IFS='|' read -r timestamp level source_name message <<< "$parsed"
                
                [[ "$first_log" == false ]] && echo ","
                first_log=false
                
                # Escape JSON
                message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
                echo "        {"
                echo "          \"timestamp\": \"$timestamp\","
                echo "          \"level\": \"$level\","
                echo "          \"message\": \"$message\""
                echo -n "        }"
            fi
        done < "$file"
        
        echo
        echo "      ]"
        echo -n "    }"
    done
    
    echo
    echo "  ]"
    echo "}"
}

output_csv() {
    local files=("$@")
    
    echo "Timestamp,Level,Source,Message"
    
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        
        local source=$(basename "$file" .collected)
        
        while IFS= read -r line; do
            local parsed=$(parse_log_line "$line" "$source")
            if apply_filters "$parsed"; then
                IFS='|' read -r timestamp level source_name message <<< "$parsed"
                
                # Escape CSV
                message=$(echo "$message" | sed 's/"/""/g')
                echo "\"$timestamp\",\"$level\",\"$source_name\",\"$message\""
            fi
        done < "$file"
    done
}

output_html() {
    local files=("$@")
    
    cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Log Aggregation Report</title>
    <style>
        body { font-family: monospace; margin: 20px; background: #1e1e1e; color: #d4d4d4; }
        h1 { color: #4ec9b0; }
        .log-entry { padding: 5px; margin: 2px 0; border-left: 3px solid #007acc; }
        .ERROR, .FATAL { background: #3d1e1e; border-left-color: #f44747; }
        .WARN { background: #3d3d1e; border-left-color: #dcdcaa; }
        .INFO { border-left-color: #4ec9b0; }
        .timestamp { color: #858585; }
        .level { font-weight: bold; margin: 0 10px; }
        .source { color: #4ec9b0; }
    </style>
</head>
<body>
    <h1>Log Aggregation Report</h1>
    <p>Generated: $(date)</p>
EOF
    
    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue
        
        local source=$(basename "$file" .collected)
        echo "    <h2>$source</h2>"
        
        while IFS= read -r line; do
            local parsed=$(parse_log_line "$line" "$source")
            if apply_filters "$parsed"; then
                IFS='|' read -r timestamp level source_name message <<< "$parsed"
                
                # HTML escape
                message=$(echo "$message" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                
                echo "    <div class=\"log-entry $level\">"
                echo "        <span class=\"timestamp\">$timestamp</span>"
                echo "        <span class=\"level\">$level</span>"
                echo "        <span class=\"source\">[$source_name]</span>"
                echo "        <span class=\"message\">$message</span>"
                echo "    </div>"
            fi
        done < "$file"
    done
    
    echo "</body>"
    echo "</html>"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Log Aggregator - Multi-Source Log Collection and Analysis${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -s, --source TYPE       Log source: file, syslog, journald, remote
    -f, --file PATH         Log file path (can specify multiple)
    -r, --remote HOST       Remote host via SSH
    -p, --pattern REGEX     Filter by regex pattern
    -l, --level LEVEL       Filter by log level (ERROR, WARN, INFO, DEBUG)
    --since TIME            Show logs since time
    --until TIME            Show logs until time
    -t, --tail              Follow logs in real-time
    -n, --lines N           Number of lines (default: 100)
    --aggregate             Aggregate and summarize logs
    --stats                 Show log statistics
    --correlate             Correlate logs across sources
    -o, --output FILE       Save output to file
    --format FORMAT         Output format: text, json, csv, html
    --alert PATTERN         Alert on pattern match
    --alert-email EMAIL     Email for alerts
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Aggregate error logs from file
    $(basename "$0") -s file -f /var/log/syslog --level ERROR
    
    # Follow journald logs
    $(basename "$0") -s journald --since "1 hour ago" --tail
    
    # Collect from remote host
    $(basename "$0") -s remote -r server.com -p "nginx" --stats
    
    # Aggregate multiple sources with JSON output
    $(basename "$0") -f /var/log/app1.log -f /var/log/app2.log --aggregate --format json
    
    # Real-time monitoring with alerts
    $(basename "$0") -s syslog --tail --alert "Failed" --alert-email admin@example.com

${CYAN}Log Sources:${NC}
    file      - Local log files
    syslog    - System log (/var/log/syslog)
    journald  - Systemd journal
    remote    - Remote host via SSH

${CYAN}Output Formats:${NC}
    text      - Human-readable colored text
    json      - JSON structured format
    csv       - CSV for spreadsheets
    html      - HTML report with styling

EOF
}

################################################################################
# Main Execution
################################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -s|--source)
            [[ -z "${2:-}" ]] && error_exit "Source type required" 2
            LOG_SOURCES+=("$2")
            shift 2
            ;;
        -f|--file)
            [[ -z "${2:-}" ]] && error_exit "File path required" 2
            LOG_FILES+=("$2")
            shift 2
            ;;
        -r|--remote)
            [[ -z "${2:-}" ]] && error_exit "Remote host required" 2
            REMOTE_HOSTS+=("$2")
            shift 2
            ;;
        -p|--pattern)
            [[ -z "${2:-}" ]] && error_exit "Pattern required" 2
            FILTER_PATTERN="$2"
            shift 2
            ;;
        -l|--level)
            [[ -z "${2:-}" ]] && error_exit "Level required" 2
            FILTER_LEVEL="$2"
            shift 2
            ;;
        --since)
            [[ -z "${2:-}" ]] && error_exit "Since time required" 2
            SINCE_TIME="$2"
            shift 2
            ;;
        --until)
            [[ -z "${2:-}" ]] && error_exit "Until time required" 2
            UNTIL_TIME="$2"
            shift 2
            ;;
        -t|--tail)
            TAIL_MODE=true
            shift
            ;;
        -n|--lines)
            [[ -z "${2:-}" ]] && error_exit "Line count required" 2
            NUM_LINES="$2"
            shift 2
            ;;
        --aggregate)
            AGGREGATE_MODE=true
            shift
            ;;
        --stats)
            SHOW_STATS=true
            shift
            ;;
        --correlate)
            CORRELATE_MODE=true
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --alert)
            [[ -z "${2:-}" ]] && error_exit "Alert pattern required" 2
            ALERT_PATTERN="$2"
            shift 2
            ;;
        --alert-email)
            [[ -z "${2:-}" ]] && error_exit "Alert email required" 2
            ALERT_EMAIL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Collect logs
collected_files=()

for source in "${LOG_SOURCES[@]}"; do
    case "$source" in
        file)
            [[ ${#LOG_FILES[@]} -eq 0 ]] && error_exit "No log files specified" 2
            ;;
        syslog)
            collected=$(collect_syslog)
            [[ -n "$collected" ]] && collected_files+=("$collected")
            ;;
        journald)
            collected=$(collect_journald)
            [[ -n "$collected" ]] && collected_files+=("$collected")
            ;;
        remote)
            [[ ${#REMOTE_HOSTS[@]} -eq 0 ]] && error_exit "No remote hosts specified" 2
            ;;
    esac
done

for file in "${LOG_FILES[@]}"; do
    collected=$(collect_file_logs "$file")
    [[ -n "$collected" ]] && collected_files+=("$collected")
done

for host in "${REMOTE_HOSTS[@]}"; do
    collected=$(collect_remote_logs "$host")
    [[ -n "$collected" ]] && collected_files+=("$collected")
done

[[ ${#collected_files[@]} -eq 0 ]] && error_exit "No logs collected" 1

# Process and output
if [[ -n "$OUTPUT_FILE" ]]; then
    exec > "$OUTPUT_FILE"
fi

if [[ "$AGGREGATE_MODE" == true ]]; then
    aggregate_logs
elif [[ "$SHOW_STATS" == true ]]; then
    show_statistics
elif [[ "$CORRELATE_MODE" == true ]]; then
    correlate_logs
else
    case "$OUTPUT_FORMAT" in
        json)
            output_json "${collected_files[@]}"
            ;;
        csv)
            output_csv "${collected_files[@]}"
            ;;
        html)
            output_html "${collected_files[@]}"
            ;;
        *)
            output_text "${collected_files[@]}"
            ;;
    esac
fi

# Wait for tail processes
if [[ "$TAIL_MODE" == true ]]; then
    wait
fi

