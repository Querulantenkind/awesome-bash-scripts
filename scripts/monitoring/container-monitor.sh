#!/bin/bash

################################################################################
# Script Name: container-monitor.sh
# Description: Docker and Podman container monitoring with resource tracking,
#              health checks, log monitoring, and automatic restart capabilities.
#              Supports both Docker and Podman container runtimes.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./container-monitor.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -c, --container NAME    Monitor specific container
#   -a, --all               Monitor all containers
#   -w, --watch SECONDS     Continuous monitoring mode
#   -r, --runtime TYPE      Container runtime (docker|podman, auto-detect)
#   --cpu PERCENT           CPU threshold for alerts (default: 80)
#   --memory PERCENT        Memory threshold for alerts (default: 80)
#   --health               Show health status
#   --logs LINES           Show last N lines of logs
#   --restart              Auto-restart unhealthy containers
#   -j, --json             Output in JSON format
#   -l, --log FILE         Log output to file
#   --no-color             Disable colored output
#
# Examples:
#   ./container-monitor.sh --all
#   ./container-monitor.sh --container nginx --watch 5
#   ./container-monitor.sh --all --health --restart
#   ./container-monitor.sh --container redis --logs 50
#   ./container-monitor.sh --json --log /var/log/containers.log
#
# Dependencies:
#   - docker OR podman
#   - jq (optional, for JSON parsing)
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
CONTAINER_NAME=""
MONITOR_ALL=false
WATCH_MODE=false
WATCH_INTERVAL=5
RUNTIME=""
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
SHOW_HEALTH=false
LOG_LINES=0
AUTO_RESTART=false
JSON_OUTPUT=false
LOG_FILE=""
USE_COLOR=true

# Internal variables
declare -A CONTAINER_STATS

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
${WHITE}Container Monitor - Docker/Podman Monitoring Tool${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -c, --container NAME    Monitor specific container
    -a, --all               Monitor all containers
    -w, --watch SECONDS     Continuous monitoring (refresh interval)
    -r, --runtime TYPE      Container runtime (docker|podman, auto-detect)
    --cpu PERCENT           CPU threshold for alerts (default: 80)
    --memory PERCENT        Memory threshold for alerts (default: 80)
    --health                Show container health status
    --logs LINES            Show last N lines of container logs
    --restart               Auto-restart unhealthy containers
    -j, --json              Output in JSON format
    -l, --log FILE          Log output to file
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Monitor all containers
    $SCRIPT_NAME --all

    # Monitor specific container with watch mode
    $SCRIPT_NAME --container nginx --watch 5

    # Monitor with health checks and auto-restart
    $SCRIPT_NAME --all --health --restart

    # Show container logs
    $SCRIPT_NAME --container redis --logs 50

    # JSON output with logging
    $SCRIPT_NAME --all --json --log /var/log/containers.log

    # Monitor with custom thresholds
    $SCRIPT_NAME --all --cpu 90 --memory 85

${CYAN}Features:${NC}
    • Docker and Podman support
    • Resource usage monitoring (CPU, memory, network, disk)
    • Container health checks
    • Log monitoring
    • Automatic container restart
    • JSON export
    • Continuous watch mode
    • Alert thresholds

EOF
}

check_dependencies() {
    # Detect container runtime
    if [[ -z "$RUNTIME" ]]; then
        if command -v docker &> /dev/null; then
            RUNTIME="docker"
        elif command -v podman &> /dev/null; then
            RUNTIME="podman"
        else
            error_exit "Neither docker nor podman found. Please install one." 3
        fi
    else
        if ! command -v "$RUNTIME" &> /dev/null; then
            error_exit "Container runtime '$RUNTIME' not found" 3
        fi
    fi

    verbose "Using container runtime: $RUNTIME"

    # Check optional dependencies
    if ! command -v jq &> /dev/null; then
        verbose "jq not found - JSON parsing will be limited"
    fi
}

################################################################################
# Container Functions
################################################################################

get_container_list() {
    $RUNTIME ps --format "{{.Names}}" 2>/dev/null
}

get_all_containers() {
    $RUNTIME ps -a --format "{{.Names}}" 2>/dev/null
}

container_exists() {
    local name="$1"
    $RUNTIME ps -a --filter "name=^${name}$" --format "{{.Names}}" | grep -q "^${name}$"
}

is_container_running() {
    local name="$1"
    $RUNTIME ps --filter "name=^${name}$" --format "{{.Names}}" | grep -q "^${name}$"
}

get_container_status() {
    local name="$1"
    $RUNTIME ps -a --filter "name=^${name}$" --format "{{.Status}}" 2>/dev/null
}

get_container_health() {
    local name="$1"

    if command -v jq &> /dev/null; then
        $RUNTIME inspect "$name" 2>/dev/null | jq -r '.[0].State.Health.Status // "none"'
    else
        $RUNTIME inspect "$name" --format "{{.State.Health.Status}}" 2>/dev/null || echo "none"
    fi
}

get_container_stats() {
    local name="$1"

    # Get stats in no-stream mode
    local stats=$($RUNTIME stats --no-stream --format "{{.Container}}|{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}" "$name" 2>/dev/null)

    if [[ -n "$stats" ]]; then
        IFS='|' read -r container cpu mem mem_usage net_io block_io <<< "$stats"

        # Clean up percentages (remove % symbol)
        cpu="${cpu%\%}"
        mem="${mem%\%}"

        CONTAINER_STATS["name"]="$container"
        CONTAINER_STATS["cpu"]="$cpu"
        CONTAINER_STATS["memory"]="$mem"
        CONTAINER_STATS["memory_usage"]="$mem_usage"
        CONTAINER_STATS["network_io"]="$net_io"
        CONTAINER_STATS["block_io"]="$block_io"

        return 0
    fi

    return 1
}

get_container_info() {
    local name="$1"

    local info=$($RUNTIME inspect "$name" 2>/dev/null)

    if command -v jq &> /dev/null && [[ -n "$info" ]]; then
        local image=$(echo "$info" | jq -r '.[0].Config.Image')
        local created=$(echo "$info" | jq -r '.[0].Created')
        local state=$(echo "$info" | jq -r '.[0].State.Status')
        local restart_count=$(echo "$info" | jq -r '.[0].RestartCount')

        CONTAINER_STATS["image"]="$image"
        CONTAINER_STATS["created"]="$created"
        CONTAINER_STATS["state"]="$state"
        CONTAINER_STATS["restart_count"]="$restart_count"
    fi
}

get_container_logs() {
    local name="$1"
    local lines="${2:-50}"

    $RUNTIME logs --tail "$lines" "$name" 2>&1
}

restart_container() {
    local name="$1"

    warning "Restarting container: $name"

    if $RUNTIME restart "$name" &> /dev/null; then
        success "Container $name restarted successfully"
        log_message "Restarted container: $name"
        return 0
    else
        warning "Failed to restart container: $name"
        log_message "ERROR: Failed to restart container: $name"
        return 1
    fi
}

################################################################################
# Monitoring Functions
################################################################################

monitor_container() {
    local name="$1"

    if ! container_exists "$name"; then
        warning "Container not found: $name"
        return 1
    fi

    # Get container stats
    if ! get_container_stats "$name"; then
        warning "Could not get stats for container: $name"
        return 1
    fi

    # Get additional info
    get_container_info "$name"

    # Get status and health
    local status=$(get_container_status "$name")
    local health=$(get_container_health "$name")

    CONTAINER_STATS["status"]="$status"
    CONTAINER_STATS["health"]="$health"

    # Display container information
    if [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo -e "${WHITE}━━━ CONTAINER: $name ━━━${NC}"
        echo -e "${CYAN}Status:${NC}       $status"

        if [[ "$health" != "none" ]]; then
            case "$health" in
                healthy)
                    echo -e "${CYAN}Health:${NC}       ${GREEN}$health${NC}"
                    ;;
                unhealthy)
                    echo -e "${CYAN}Health:${NC}       ${RED}$health${NC}"
                    ;;
                starting)
                    echo -e "${CYAN}Health:${NC}       ${YELLOW}$health${NC}"
                    ;;
                *)
                    echo -e "${CYAN}Health:${NC}       $health"
                    ;;
            esac
        fi

        [[ -n "${CONTAINER_STATS[image]:-}" ]] && echo -e "${CYAN}Image:${NC}        ${CONTAINER_STATS[image]}"
        [[ -n "${CONTAINER_STATS[restart_count]:-}" ]] && echo -e "${CYAN}Restarts:${NC}     ${CONTAINER_STATS[restart_count]}"

        echo ""
        echo -e "${WHITE}━━━ RESOURCE USAGE ━━━${NC}"

        # CPU usage with color coding
        local cpu="${CONTAINER_STATS[cpu]}"
        local cpu_int=${cpu%.*}
        if [[ "$cpu_int" =~ ^[0-9]+$ ]]; then
            if (( cpu_int >= CPU_THRESHOLD )); then
                echo -e "${CYAN}CPU:${NC}          ${RED}${cpu}%${NC}"
            elif (( cpu_int >= 50 )); then
                echo -e "${CYAN}CPU:${NC}          ${YELLOW}${cpu}%${NC}"
            else
                echo -e "${CYAN}CPU:${NC}          ${GREEN}${cpu}%${NC}"
            fi
        else
            echo -e "${CYAN}CPU:${NC}          ${cpu}"
        fi

        # Memory usage with color coding
        local mem="${CONTAINER_STATS[memory]}"
        local mem_int=${mem%.*}
        if [[ "$mem_int" =~ ^[0-9]+$ ]]; then
            if (( mem_int >= MEMORY_THRESHOLD )); then
                echo -e "${CYAN}Memory:${NC}       ${RED}${mem}%${NC}"
            elif (( mem_int >= 50 )); then
                echo -e "${CYAN}Memory:${NC}       ${YELLOW}${mem}%${NC}"
            else
                echo -e "${CYAN}Memory:${NC}       ${GREEN}${mem}%${NC}"
            fi
        else
            echo -e "${CYAN}Memory:${NC}       ${mem}"
        fi

        echo -e "${CYAN}Mem Usage:${NC}    ${CONTAINER_STATS[memory_usage]}"
        echo -e "${CYAN}Network I/O:${NC}  ${CONTAINER_STATS[network_io]}"
        echo -e "${CYAN}Block I/O:${NC}    ${CONTAINER_STATS[block_io]}"
        echo ""

        # Show logs if requested
        if [[ $LOG_LINES -gt 0 ]]; then
            echo -e "${WHITE}━━━ CONTAINER LOGS (last $LOG_LINES lines) ━━━${NC}"
            get_container_logs "$name" "$LOG_LINES"
            echo ""
        fi
    fi

    # Check thresholds
    check_container_thresholds "$name"

    log_message "Monitored container $name: CPU=${CONTAINER_STATS[cpu]}%, MEM=${CONTAINER_STATS[memory]}%, Health=$health"
}

monitor_all_containers() {
    local containers=$(get_container_list)

    if [[ -z "$containers" ]]; then
        warning "No running containers found"
        return 1
    fi

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${WHITE}║             CONTAINER RESOURCE MONITOR                          ║${NC}"
        echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        printf "${CYAN}%-20s %-12s %-8s %-8s %-20s %-s${NC}\n" \
            "NAME" "STATUS" "CPU%" "MEM%" "MEMORY USAGE" "HEALTH"
        echo "────────────────────────────────────────────────────────────────────────────"
    fi

    local container_array=()
    while IFS= read -r container; do
        container_array+=("$container")

        if get_container_stats "$container"; then
            local status=$(get_container_status "$container" | awk '{print $1}')
            local health=$(get_container_health "$container")

            if [[ "$JSON_OUTPUT" != true ]]; then
                # Color code health status
                local health_colored
                case "$health" in
                    healthy)
                        health_colored="${GREEN}$health${NC}"
                        ;;
                    unhealthy)
                        health_colored="${RED}$health${NC}"
                        ;;
                    starting)
                        health_colored="${YELLOW}$health${NC}"
                        ;;
                    *)
                        health_colored="$health"
                        ;;
                esac

                printf "%-20s %-12s %-8s %-8s %-20s %-b\n" \
                    "${container:0:20}" \
                    "${status:0:12}" \
                    "${CONTAINER_STATS[cpu]}%" \
                    "${CONTAINER_STATS[memory]}%" \
                    "${CONTAINER_STATS[memory_usage]:0:20}" \
                    "$health_colored"
            fi

            # Check thresholds
            check_container_thresholds "$container"
        fi
    done <<< "$containers"

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo ""
        info "Total running containers: ${#container_array[@]}"
    fi
}

check_container_thresholds() {
    local name="$1"
    local cpu="${CONTAINER_STATS[cpu]}"
    local mem="${CONTAINER_STATS[memory]}"
    local health="${CONTAINER_STATS[health]}"

    local alert_triggered=false

    # Clean up CPU and memory values
    cpu="${cpu%\%}"
    mem="${mem%\%}"
    local cpu_int=${cpu%.*}
    local mem_int=${mem%.*}

    # Check CPU threshold
    if [[ "$cpu_int" =~ ^[0-9]+$ ]] && (( cpu_int >= CPU_THRESHOLD )); then
        warning "Container $name: CPU threshold exceeded (${cpu}% >= ${CPU_THRESHOLD}%)"
        alert_triggered=true
        log_message "ALERT: Container $name CPU threshold exceeded (${cpu}%)"
    fi

    # Check memory threshold
    if [[ "$mem_int" =~ ^[0-9]+$ ]] && (( mem_int >= MEMORY_THRESHOLD )); then
        warning "Container $name: Memory threshold exceeded (${mem}% >= ${MEMORY_THRESHOLD}%)"
        alert_triggered=true
        log_message "ALERT: Container $name Memory threshold exceeded (${mem}%)"
    fi

    # Check health status
    if [[ "$SHOW_HEALTH" == true ]] && [[ "$health" == "unhealthy" ]]; then
        warning "Container $name is unhealthy"
        alert_triggered=true
        log_message "ALERT: Container $name is unhealthy"

        if [[ "$AUTO_RESTART" == true ]]; then
            restart_container "$name"
        fi
    fi
}

generate_json_output() {
    local containers=$(get_container_list)
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"runtime\": \"$RUNTIME\","
    echo "  \"containers\": ["

    local first=true
    while IFS= read -r container; do
        if get_container_stats "$container"; then
            local status=$(get_container_status "$container")
            local health=$(get_container_health "$container")

            [[ "$first" != true ]] && echo ","

            cat << EOF
    {
      "name": "$container",
      "status": "$status",
      "health": "$health",
      "cpu_percent": "${CONTAINER_STATS[cpu]}",
      "memory_percent": "${CONTAINER_STATS[memory]}",
      "memory_usage": "${CONTAINER_STATS[memory_usage]}",
      "network_io": "${CONTAINER_STATS[network_io]}",
      "block_io": "${CONTAINER_STATS[block_io]}"
    }
EOF
            first=false
        fi
    done <<< "$containers"

    echo ""
    echo "  ]"
    echo "}"
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
        -c|--container)
            [[ -z "${2:-}" ]] && error_exit "--container requires a name" 2
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -a|--all)
            MONITOR_ALL=true
            shift
            ;;
        -w|--watch)
            [[ -z "${2:-}" ]] && error_exit "--watch requires an interval" 2
            WATCH_MODE=true
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -r|--runtime)
            [[ -z "${2:-}" ]] && error_exit "--runtime requires a type" 2
            RUNTIME="$2"
            shift 2
            ;;
        --cpu)
            [[ -z "${2:-}" ]] && error_exit "--cpu requires a percentage" 2
            CPU_THRESHOLD="$2"
            shift 2
            ;;
        --memory)
            [[ -z "${2:-}" ]] && error_exit "--memory requires a percentage" 2
            MEMORY_THRESHOLD="$2"
            shift 2
            ;;
        --health)
            SHOW_HEALTH=true
            shift
            ;;
        --logs)
            [[ -z "${2:-}" ]] && error_exit "--logs requires a line count" 2
            LOG_LINES="$2"
            shift 2
            ;;
        --restart)
            AUTO_RESTART=true
            shift
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

verbose "Container monitor started"
log_message "Container monitor started (runtime: $RUNTIME)"

# Main monitoring logic
if [[ "$WATCH_MODE" == true ]]; then
    verbose "Watch mode enabled (interval: ${WATCH_INTERVAL}s)"

    while true; do
        if [[ "$USE_COLOR" == true ]] && [[ "$JSON_OUTPUT" != true ]]; then
            clear
        fi

        if [[ -n "$CONTAINER_NAME" ]]; then
            monitor_container "$CONTAINER_NAME"
        elif [[ "$MONITOR_ALL" == true ]]; then
            if [[ "$JSON_OUTPUT" == true ]]; then
                generate_json_output
            else
                monitor_all_containers
            fi
        else
            monitor_all_containers
        fi

        if [[ "$JSON_OUTPUT" != true ]]; then
            echo -e "${CYAN}Refreshing in ${WATCH_INTERVAL}s... (Press Ctrl+C to exit)${NC}"
        fi

        sleep "$WATCH_INTERVAL"
    done
else
    # Single run
    if [[ -n "$CONTAINER_NAME" ]]; then
        monitor_container "$CONTAINER_NAME"
    elif [[ "$MONITOR_ALL" == true ]]; then
        if [[ "$JSON_OUTPUT" == true ]]; then
            generate_json_output
        else
            monitor_all_containers
        fi
    else
        monitor_all_containers
    fi
fi

log_message "Container monitoring completed"
