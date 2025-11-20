#!/bin/bash

################################################################################
# Script Name: disk-health-monitor.sh
# Description: Monitor disk health using S.M.A.R.T. data and system metrics
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./disk-health-monitor.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -d, --disk DEVICE       Monitor specific disk (e.g., /dev/sda)
#   -a, --all               Monitor all available disks
#   -w, --watch SECONDS     Continuous monitoring mode
#   -j, --json              Output in JSON format
#   -c, --csv               Output in CSV format
#   --alert                 Enable alerts for disk issues
#   --temp-threshold TEMP   Temperature alert threshold in Celsius (default: 50)
#   --health-only           Show only health status
#   --no-color              Disable colored output
#
# Examples:
#   ./disk-health-monitor.sh --all
#   ./disk-health-monitor.sh --disk /dev/sda --verbose
#   ./disk-health-monitor.sh --watch 60 --alert
#   ./disk-health-monitor.sh --json --log /var/log/disk-health.log
#
# Dependencies:
#   - smartmontools (smartctl)
#   - lsblk
#
# Exit Codes:
#   0 - Success, all disks healthy
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Disk health warning/failure detected
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
WATCH_INTERVAL=60
JSON_OUTPUT=false
CSV_OUTPUT=false
ENABLE_ALERTS=false
TEMP_THRESHOLD=50
HEALTH_ONLY=false
USE_COLOR=true
MONITOR_ALL=false
SPECIFIC_DISK=""

# Tracking variables
DISKS_WITH_ISSUES=0
EXIT_CODE=0

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
${WHITE}Disk Health Monitor - S.M.A.R.T. Monitoring and Disk Health Analysis${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -d, --disk DEVICE       Monitor specific disk (e.g., /dev/sda)
    -a, --all               Monitor all available disks (default)
    -w, --watch SECONDS     Continuous monitoring mode
    -j, --json              Output in JSON format
    -c, --csv               Output in CSV format
    --alert                 Enable alerts for disk issues
    --temp-threshold TEMP   Temperature alert threshold (default: 50°C)
    --health-only           Show only health status summary
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Monitor all disks
    $SCRIPT_NAME --all

    # Monitor specific disk with verbose output
    $SCRIPT_NAME --disk /dev/sda --verbose

    # Continuous monitoring with alerts
    $SCRIPT_NAME --watch 60 --alert

    # JSON output for integration
    $SCRIPT_NAME --json --log /var/log/disk-health.log

    # Quick health check
    $SCRIPT_NAME --health-only

${CYAN}S.M.A.R.T. Attributes Monitored:${NC}
    - Overall health status
    - Reallocated sectors count
    - Current pending sectors
    - Uncorrectable sectors
    - Temperature
    - Power-on hours
    - Spin retry count
    - Drive errors

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in smartctl lsblk; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}\nInstall with: sudo apt install smartmontools util-linux" 3
    fi

    # Check if running as root for smartctl
    if [[ $EUID -ne 0 ]]; then
        warning "Not running as root. Some S.M.A.R.T. data may be unavailable."
        verbose "Run with sudo for complete disk information"
    fi
}

################################################################################
# Disk Discovery Functions
################################################################################

get_all_disks() {
    verbose "Discovering all available disks..."

    # Get all block devices (excluding loop, ram, etc.)
    lsblk -ndo NAME,TYPE | grep -E "disk" | awk '{print "/dev/"$1}' | sort
}

is_disk_smart_capable() {
    local disk="$1"

    if smartctl -i "$disk" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

################################################################################
# S.M.A.R.T. Monitoring Functions
################################################################################

get_smart_health() {
    local disk="$1"

    # Get overall health status
    smartctl -H "$disk" 2>/dev/null | grep -i "SMART overall-health" | awk -F: '{print $2}' | tr -d ' '
}

get_smart_attribute() {
    local disk="$1"
    local attribute_id="$2"

    # Get specific SMART attribute value
    smartctl -A "$disk" 2>/dev/null | grep "^ *${attribute_id} " | awk '{print $10}'
}

get_disk_temperature() {
    local disk="$1"

    # Try to get temperature from SMART data
    local temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $10}')

    # Alternative: try with -l scttempsts
    if [[ -z "$temp" ]]; then
        temp=$(smartctl -l scttempsts "$disk" 2>/dev/null | grep "Current Temperature:" | awk '{print $3}')
    fi

    echo "${temp:-N/A}"
}

get_disk_power_on_hours() {
    local disk="$1"

    smartctl -A "$disk" 2>/dev/null | grep "Power_On_Hours" | awk '{print $10}'
}

get_disk_info() {
    local disk="$1"

    smartctl -i "$disk" 2>/dev/null
}

################################################################################
# Analysis Functions
################################################################################

analyze_disk() {
    local disk="$1"
    local disk_status="HEALTHY"
    local issues=()

    verbose "Analyzing disk: $disk"

    # Check if disk supports SMART
    if ! is_disk_smart_capable "$disk"; then
        warning "Disk $disk does not support S.M.A.R.T. or is not accessible"
        return 1
    fi

    # Get basic info
    local model=$(smartctl -i "$disk" 2>/dev/null | grep "Device Model:" | cut -d: -f2- | xargs)
    local serial=$(smartctl -i "$disk" 2>/dev/null | grep "Serial Number:" | cut -d: -f2- | xargs)
    local capacity=$(lsblk -bdn -o SIZE "$disk" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "N/A")

    # Get health status
    local health=$(get_smart_health "$disk")

    # Get critical SMART attributes
    local reallocated=$(get_smart_attribute "$disk" 5)
    local pending=$(get_smart_attribute "$disk" 197)
    local uncorrectable=$(get_smart_attribute "$disk" 198)
    local temperature=$(get_disk_temperature "$disk")
    local power_hours=$(get_disk_power_on_hours "$disk")

    # Analyze health
    if [[ "$health" != "PASSED" ]] && [[ -n "$health" ]]; then
        disk_status="FAILED"
        issues+=("Overall health: $health")
    fi

    # Check reallocated sectors
    if [[ -n "$reallocated" ]] && [[ "$reallocated" -gt 0 ]]; then
        disk_status="WARNING"
        issues+=("Reallocated sectors: $reallocated")
    fi

    # Check pending sectors
    if [[ -n "$pending" ]] && [[ "$pending" -gt 0 ]]; then
        disk_status="WARNING"
        issues+=("Pending sectors: $pending")
    fi

    # Check uncorrectable sectors
    if [[ -n "$uncorrectable" ]] && [[ "$uncorrectable" -gt 0 ]]; then
        disk_status="CRITICAL"
        issues+=("Uncorrectable sectors: $uncorrectable")
    fi

    # Check temperature
    if [[ "$temperature" != "N/A" ]] && [[ "$temperature" -gt "$TEMP_THRESHOLD" ]]; then
        disk_status="WARNING"
        issues+=("Temperature: ${temperature}°C (threshold: ${TEMP_THRESHOLD}°C)")
    fi

    # Output results based on format
    if [[ "$JSON_OUTPUT" == true ]]; then
        output_json_disk "$disk" "$model" "$serial" "$capacity" "$health" "$reallocated" "$pending" "$uncorrectable" "$temperature" "$power_hours" "$disk_status" "${issues[*]:-}"
    elif [[ "$CSV_OUTPUT" == true ]]; then
        output_csv_disk "$disk" "$model" "$serial" "$capacity" "$health" "$reallocated" "$pending" "$uncorrectable" "$temperature" "$power_hours" "$disk_status"
    elif [[ "$HEALTH_ONLY" == true ]]; then
        output_health_only "$disk" "$disk_status" "${issues[*]:-}"
    else
        output_detailed_disk "$disk" "$model" "$serial" "$capacity" "$health" "$reallocated" "$pending" "$uncorrectable" "$temperature" "$power_hours" "$disk_status" "${issues[@]+"${issues[@]}"}"
    fi

    # Track issues
    if [[ "$disk_status" != "HEALTHY" ]]; then
        ((DISKS_WITH_ISSUES++))
        EXIT_CODE=4

        if [[ "$ENABLE_ALERTS" == true ]]; then
            send_alert "$disk" "$disk_status" "${issues[*]:-}"
        fi
    fi

    log_message "Disk $disk: Status=$disk_status, Issues=${#issues[@]}"
}

################################################################################
# Output Functions
################################################################################

output_detailed_disk() {
    local disk="$1"
    local model="$2"
    local serial="$3"
    local capacity="$4"
    local health="$5"
    local reallocated="$6"
    local pending="$7"
    local uncorrectable="$8"
    local temperature="$9"
    local power_hours="${10}"
    local disk_status="${11}"
    shift 11
    local issues=("$@")

    echo ""
    echo "=========================================="
    if [[ "$disk_status" == "HEALTHY" ]]; then
        success "Disk: $disk [${disk_status}]"
    elif [[ "$disk_status" == "WARNING" ]]; then
        warning "Disk: $disk [${disk_status}]"
    else
        error_exit "Disk: $disk [${disk_status}]" 0
    fi
    echo "=========================================="
    echo "Model:               $model"
    echo "Serial Number:       $serial"
    echo "Capacity:            $capacity"
    echo "Health Status:       $health"
    echo "Temperature:         ${temperature}°C"
    echo "Power-On Hours:      ${power_hours:-N/A}"
    echo "Reallocated Sectors: ${reallocated:-0}"
    echo "Pending Sectors:     ${pending:-0}"
    echo "Uncorrectable:       ${uncorrectable:-0}"

    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        echo "Issues Detected:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
    fi
}

output_health_only() {
    local disk="$1"
    local disk_status="$2"
    local issues="$3"

    if [[ "$disk_status" == "HEALTHY" ]]; then
        success "$disk: $disk_status"
    elif [[ "$disk_status" == "WARNING" ]]; then
        warning "$disk: $disk_status - $issues"
    else
        if [[ "$USE_COLOR" == true ]]; then
            echo -e "${RED}✗ $disk: $disk_status - $issues${NC}"
        else
            echo "✗ $disk: $disk_status - $issues"
        fi
    fi
}

output_json_disk() {
    local disk="$1"
    local model="$2"
    local serial="$3"
    local capacity="$4"
    local health="$5"
    local reallocated="$6"
    local pending="$7"
    local uncorrectable="$8"
    local temperature="$9"
    local power_hours="${10}"
    local disk_status="${11}"
    local issues="${12}"

    cat << EOF
{
  "disk": "$disk",
  "model": "$model",
  "serial": "$serial",
  "capacity": "$capacity",
  "health": "$health",
  "temperature": "$temperature",
  "power_on_hours": "${power_hours:-0}",
  "reallocated_sectors": "${reallocated:-0}",
  "pending_sectors": "${pending:-0}",
  "uncorrectable_sectors": "${uncorrectable:-0}",
  "status": "$disk_status",
  "issues": "$issues",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

output_csv_disk() {
    local disk="$1"
    local model="$2"
    local serial="$3"
    local capacity="$4"
    local health="$5"
    local reallocated="$6"
    local pending="$7"
    local uncorrectable="$8"
    local temperature="$9"
    local power_hours="${10}"
    local disk_status="${11}"

    # Print header if first disk
    if [[ ! -f /tmp/.disk_health_csv_header_$$ ]]; then
        echo "Disk,Model,Serial,Capacity,Health,Temperature,PowerOnHours,Reallocated,Pending,Uncorrectable,Status,Timestamp"
        touch /tmp/.disk_health_csv_header_$$
    fi

    echo "$disk,\"$model\",\"$serial\",$capacity,$health,$temperature,${power_hours:-0},${reallocated:-0},${pending:-0},${uncorrectable:-0},$disk_status,$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

send_alert() {
    local disk="$1"
    local status="$2"
    local issues="$3"

    local alert_message="DISK ALERT: $disk is $status - Issues: $issues"

    warning "$alert_message"
    log_message "$alert_message"

    # Send system notification if available
    if command -v notify-send &>/dev/null; then
        notify-send -u critical "Disk Health Alert" "$alert_message"
    fi

    # Log to syslog if available
    if command -v logger &>/dev/null; then
        logger -t disk-health-monitor -p user.crit "$alert_message"
    fi
}

################################################################################
# Main Monitoring Function
################################################################################

monitor_disks() {
    local disks_to_monitor=()

    # Determine which disks to monitor
    if [[ -n "$SPECIFIC_DISK" ]]; then
        disks_to_monitor=("$SPECIFIC_DISK")
    else
        readarray -t disks_to_monitor < <(get_all_disks)
    fi

    if [[ ${#disks_to_monitor[@]} -eq 0 ]]; then
        error_exit "No disks found to monitor" 1
    fi

    verbose "Found ${#disks_to_monitor[@]} disk(s) to monitor"

    # Start JSON array if JSON output
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "["
    fi

    # Monitor each disk
    local first=true
    for disk in "${disks_to_monitor[@]}"; do
        if [[ "$JSON_OUTPUT" == true ]] && [[ "$first" == false ]]; then
            echo ","
        fi

        analyze_disk "$disk"
        first=false
    done

    # Close JSON array if JSON output
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo ""
        echo "]"
    fi

    # Summary
    if [[ "$JSON_OUTPUT" == false ]] && [[ "$CSV_OUTPUT" == false ]]; then
        echo ""
        echo "=========================================="
        if [[ $DISKS_WITH_ISSUES -eq 0 ]]; then
            success "All disks are healthy"
        else
            warning "$DISKS_WITH_ISSUES disk(s) have issues"
        fi
        echo "=========================================="
    fi
}

main() {
    check_dependencies

    if [[ "$WATCH_MODE" == true ]]; then
        info "Starting continuous monitoring (interval: ${WATCH_INTERVAL}s, press Ctrl+C to stop)..."

        while true; do
            clear
            DISKS_WITH_ISSUES=0
            EXIT_CODE=0
            monitor_disks
            sleep "$WATCH_INTERVAL"
        done
    else
        monitor_disks
    fi
}

################################################################################
# Argument Parsing
################################################################################

# No arguments = monitor all disks
if [[ $# -eq 0 ]]; then
    MONITOR_ALL=true
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
        -d|--disk)
            SPECIFIC_DISK="$2"
            shift 2
            ;;
        -a|--all)
            MONITOR_ALL=true
            shift
            ;;
        -w|--watch)
            WATCH_MODE=true
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -c|--csv)
            CSV_OUTPUT=true
            shift
            ;;
        --alert)
            ENABLE_ALERTS=true
            shift
            ;;
        --temp-threshold)
            TEMP_THRESHOLD="$2"
            shift 2
            ;;
        --health-only)
            HEALTH_ONLY=true
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
# Cleanup
################################################################################

cleanup() {
    # Remove temporary files
    rm -f /tmp/.disk_health_csv_header_$$
}

trap cleanup EXIT

################################################################################
# Main Execution
################################################################################

main

exit $EXIT_CODE
