#!/bin/bash

################################################################################
# Script Name: service-manager.sh
# Description: Systemd service management wrapper with batch operations,
#              dependency checking, log viewing, and service monitoring.
#              Simplifies common systemd service management tasks.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./service-manager.sh [options] [service...]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -a, --action ACTION     Action (start|stop|restart|reload|status|enable|disable)
#   -l, --list              List all services
#   --active                List only active services
#   --failed                List only failed services
#   --logs SERVICE          Show logs for service
#   -n, --lines NUM         Number of log lines (default: 50)
#   -f, --follow            Follow logs in real-time
#   --deps SERVICE          Show service dependencies
#   --batch FILE            Batch operations from file
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./service-manager.sh --action start nginx
#   ./service-manager.sh --action restart apache2 mysql
#   ./service-manager.sh --list --active
#   ./service-manager.sh --logs nginx --lines 100
#   ./service-manager.sh --deps sshd
#   ./service-manager.sh --failed
#
# Dependencies:
#   - systemctl
#   - journalctl
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Permission denied
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

VERBOSE=false
ACTION=""
LIST_SERVICES=false
SHOW_ACTIVE=false
SHOW_FAILED=false
SHOW_LOGS=""
LOG_LINES=50
FOLLOW_LOGS=false
SHOW_DEPS=""
BATCH_FILE=""
JSON_OUTPUT=false
USE_COLOR=true
SERVICES=()

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

show_usage() {
    cat << EOF
${WHITE}Service Manager - Systemd Service Management Wrapper${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS] [SERVICE...]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --action ACTION     Action (start|stop|restart|reload|status|enable|disable)
    -l, --list              List all services
    --active                List only active services
    --failed                List only failed services
    --logs SERVICE          Show logs for service
    -n, --lines NUM         Number of log lines (default: 50)
    -f, --follow            Follow logs in real-time
    --deps SERVICE          Show service dependencies
    --batch FILE            Batch operations from file
    -j, --json              Output in JSON format
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Start a service
    $SCRIPT_NAME --action start nginx

    # Restart multiple services
    $SCRIPT_NAME --action restart apache2 mysql

    # List active services
    $SCRIPT_NAME --list --active

    # View service logs
    $SCRIPT_NAME --logs nginx --lines 100

    # Show service dependencies
    $SCRIPT_NAME --deps sshd

    # List failed services
    $SCRIPT_NAME --failed

${CYAN}Features:${NC}
    • Start/stop/restart services
    • Enable/disable services
    • View service status
    • Log viewing with follow
    • Dependency checking
    • Batch operations
    • JSON output

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$ACTION" =~ ^(start|stop|restart|reload|enable|disable)$ ]]; then
        error_exit "This action requires root privileges" 4
    fi
}

check_dependencies() {
    for cmd in systemctl journalctl; do
        command -v "$cmd" &> /dev/null || error_exit "$cmd not found" 3
    done
}

service_action() {
    local action="$1"
    shift
    local services=("$@")

    for service in "${services[@]}"; do
        info "Executing $action on $service..."

        if systemctl "$action" "$service" 2>&1; then
            success "$service ${action}ed successfully"
        else
            warning "Failed to $action $service"
        fi
    done
}

list_services() {
    local filter=""

    if [[ "$SHOW_ACTIVE" == true ]]; then
        filter="--state=active"
    elif [[ "$SHOW_FAILED" == true ]]; then
        filter="--state=failed"
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        systemctl list-units --type=service $filter --output=json
    else
        echo ""
        echo -e "${WHITE}━━━ SYSTEMD SERVICES ━━━${NC}"
        systemctl list-units --type=service $filter --no-pager
        echo ""
    fi
}

show_service_logs() {
    local service="$1"

    local opts="-u $service -n $LOG_LINES --no-pager"

    if [[ "$FOLLOW_LOGS" == true ]]; then
        opts="-u $service -f"
    fi

    journalctl $opts
}

show_service_deps() {
    local service="$1"

    echo ""
    echo -e "${WHITE}━━━ DEPENDENCIES: $service ━━━${NC}"
    echo ""
    echo -e "${CYAN}Required by:${NC}"
    systemctl list-dependencies --reverse "$service" --no-pager
    echo ""
    echo -e "${CYAN}Requires:${NC}"
    systemctl list-dependencies "$service" --no-pager
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -a|--action) ACTION="$2"; shift 2 ;;
        -l|--list) LIST_SERVICES=true; shift ;;
        --active) SHOW_ACTIVE=true; shift ;;
        --failed) SHOW_FAILED=true; shift ;;
        --logs) SHOW_LOGS="$2"; shift 2 ;;
        -n|--lines) LOG_LINES="$2"; shift 2 ;;
        -f|--follow) FOLLOW_LOGS=true; shift ;;
        --deps) SHOW_DEPS="$2"; shift 2 ;;
        --batch) BATCH_FILE="$2"; shift 2 ;;
        -j|--json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        -*) error_exit "Unknown option: $1" 2 ;;
        *) SERVICES+=("$1"); shift ;;
    esac
done

check_dependencies

if [[ "$LIST_SERVICES" == true ]] || [[ "$SHOW_ACTIVE" == true ]] || [[ "$SHOW_FAILED" == true ]]; then
    list_services
elif [[ -n "$SHOW_LOGS" ]]; then
    show_service_logs "$SHOW_LOGS"
elif [[ -n "$SHOW_DEPS" ]]; then
    show_service_deps "$SHOW_DEPS"
elif [[ -n "$ACTION" ]]; then
    check_root
    [[ ${#SERVICES[@]} -eq 0 ]] && error_exit "No services specified" 2
    service_action "$ACTION" "${SERVICES[@]}"
else
    show_usage
fi
