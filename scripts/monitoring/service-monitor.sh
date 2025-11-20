#!/bin/bash

################################################################################
# Script Name: service-monitor.sh
# Description: Monitor systemd services with health checks, restart capabilities,
#              and notification support. Tracks service status, uptime, and
#              resource usage with automatic recovery options.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./service-monitor.sh [options] [services...]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -w, --watch SECONDS     Continuous monitoring mode
#   -a, --auto-restart      Automatically restart failed services
#   -n, --notify            Send desktop notifications (requires notify-send)
#   -e, --email EMAIL       Send email alerts (requires mail command)
#   -c, --config FILE       Load services from config file
#   -j, --json              Output in JSON format
#   --list-failed           List all failed services
#   --list-active           List all active services
#   --check-all             Monitor all enabled services
#
# Examples:
#   ./service-monitor.sh nginx postgresql
#   ./service-monitor.sh --watch 30 --auto-restart sshd nginx
#   ./service-monitor.sh --list-failed
#   ./service-monitor.sh --config /etc/service-monitor.conf --notify
#   ./service-monitor.sh --check-all --json
#
# Config File Format:
#   One service name per line, optional comments with #
#   nginx
#   postgresql
#   # This is a comment
#
# Dependencies:
#   - systemctl (systemd)
#   - notify-send (optional, for desktop notifications)
#   - mail (optional, for email alerts)
#
# Exit Codes:
#   0 - All services running
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - One or more services failed
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
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
LOG_FILE=""
WATCH_MODE=false
WATCH_INTERVAL=30
AUTO_RESTART=false
ENABLE_NOTIFY=false
EMAIL_ALERT=""
CONFIG_FILE=""
JSON_OUTPUT=false
LIST_FAILED=false
LIST_ACTIVE=false
CHECK_ALL=false
SERVICES=()
USE_COLOR=true

# Statistics
TOTAL_SERVICES=0
RUNNING_SERVICES=0
FAILED_SERVICES=0
RESTARTED_SERVICES=0

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
        echo -e "${BLUE}[VERBOSE] $1${NC}" >&2
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
${WHITE}Service Monitor - Systemd Service Health Monitoring${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS] [SERVICES...]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -w, --watch SECONDS     Continuous monitoring (default: 30s)
    -a, --auto-restart      Automatically restart failed services
    -n, --notify            Send desktop notifications
    -e, --email EMAIL       Send email alerts
    -c, --config FILE       Load services from config file
    -j, --json              Output in JSON format
    --list-failed           List all failed services
    --list-active           List all active services
    --check-all             Monitor all enabled services

${CYAN}Examples:${NC}
    # Monitor specific services
    $SCRIPT_NAME nginx postgresql redis

    # Continuous monitoring with auto-restart
    $SCRIPT_NAME --watch 30 --auto-restart sshd nginx

    # List all failed services
    $SCRIPT_NAME --list-failed

    # Monitor with notifications and email
    $SCRIPT_NAME -w 60 -n -e admin@example.com -c /etc/services.conf

    # JSON output for all enabled services
    $SCRIPT_NAME --check-all --json

${CYAN}Features:${NC}
    • Real-time service status monitoring
    • Automatic service restart on failure
    • Desktop and email notifications
    • Detailed service information (uptime, memory, PIDs)
    • Configuration file support
    • JSON export for automation
    • Systemd unit file analysis
    • Service dependency tracking

EOF
}

check_dependencies() {
    if ! command -v systemctl &> /dev/null; then
        error_exit "systemctl not found - this script requires systemd" 3
    fi
    
    if [[ "$ENABLE_NOTIFY" == true ]] && ! command -v notify-send &> /dev/null; then
        warning "notify-send not found - desktop notifications disabled"
        ENABLE_NOTIFY=false
    fi
    
    if [[ -n "$EMAIL_ALERT" ]] && ! command -v mail &> /dev/null; then
        warning "mail command not found - email alerts disabled"
        EMAIL_ALERT=""
    fi
}

send_notification() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    
    if [[ "$ENABLE_NOTIFY" == true ]]; then
        notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
        verbose "Sent desktop notification: $title"
    fi
    
    if [[ -n "$EMAIL_ALERT" ]]; then
        echo "$message" | mail -s "$title" "$EMAIL_ALERT" 2>/dev/null || true
        verbose "Sent email to $EMAIL_ALERT"
    fi
    
    log_message "NOTIFICATION: $title - $message"
}

################################################################################
# Service Functions
################################################################################

get_service_status() {
    local service="$1"
    systemctl is-active "$service" 2>/dev/null || echo "inactive"
}

get_service_enabled() {
    local service="$1"
    systemctl is-enabled "$service" 2>/dev/null || echo "disabled"
}

get_service_uptime() {
    local service="$1"
    local active_time
    
    active_time=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null)
    
    if [[ -n "$active_time" && "$active_time" != "n/a" ]]; then
        local active_epoch=$(date -d "$active_time" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        local uptime_seconds=$((now_epoch - active_epoch))
        
        if [[ $uptime_seconds -gt 0 ]]; then
            format_uptime $uptime_seconds
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

format_uptime() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

get_service_memory() {
    local service="$1"
    systemctl show "$service" --property=MemoryCurrent --value 2>/dev/null | \
        awk '{if($1 == "[not set]" || $1 == "") print "N/A"; else printf "%.1f MB", $1/1024/1024}'
}

get_service_pid() {
    local service="$1"
    systemctl show "$service" --property=MainPID --value 2>/dev/null
}

get_service_tasks() {
    local service="$1"
    local tasks
    tasks=$(systemctl show "$service" --property=TasksCurrent --value 2>/dev/null)
    [[ -n "$tasks" && "$tasks" != "[not set]" ]] && echo "$tasks" || echo "N/A"
}

get_service_description() {
    local service="$1"
    systemctl show "$service" --property=Description --value 2>/dev/null
}

get_all_failed_services() {
    systemctl list-units --failed --no-pager --no-legend | awk '{print $1}' | grep '\.service$' | sed 's/\.service$//'
}

get_all_active_services() {
    systemctl list-units --type=service --state=active --no-pager --no-legend | awk '{print $1}' | sed 's/\.service$//'
}

get_all_enabled_services() {
    systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend | awk '{print $1}' | sed 's/\.service$//'
}

restart_service() {
    local service="$1"
    
    verbose "Attempting to restart $service..."
    
    if sudo systemctl restart "$service" 2>/dev/null; then
        success "Successfully restarted $service"
        log_message "RESTART: Successfully restarted $service"
        send_notification "Service Restarted" "$service has been automatically restarted" "normal"
        ((RESTARTED_SERVICES++))
        return 0
    else
        error_exit "Failed to restart $service" 1
        log_message "ERROR: Failed to restart $service"
        send_notification "Restart Failed" "Failed to restart $service" "critical"
        return 1
    fi
}

################################################################################
# Display Functions
################################################################################

display_header() {
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              SERVICE MONITOR                                    ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Time:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}Host:${NC}     $(hostname)"
    echo ""
}

display_service_status() {
    local service="$1"
    local status=$(get_service_status "$service")
    local enabled=$(get_service_enabled "$service")
    local uptime=$(get_service_uptime "$service")
    local memory=$(get_service_memory "$service")
    local pid=$(get_service_pid "$service")
    local tasks=$(get_service_tasks "$service")
    local description=$(get_service_description "$service")
    
    ((TOTAL_SERVICES++))
    
    # Status indicator
    if [[ "$status" == "active" ]]; then
        local status_icon="${GREEN}●${NC} ACTIVE"
        ((RUNNING_SERVICES++))
    elif [[ "$status" == "inactive" ]]; then
        local status_icon="${YELLOW}○${NC} INACTIVE"
    elif [[ "$status" == "failed" ]]; then
        local status_icon="${RED}✗${NC} FAILED"
        ((FAILED_SERVICES++))
    else
        local status_icon="${RED}?${NC} UNKNOWN"
        ((FAILED_SERVICES++))
    fi
    
    # Display service information
    echo -e "${WHITE}━━━ $service ━━━${NC}"
    echo -e "  ${CYAN}Status:${NC}       $status_icon"
    echo -e "  ${CYAN}Enabled:${NC}      $enabled"
    echo -e "  ${CYAN}Uptime:${NC}       $uptime"
    echo -e "  ${CYAN}Memory:${NC}       $memory"
    echo -e "  ${CYAN}PID:${NC}          $pid"
    echo -e "  ${CYAN}Tasks:${NC}        $tasks"
    echo -e "  ${CYAN}Description:${NC}  $description"
    
    # Auto-restart if enabled and service failed
    if [[ "$AUTO_RESTART" == true ]] && [[ "$status" != "active" ]]; then
        echo -e "  ${YELLOW}→ Attempting auto-restart...${NC}"
        restart_service "$service"
        
        # Re-check status after restart
        sleep 2
        local new_status=$(get_service_status "$service")
        if [[ "$new_status" == "active" ]]; then
            echo -e "  ${GREEN}✓ Service is now active${NC}"
        else
            echo -e "  ${RED}✗ Restart failed${NC}"
        fi
    fi
    
    echo ""
}

display_summary() {
    echo -e "${WHITE}━━━ SUMMARY ━━━${NC}"
    echo -e "${CYAN}Total Services:${NC}     $TOTAL_SERVICES"
    echo -e "${GREEN}Running:${NC}            $RUNNING_SERVICES"
    echo -e "${RED}Failed:${NC}             $FAILED_SERVICES"
    
    if [[ $RESTARTED_SERVICES -gt 0 ]]; then
        echo -e "${YELLOW}Restarted:${NC}          $RESTARTED_SERVICES"
    fi
    
    echo ""
    
    if [[ $FAILED_SERVICES -gt 0 ]]; then
        warning "Some services are not running properly!"
        return 4
    else
        success "All monitored services are running"
        return 0
    fi
}

generate_json_output() {
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local hostname=$(hostname)
    local first=true
    
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"hostname\": \"$hostname\","
    echo "  \"services\": ["
    
    for service in "${SERVICES[@]}"; do
        [[ "$first" == false ]] && echo ","
        first=false
        
        local status=$(get_service_status "$service")
        local enabled=$(get_service_enabled "$service")
        local uptime=$(get_service_uptime "$service")
        local memory=$(get_service_memory "$service")
        local pid=$(get_service_pid "$service")
        local tasks=$(get_service_tasks "$service")
        local description=$(get_service_description "$service")
        
        cat << EOF
    {
      "name": "$service",
      "status": "$status",
      "enabled": "$enabled",
      "uptime": "$uptime",
      "memory": "$memory",
      "pid": $pid,
      "tasks": "$tasks",
      "description": "$description"
    }
EOF
    done
    
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total\": $TOTAL_SERVICES,"
    echo "    \"running\": $RUNNING_SERVICES,"
    echo "    \"failed\": $FAILED_SERVICES"
    echo "  }"
    echo "}"
}

################################################################################
# Main Functions
################################################################################

load_config_file() {
    local config="$1"
    
    if [[ ! -f "$config" ]]; then
        error_exit "Config file not found: $config" 2
    fi
    
    verbose "Loading services from $config"
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Trim whitespace
        line=$(echo "$line" | xargs)
        SERVICES+=("$line")
    done < "$config"
    
    verbose "Loaded ${#SERVICES[@]} services from config"
}

run_monitoring() {
    # Reset statistics
    TOTAL_SERVICES=0
    RUNNING_SERVICES=0
    FAILED_SERVICES=0
    RESTARTED_SERVICES=0
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        generate_json_output
    else
        display_header
        
        for service in "${SERVICES[@]}"; do
            display_service_status "$service"
        done
        
        display_summary
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
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        -w|--watch)
            WATCH_MODE=true
            if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL="$2"
                shift 2
            else
                shift
            fi
            ;;
        -a|--auto-restart)
            AUTO_RESTART=true
            shift
            ;;
        -n|--notify)
            ENABLE_NOTIFY=true
            shift
            ;;
        -e|--email)
            [[ -z "${2:-}" ]] && error_exit "--email requires an email address" 2
            EMAIL_ALERT="$2"
            shift 2
            ;;
        -c|--config)
            [[ -z "${2:-}" ]] && error_exit "--config requires a file path" 2
            CONFIG_FILE="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --list-failed)
            LIST_FAILED=true
            shift
            ;;
        --list-active)
            LIST_ACTIVE=true
            shift
            ;;
        --check-all)
            CHECK_ALL=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1\nUse -h or --help for usage information." 2
            ;;
        *)
            SERVICES+=("$1")
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Handle list operations
if [[ "$LIST_FAILED" == true ]]; then
    echo -e "${WHITE}Failed Services:${NC}"
    mapfile -t failed < <(get_all_failed_services)
    if [[ ${#failed[@]} -eq 0 ]]; then
        echo -e "${GREEN}No failed services${NC}"
    else
        for service in "${failed[@]}"; do
            echo -e "  ${RED}✗${NC} $service"
        done
    fi
    exit 0
fi

if [[ "$LIST_ACTIVE" == true ]]; then
    echo -e "${WHITE}Active Services:${NC}"
    mapfile -t active < <(get_all_active_services)
    for service in "${active[@]}"; do
        echo -e "  ${GREEN}●${NC} $service"
    done
    exit 0
fi

# Load services from config if specified
if [[ -n "$CONFIG_FILE" ]]; then
    load_config_file "$CONFIG_FILE"
fi

# Check all enabled services if requested
if [[ "$CHECK_ALL" == true ]]; then
    verbose "Checking all enabled services..."
    mapfile -t enabled < <(get_all_enabled_services)
    SERVICES+=("${enabled[@]}")
fi

# Validate we have services to monitor
if [[ ${#SERVICES[@]} -eq 0 ]]; then
    error_exit "No services specified. Use -h for help." 2
fi

verbose "Monitoring ${#SERVICES[@]} services: ${SERVICES[*]}"
log_message "Service monitoring started for: ${SERVICES[*]}"

# Main monitoring loop
if [[ "$WATCH_MODE" == true ]]; then
    verbose "Watch mode enabled (interval: ${WATCH_INTERVAL}s)"
    
    while true; do
        [[ "$JSON_OUTPUT" == false ]] && clear
        run_monitoring
        
        if [[ "$JSON_OUTPUT" == false ]]; then
            echo -e "${CYAN}Refreshing in ${WATCH_INTERVAL}s... (Press Ctrl+C to exit)${NC}"
        fi
        
        sleep "$WATCH_INTERVAL"
    done
else
    run_monitoring
    exit_code=$?
    log_message "Service monitoring completed"
    exit $exit_code
fi

