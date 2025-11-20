#!/bin/bash

################################################################################
# Script Name: process-monitor.sh
# Description: Advanced process resource monitoring with CPU, memory, thread
#              tracking, alerts, and process management capabilities. Features
#              process tree visualization and automatic resource-based actions.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./process-monitor.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -p, --pid PID           Monitor specific process by PID
#   -n, --name NAME         Monitor processes by name
#   -w, --watch SECONDS     Continuous monitoring mode
#   -c, --cpu PERCENT       CPU threshold for alerts (default: 80)
#   -m, --memory PERCENT    Memory threshold for alerts (default: 80)
#   -t, --top NUM           Show top N processes (default: 10)
#   -j, --json              Output in JSON format
#   -l, --log FILE          Log output to file
#   --tree                  Display process tree
#   --kill                  Kill process if threshold exceeded
#   --restart CMD           Restart command if threshold exceeded
#   --threads               Show thread information
#   --no-color              Disable colored output
#
# Examples:
#   ./process-monitor.sh --name nginx
#   ./process-monitor.sh --pid 1234 --watch 5
#   ./process-monitor.sh --top 20 --cpu 90
#   ./process-monitor.sh --name apache --kill --cpu 95
#   ./process-monitor.sh --tree --json --log /var/log/process.log
#
# Dependencies:
#   - ps
#   - top
#   - pgrep (optional)
#   - pstree (optional, for tree view)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
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
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
MONITOR_PID=""
PROCESS_NAME=""
WATCH_MODE=false
WATCH_INTERVAL=5
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
TOP_COUNT=10
JSON_OUTPUT=false
LOG_FILE=""
SHOW_TREE=false
KILL_ON_THRESHOLD=false
RESTART_COMMAND=""
SHOW_THREADS=false
USE_COLOR=true

# Internal variables
declare -A PROCESS_DATA
ALERT_TRIGGERED=false

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
${WHITE}Process Monitor - Advanced Process Resource Monitoring${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -p, --pid PID           Monitor specific process by PID
    -n, --name NAME         Monitor processes by name
    -w, --watch SECONDS     Continuous monitoring (refresh interval)
    -c, --cpu PERCENT       CPU threshold for alerts (default: 80)
    -m, --memory PERCENT    Memory threshold for alerts (default: 80)
    -t, --top NUM           Show top N processes (default: 10)
    -j, --json              Output in JSON format
    -l, --log FILE          Log output to file
    --tree                  Display process tree visualization
    --kill                  Kill process if threshold exceeded
    --restart CMD           Restart command if killed
    --threads               Show thread information
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Monitor specific process by name
    $SCRIPT_NAME --name nginx --watch 5

    # Monitor by PID with alerts
    $SCRIPT_NAME --pid 1234 --cpu 90 --memory 85

    # Show top CPU consumers
    $SCRIPT_NAME --top 20

    # Kill process if CPU exceeds threshold
    $SCRIPT_NAME --name rogue_process --kill --cpu 95

    # Process tree with JSON output
    $SCRIPT_NAME --tree --json

    # Monitor with restart capability
    $SCRIPT_NAME --name httpd --restart "systemctl start httpd"

${CYAN}Features:${NC}
    • Real-time CPU and memory monitoring
    • Process tree visualization
    • Thread count tracking
    • Configurable alert thresholds
    • Automatic process termination
    • Process restart capabilities
    • Top resource consumers
    • JSON export
    • Continuous watch mode

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in ps top awk grep; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi

    # Check optional dependencies
    if [[ "$SHOW_TREE" == true ]] && ! command -v pstree &> /dev/null; then
        warning "pstree not found - tree view will be limited"
    fi
}

################################################################################
# Process Information Functions
################################################################################

get_process_info() {
    local pid="$1"

    if ! ps -p "$pid" &> /dev/null; then
        return 1
    fi

    local info=$(ps -p "$pid" -o pid,ppid,user,comm,%cpu,%mem,vsz,rss,stat,start,time,nlwp,args --no-headers)

    if [[ -n "$info" ]]; then
        read -r pid ppid user comm cpu mem vsz rss stat start time nlwp args <<< "$info"

        PROCESS_DATA["pid"]="$pid"
        PROCESS_DATA["ppid"]="$ppid"
        PROCESS_DATA["user"]="$user"
        PROCESS_DATA["comm"]="$comm"
        PROCESS_DATA["cpu"]="$cpu"
        PROCESS_DATA["mem"]="$mem"
        PROCESS_DATA["vsz"]="$vsz"
        PROCESS_DATA["rss"]="$rss"
        PROCESS_DATA["stat"]="$stat"
        PROCESS_DATA["start"]="$start"
        PROCESS_DATA["time"]="$time"
        PROCESS_DATA["threads"]="$nlwp"
        PROCESS_DATA["args"]="$args"

        return 0
    fi

    return 1
}

get_process_tree() {
    local pid="$1"

    if command -v pstree &> /dev/null; then
        pstree -p -a -l "$pid" 2>/dev/null
    else
        ps -p "$pid" -o pid,ppid,cmd --no-headers
        ps --ppid "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || true
    fi
}

get_process_children() {
    local pid="$1"
    ps --ppid "$pid" -o pid --no-headers 2>/dev/null || true
}

get_process_by_name() {
    local name="$1"
    pgrep -f "$name" 2>/dev/null || ps aux | grep -v grep | grep "$name" | awk '{print $2}'
}

get_top_processes() {
    local count="${1:-10}"
    local sort_by="${2:-cpu}"

    case "$sort_by" in
        cpu)
            ps aux --sort=-%cpu | head -n $((count + 1))
            ;;
        mem|memory)
            ps aux --sort=-%mem | head -n $((count + 1))
            ;;
        threads)
            ps aux --sort=-nlwp | head -n $((count + 1))
            ;;
    esac
}

get_process_threads() {
    local pid="$1"
    ps -T -p "$pid" 2>/dev/null
}

calculate_cpu_usage() {
    local pid="$1"
    local interval="${2:-1}"

    # Get initial CPU time
    local cpu1=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')

    sleep "$interval"

    # Get second CPU time
    local cpu2=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ')

    echo "$cpu2"
}

################################################################################
# Monitoring Functions
################################################################################

monitor_single_process() {
    local pid="$1"

    if ! get_process_info "$pid"; then
        warning "Process $pid not found or terminated"
        return 1
    fi

    # Display process information
    if [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo -e "${WHITE}━━━ PROCESS INFORMATION ━━━${NC}"
        echo -e "${CYAN}PID:${NC}          ${PROCESS_DATA[pid]}"
        echo -e "${CYAN}Parent PID:${NC}   ${PROCESS_DATA[ppid]}"
        echo -e "${CYAN}User:${NC}         ${PROCESS_DATA[user]}"
        echo -e "${CYAN}Command:${NC}      ${PROCESS_DATA[comm]}"
        echo -e "${CYAN}Arguments:${NC}    ${PROCESS_DATA[args]}"
        echo -e "${CYAN}Status:${NC}       ${PROCESS_DATA[stat]}"
        echo -e "${CYAN}Started:${NC}      ${PROCESS_DATA[start]}"
        echo -e "${CYAN}CPU Time:${NC}     ${PROCESS_DATA[time]}"
        echo ""

        echo -e "${WHITE}━━━ RESOURCE USAGE ━━━${NC}"

        # CPU usage with color coding
        local cpu="${PROCESS_DATA[cpu]}"
        local cpu_int=${cpu%.*}
        if (( cpu_int >= CPU_THRESHOLD )); then
            echo -e "${CYAN}CPU:${NC}          ${RED}${cpu}%${NC}"
        elif (( cpu_int >= 50 )); then
            echo -e "${CYAN}CPU:${NC}          ${YELLOW}${cpu}%${NC}"
        else
            echo -e "${CYAN}CPU:${NC}          ${GREEN}${cpu}%${NC}"
        fi

        # Memory usage with color coding
        local mem="${PROCESS_DATA[mem]}"
        local mem_int=${mem%.*}
        if (( mem_int >= MEMORY_THRESHOLD )); then
            echo -e "${CYAN}Memory:${NC}       ${RED}${mem}%${NC}"
        elif (( mem_int >= 50 )); then
            echo -e "${CYAN}Memory:${NC}       ${YELLOW}${mem}%${NC}"
        else
            echo -e "${CYAN}Memory:${NC}       ${GREEN}${mem}%${NC}"
        fi

        echo -e "${CYAN}VSZ:${NC}          ${PROCESS_DATA[vsz]} KB"
        echo -e "${CYAN}RSS:${NC}          ${PROCESS_DATA[rss]} KB"
        echo -e "${CYAN}Threads:${NC}      ${PROCESS_DATA[threads]}"
        echo ""

        # Show thread details if requested
        if [[ "$SHOW_THREADS" == true ]]; then
            echo -e "${WHITE}━━━ THREAD INFORMATION ━━━${NC}"
            get_process_threads "$pid"
            echo ""
        fi

        # Show process tree if requested
        if [[ "$SHOW_TREE" == true ]]; then
            echo -e "${WHITE}━━━ PROCESS TREE ━━━${NC}"
            get_process_tree "$pid"
            echo ""
        fi
    fi

    # Check thresholds and trigger alerts
    check_thresholds "$pid"

    log_message "Monitored PID $pid: CPU=${PROCESS_DATA[cpu]}%, MEM=${PROCESS_DATA[mem]}%"
}

monitor_processes_by_name() {
    local name="$1"

    verbose "Searching for processes matching: $name"

    local pids=$(get_process_by_name "$name")

    if [[ -z "$pids" ]]; then
        warning "No processes found matching: $name"
        return 1
    fi

    info "Found $(echo "$pids" | wc -w) process(es) matching: $name"

    for pid in $pids; do
        monitor_single_process "$pid"
    done
}

check_thresholds() {
    local pid="$1"
    local cpu="${PROCESS_DATA[cpu]}"
    local mem="${PROCESS_DATA[mem]}"
    local cpu_int=${cpu%.*}
    local mem_int=${mem%.*}

    ALERT_TRIGGERED=false

    # Check CPU threshold
    if (( cpu_int >= CPU_THRESHOLD )); then
        warning "CPU threshold exceeded: ${cpu}% >= ${CPU_THRESHOLD}%"
        ALERT_TRIGGERED=true
        log_message "ALERT: PID $pid CPU threshold exceeded (${cpu}%)"
    fi

    # Check memory threshold
    if (( mem_int >= MEMORY_THRESHOLD )); then
        warning "Memory threshold exceeded: ${mem}% >= ${MEMORY_THRESHOLD}%"
        ALERT_TRIGGERED=true
        log_message "ALERT: PID $pid Memory threshold exceeded (${mem}%)"
    fi

    # Take action if threshold exceeded
    if [[ "$ALERT_TRIGGERED" == true ]]; then
        if [[ "$KILL_ON_THRESHOLD" == true ]]; then
            kill_process "$pid"

            if [[ -n "$RESTART_COMMAND" ]]; then
                restart_process
            fi
        fi
    fi
}

kill_process() {
    local pid="$1"

    warning "Killing process $pid (${PROCESS_DATA[comm]})"

    if kill -15 "$pid" 2>/dev/null; then
        sleep 2

        # Check if process still exists
        if ps -p "$pid" &> /dev/null; then
            warning "Process didn't respond to SIGTERM, sending SIGKILL"
            kill -9 "$pid" 2>/dev/null || true
        fi

        success "Process $pid terminated"
        log_message "Killed process $pid (${PROCESS_DATA[comm]})"
    else
        error_exit "Failed to kill process $pid" 1
    fi
}

restart_process() {
    info "Restarting process: $RESTART_COMMAND"

    if eval "$RESTART_COMMAND" 2>&1 | tee -a "$LOG_FILE"; then
        success "Process restarted successfully"
        log_message "Process restarted: $RESTART_COMMAND"
    else
        warning "Failed to restart process"
        log_message "WARNING: Process restart failed"
    fi
}

display_top_processes() {
    local count="$TOP_COUNT"

    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║          TOP $count PROCESSES BY CPU USAGE                        ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    printf "${CYAN}%-8s %-10s %-8s %-8s %-8s %-s${NC}\n" "PID" "USER" "CPU%" "MEM%" "THREADS" "COMMAND"
    echo "────────────────────────────────────────────────────────────────────"

    get_top_processes "$count" "cpu" | tail -n +2 | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local user=$(echo "$line" | awk '{print $1}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local threads=$(ps -p "$pid" -o nlwp --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
        local cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=$9=$10=""; print $0}' | sed 's/^[[:space:]]*//')

        printf "%-8s %-10s %-8s %-8s %-8s %-s\n" "$pid" "${user:0:10}" "${cpu}%" "${mem}%" "$threads" "${cmd:0:40}"
    done

    echo ""

    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║          TOP $count PROCESSES BY MEMORY USAGE                     ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    printf "${CYAN}%-8s %-10s %-8s %-8s %-8s %-s${NC}\n" "PID" "USER" "CPU%" "MEM%" "RSS(KB)" "COMMAND"
    echo "────────────────────────────────────────────────────────────────────"

    get_top_processes "$count" "mem" | tail -n +2 | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local user=$(echo "$line" | awk '{print $1}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local rss=$(echo "$line" | awk '{print $6}')
        local cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=$9=$10=""; print $0}' | sed 's/^[[:space:]]*//')

        printf "%-8s %-10s %-8s %-8s %-8s %-s\n" "$pid" "${user:0:10}" "${cpu}%" "${mem}%" "$rss" "${cmd:0:40}"
    done

    echo ""
}

generate_json_output() {
    local pid="$1"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    cat << EOF
{
  "timestamp": "$timestamp",
  "process": {
    "pid": ${PROCESS_DATA[pid]},
    "ppid": ${PROCESS_DATA[ppid]},
    "user": "${PROCESS_DATA[user]}",
    "command": "${PROCESS_DATA[comm]}",
    "arguments": "${PROCESS_DATA[args]}",
    "status": "${PROCESS_DATA[stat]}",
    "started": "${PROCESS_DATA[start]}",
    "cpu_time": "${PROCESS_DATA[time]}",
    "cpu_percent": ${PROCESS_DATA[cpu]},
    "memory_percent": ${PROCESS_DATA[mem]},
    "vsz_kb": ${PROCESS_DATA[vsz]},
    "rss_kb": ${PROCESS_DATA[rss]},
    "threads": ${PROCESS_DATA[threads]}
  },
  "thresholds": {
    "cpu_threshold": $CPU_THRESHOLD,
    "memory_threshold": $MEMORY_THRESHOLD,
    "alert_triggered": $ALERT_TRIGGERED
  }
}
EOF
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
        -p|--pid)
            [[ -z "${2:-}" ]] && error_exit "--pid requires a PID argument" 2
            MONITOR_PID="$2"
            shift 2
            ;;
        -n|--name)
            [[ -z "${2:-}" ]] && error_exit "--name requires a process name" 2
            PROCESS_NAME="$2"
            shift 2
            ;;
        -w|--watch)
            [[ -z "${2:-}" ]] && error_exit "--watch requires an interval" 2
            WATCH_MODE=true
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -c|--cpu)
            [[ -z "${2:-}" ]] && error_exit "--cpu requires a percentage" 2
            CPU_THRESHOLD="$2"
            shift 2
            ;;
        -m|--memory)
            [[ -z "${2:-}" ]] && error_exit "--memory requires a percentage" 2
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        -t|--top)
            [[ -z "${2:-}" ]] && error_exit "--top requires a number" 2
            TOP_COUNT="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        -l|--log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        --tree)
            SHOW_TREE=true
            shift
            ;;
        --kill)
            KILL_ON_THRESHOLD=true
            shift
            ;;
        --restart)
            [[ -z "${2:-}" ]] && error_exit "--restart requires a command" 2
            RESTART_COMMAND="$2"
            shift 2
            ;;
        --threads)
            SHOW_THREADS=true
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

check_dependencies

verbose "Process monitor started"
log_message "Process monitor started"

# Main monitoring logic
if [[ "$WATCH_MODE" == true ]]; then
    verbose "Watch mode enabled (interval: ${WATCH_INTERVAL}s)"

    while true; do
        if [[ "$USE_COLOR" == true ]]; then
            clear
        fi

        if [[ -n "$MONITOR_PID" ]]; then
            monitor_single_process "$MONITOR_PID"
        elif [[ -n "$PROCESS_NAME" ]]; then
            monitor_processes_by_name "$PROCESS_NAME"
        else
            display_top_processes
        fi

        if [[ "$JSON_OUTPUT" != true ]]; then
            echo -e "${CYAN}Refreshing in ${WATCH_INTERVAL}s... (Press Ctrl+C to exit)${NC}"
        fi

        sleep "$WATCH_INTERVAL"
    done
else
    # Single run
    if [[ -n "$MONITOR_PID" ]]; then
        monitor_single_process "$MONITOR_PID"

        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_json_output "$MONITOR_PID"
        fi
    elif [[ -n "$PROCESS_NAME" ]]; then
        monitor_processes_by_name "$PROCESS_NAME"
    else
        display_top_processes
    fi
fi

log_message "Process monitoring completed"
