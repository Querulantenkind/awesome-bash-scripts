#!/bin/bash

################################################################################
# Script Name: system-monitor.sh
# Description: Comprehensive system resource monitoring with alerts and logging
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./system-monitor.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -w, --watch SECONDS     Continuous monitoring mode (refresh interval)
#   -a, --alert             Enable alerts when thresholds exceeded
#   -c, --cpu PERCENT       CPU alert threshold (default: 80)
#   -m, --memory PERCENT    Memory alert threshold (default: 80)
#   -d, --disk PERCENT      Disk alert threshold (default: 85)
#   -j, --json              Output in JSON format
#   -s, --summary           Show summary only
#   --no-color              Disable colored output
#
# Examples:
#   ./system-monitor.sh
#   ./system-monitor.sh --watch 5
#   ./system-monitor.sh --alert --cpu 90 --memory 85
#   ./system-monitor.sh --json --log /var/log/sysmonitor.log
#
# Dependencies:
#   - bc (for calculations)
#   - iostat (optional, for detailed I/O stats)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
################################################################################

set -euo pipefail

# Script directory and configuration
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
readonly NC='\033[0m' # No Color

# Configuration variables
VERBOSE=false
LOG_FILE=""
WATCH_MODE=false
WATCH_INTERVAL=5
ENABLE_ALERTS=false
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
JSON_OUTPUT=false
SUMMARY_ONLY=false
USE_COLOR=true

# Temporary file for previous stats (for delta calculations)
PREV_STATS_FILE="/tmp/.sysmonitor_$$"

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
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
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}System Monitor - Comprehensive Resource Monitoring${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -w, --watch SECONDS     Continuous monitoring (refresh every N seconds)
    -a, --alert             Enable threshold alerts
    -c, --cpu PERCENT       CPU alert threshold (default: 80)
    -m, --memory PERCENT    Memory alert threshold (default: 80)
    -d, --disk PERCENT      Disk alert threshold (default: 85)
    -j, --json              Output in JSON format
    -s, --summary           Show summary only
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Basic monitoring
    $SCRIPT_NAME

    # Continuous monitoring every 5 seconds
    $SCRIPT_NAME --watch 5

    # Enable alerts with custom thresholds
    $SCRIPT_NAME --alert --cpu 90 --memory 85 --disk 90

    # JSON output with logging
    $SCRIPT_NAME --json --log /var/log/sysmonitor.log

    # Watch mode with alerts
    $SCRIPT_NAME -w 3 -a -c 75 -m 80

${CYAN}Features:${NC}
    • CPU usage monitoring (per-core and overall)
    • Memory usage (RAM and Swap)
    • Disk usage (all mounted filesystems)
    • System load averages
    • Network statistics
    • Process count and top consumers
    • Uptime tracking
    • Configurable alert thresholds
    • JSON export capability
    • Continuous watch mode

EOF
}

check_dependencies() {
    local missing_deps=()
    
    for cmd in bc awk grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi
    
    # Check optional dependencies
    if ! command -v iostat &> /dev/null; then
        verbose "iostat not found - detailed I/O stats will be limited"
    fi
}

################################################################################
# Monitoring Functions
################################################################################

get_cpu_usage() {
    local cpu_stats
    cpu_stats=$(top -bn2 -d 0.5 | grep "Cpu(s)" | tail -1 | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    echo "$cpu_stats"
}

get_cpu_cores() {
    grep -c ^processor /proc/cpuinfo
}

get_memory_usage() {
    local total used free percent
    
    read -r total used free < <(free -m | awk '/^Mem:/ {print $2, $3, $4}')
    percent=$(echo "scale=2; ($used / $total) * 100" | bc)
    
    echo "$total $used $free $percent"
}

get_swap_usage() {
    local total used free percent
    
    read -r total used free < <(free -m | awk '/^Swap:/ {print $2, $3, $4}')
    
    if [[ "$total" -eq 0 ]]; then
        echo "0 0 0 0"
    else
        percent=$(echo "scale=2; ($used / $total) * 100" | bc)
        echo "$total $used $free $percent"
    fi
}

get_disk_usage() {
    df -h --output=source,fstype,size,used,avail,pcent,target | grep -v "tmpfs\|devtmpfs\|loop" | tail -n +2
}

get_load_average() {
    cat /proc/loadavg | awk '{print $1, $2, $3}'
}

get_uptime() {
    uptime -p | sed 's/up //'
}

get_process_count() {
    ps aux | wc -l
}

get_top_cpu_processes() {
    local count=${1:-5}
    ps aux --sort=-%cpu | head -n $((count + 1)) | tail -n +2 | awk '{print $2, $3, $11}'
}

get_top_memory_processes() {
    local count=${1:-5}
    ps aux --sort=-%mem | head -n $((count + 1)) | tail -n +2 | awk '{print $2, $4, $11}'
}

get_network_stats() {
    local interface rx_bytes tx_bytes
    
    # Get primary network interface
    interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -n "$interface" ]]; then
        rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)
        
        # Convert to MB
        rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
        tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
        
        echo "$interface $rx_mb $tx_mb"
    else
        echo "none 0 0"
    fi
}

################################################################################
# Alert Functions
################################################################################

check_alerts() {
    local cpu_usage="$1"
    local mem_percent="$2"
    local alerts=()
    
    # Check CPU threshold
    if (( $(echo "$cpu_usage >= $CPU_THRESHOLD" | bc -l) )); then
        alerts+=("CPU usage (${cpu_usage}%) exceeds threshold (${CPU_THRESHOLD}%)")
    fi
    
    # Check Memory threshold
    if (( $(echo "$mem_percent >= $MEMORY_THRESHOLD" | bc -l) )); then
        alerts+=("Memory usage (${mem_percent}%) exceeds threshold (${MEMORY_THRESHOLD}%)")
    fi
    
    # Check Disk thresholds
    while IFS= read -r line; do
        local percent=$(echo "$line" | awk '{print $6}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $7}')
        
        if (( percent >= DISK_THRESHOLD )); then
            alerts+=("Disk usage on $mount (${percent}%) exceeds threshold (${DISK_THRESHOLD}%)")
        fi
    done < <(get_disk_usage)
    
    # Display alerts
    if [[ ${#alerts[@]} -gt 0 ]]; then
        echo ""
        warning "ALERTS TRIGGERED:"
        for alert in "${alerts[@]}"; do
            echo -e "${RED}  ✗ $alert${NC}"
            log_message "ALERT: $alert"
        done
        echo ""
    fi
}

################################################################################
# Display Functions
################################################################################

display_header() {
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║             SYSTEM RESOURCE MONITOR                             ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Host:${NC}     $hostname"
    echo -e "${CYAN}Kernel:${NC}   $kernel"
    echo -e "${CYAN}Time:${NC}     $timestamp"
    echo -e "${CYAN}Uptime:${NC}   $(get_uptime)"
    echo ""
}

display_cpu_info() {
    local cpu_usage=$(get_cpu_usage)
    local cpu_cores=$(get_cpu_cores)
    local load_avg
    read -r load_1 load_5 load_15 < <(get_load_average)
    
    echo -e "${WHITE}━━━ CPU INFORMATION ━━━${NC}"
    echo -e "${CYAN}Cores:${NC}        $cpu_cores"
    echo -e "${CYAN}Usage:${NC}        ${cpu_usage}%"
    
    # Color code based on usage
    if (( $(echo "$cpu_usage >= 80" | bc -l) )); then
        echo -e "${CYAN}Status:${NC}       ${RED}HIGH${NC}"
    elif (( $(echo "$cpu_usage >= 50" | bc -l) )); then
        echo -e "${CYAN}Status:${NC}       ${YELLOW}MODERATE${NC}"
    else
        echo -e "${CYAN}Status:${NC}       ${GREEN}NORMAL${NC}"
    fi
    
    echo -e "${CYAN}Load Avg:${NC}     $load_1 (1m) | $load_5 (5m) | $load_15 (15m)"
    echo ""
}

display_memory_info() {
    read -r mem_total mem_used mem_free mem_percent < <(get_memory_usage)
    read -r swap_total swap_used swap_free swap_percent < <(get_swap_usage)
    
    echo -e "${WHITE}━━━ MEMORY INFORMATION ━━━${NC}"
    echo -e "${CYAN}RAM Total:${NC}    ${mem_total} MB"
    echo -e "${CYAN}RAM Used:${NC}     ${mem_used} MB (${mem_percent}%)"
    echo -e "${CYAN}RAM Free:${NC}     ${mem_free} MB"
    
    if [[ "$swap_total" -gt 0 ]]; then
        echo -e "${CYAN}Swap Total:${NC}   ${swap_total} MB"
        echo -e "${CYAN}Swap Used:${NC}    ${swap_used} MB (${swap_percent}%)"
    else
        echo -e "${CYAN}Swap:${NC}         Not configured"
    fi
    echo ""
}

display_disk_info() {
    echo -e "${WHITE}━━━ DISK USAGE ━━━${NC}"
    printf "${CYAN}%-20s %-8s %-8s %-8s %-8s %-6s %-s${NC}\n" "Device" "Type" "Size" "Used" "Avail" "Use%" "Mount"
    
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local fstype=$(echo "$line" | awk '{print $2}')
        local size=$(echo "$line" | awk '{print $3}')
        local used=$(echo "$line" | awk '{print $4}')
        local avail=$(echo "$line" | awk '{print $5}')
        local percent=$(echo "$line" | awk '{print $6}')
        local mount=$(echo "$line" | awk '{print $7}')
        
        # Color code based on usage
        local percent_num=$(echo "$percent" | tr -d '%')
        if (( percent_num >= 85 )); then
            percent="${RED}${percent}${NC}"
        elif (( percent_num >= 70 )); then
            percent="${YELLOW}${percent}${NC}"
        else
            percent="${GREEN}${percent}${NC}"
        fi
        
        printf "%-20s %-8s %-8s %-8s %-8s %-6b %-s\n" \
            "${device:0:20}" "$fstype" "$size" "$used" "$avail" "$percent" "$mount"
    done < <(get_disk_usage)
    echo ""
}

display_process_info() {
    local proc_count=$(get_process_count)
    
    echo -e "${WHITE}━━━ PROCESS INFORMATION ━━━${NC}"
    echo -e "${CYAN}Total Processes:${NC} $proc_count"
    echo ""
    
    if [[ "$SUMMARY_ONLY" == false ]]; then
        echo -e "${YELLOW}Top 5 CPU Consumers:${NC}"
        printf "${CYAN}%-8s %-8s %-s${NC}\n" "PID" "CPU%" "Command"
        while IFS= read -r line; do
            echo "$line" | awk '{printf "%-8s %-8s %-s\n", $1, $2"%", $3}'
        done < <(get_top_cpu_processes 5)
        echo ""
        
        echo -e "${YELLOW}Top 5 Memory Consumers:${NC}"
        printf "${CYAN}%-8s %-8s %-s${NC}\n" "PID" "MEM%" "Command"
        while IFS= read -r line; do
            echo "$line" | awk '{printf "%-8s %-8s %-s\n", $1, $2"%", $3}'
        done < <(get_top_memory_processes 5)
        echo ""
    fi
}

display_network_info() {
    read -r interface rx_mb tx_mb < <(get_network_stats)
    
    echo -e "${WHITE}━━━ NETWORK STATISTICS ━━━${NC}"
    echo -e "${CYAN}Interface:${NC}    $interface"
    echo -e "${CYAN}RX Total:${NC}     ${rx_mb} MB"
    echo -e "${CYAN}TX Total:${NC}     ${tx_mb} MB"
    echo ""
}

display_summary() {
    local cpu_usage=$(get_cpu_usage)
    read -r mem_total mem_used mem_free mem_percent < <(get_memory_usage)
    read -r load_1 load_5 load_15 < <(get_load_average)
    
    echo -e "${WHITE}╔════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        SYSTEM SUMMARY                  ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}CPU:${NC}      ${cpu_usage}%"
    echo -e "${CYAN}Memory:${NC}   ${mem_percent}% (${mem_used}/${mem_total} MB)"
    echo -e "${CYAN}Load:${NC}     $load_1, $load_5, $load_15"
    echo -e "${CYAN}Uptime:${NC}   $(get_uptime)"
    echo ""
}

generate_json_output() {
    local cpu_usage=$(get_cpu_usage)
    local cpu_cores=$(get_cpu_cores)
    read -r load_1 load_5 load_15 < <(get_load_average)
    read -r mem_total mem_used mem_free mem_percent < <(get_memory_usage)
    read -r swap_total swap_used swap_free swap_percent < <(get_swap_usage)
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local hostname=$(hostname)
    
    cat << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "uptime": "$(get_uptime)",
  "cpu": {
    "cores": $cpu_cores,
    "usage_percent": $cpu_usage,
    "load_average": {
      "1min": $load_1,
      "5min": $load_5,
      "15min": $load_15
    }
  },
  "memory": {
    "total_mb": $mem_total,
    "used_mb": $mem_used,
    "free_mb": $mem_free,
    "usage_percent": $mem_percent
  },
  "swap": {
    "total_mb": $swap_total,
    "used_mb": $swap_used,
    "free_mb": $swap_free,
    "usage_percent": $swap_percent
  },
  "processes": {
    "total": $(get_process_count)
  }
}
EOF
}

################################################################################
# Main Monitoring Function
################################################################################

run_monitoring() {
    if [[ "$JSON_OUTPUT" == true ]]; then
        generate_json_output
        log_message "Generated JSON output"
    elif [[ "$SUMMARY_ONLY" == true ]]; then
        display_summary
    else
        if [[ "$USE_COLOR" == true ]] && [[ "$WATCH_MODE" == true ]]; then
            clear
        fi
        
        display_header
        display_cpu_info
        display_memory_info
        display_disk_info
        display_process_info
        display_network_info
    fi
    
    # Check alerts if enabled
    if [[ "$ENABLE_ALERTS" == true ]] && [[ "$JSON_OUTPUT" == false ]]; then
        local cpu_usage=$(get_cpu_usage)
        read -r mem_total mem_used mem_free mem_percent < <(get_memory_usage)
        check_alerts "$cpu_usage" "$mem_percent"
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
        -l|--log)
            if [[ -z "${2:-}" ]]; then
                error_exit "--log requires a file path argument" 2
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        -w|--watch)
            if [[ -z "${2:-}" ]]; then
                error_exit "--watch requires a time interval argument" 2
            fi
            WATCH_MODE=true
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -a|--alert)
            ENABLE_ALERTS=true
            shift
            ;;
        -c|--cpu)
            if [[ -z "${2:-}" ]]; then
                error_exit "--cpu requires a percentage argument" 2
            fi
            CPU_THRESHOLD="$2"
            shift 2
            ;;
        -m|--memory)
            if [[ -z "${2:-}" ]]; then
                error_exit "--memory requires a percentage argument" 2
            fi
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        -d|--disk)
            if [[ -z "${2:-}" ]]; then
                error_exit "--disk requires a percentage argument" 2
            fi
            DISK_THRESHOLD="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        -s|--summary)
            SUMMARY_ONLY=true
            shift
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

# Cleanup on exit
cleanup() {
    [[ -f "$PREV_STATS_FILE" ]] && rm -f "$PREV_STATS_FILE"
}
trap cleanup EXIT INT TERM

# Check dependencies
check_dependencies

verbose "Starting system monitor..."
log_message "System monitoring started"

# Main loop
if [[ "$WATCH_MODE" == true ]]; then
    verbose "Watch mode enabled (interval: ${WATCH_INTERVAL}s)"
    
    while true; do
        run_monitoring
        
        if [[ "$JSON_OUTPUT" == false ]]; then
            echo -e "${CYAN}Refreshing in ${WATCH_INTERVAL}s... (Press Ctrl+C to exit)${NC}"
        fi
        
        sleep "$WATCH_INTERVAL"
    done
else
    run_monitoring
fi

log_message "System monitoring completed"

