#!/bin/bash

################################################################################
# Script Name: fail2ban-manager.sh
# Description: Fail2ban configuration and management tool. Manage banned IPs,
#              configure jails, view statistics, and export ban lists.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./fail2ban-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -s, --status            Show fail2ban status
#   -j, --jail NAME         Specify jail name
#   --list                  List all jails
#   --banned                List banned IPs
#   --ban IP                Ban specific IP
#   --unban IP              Unban specific IP
#   --stats                 Show ban statistics
#   --export FILE           Export banned IPs to file
#   --json                  Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./fail2ban-manager.sh --status
#   ./fail2ban-manager.sh --list
#   ./fail2ban-manager.sh --banned --jail sshd
#   ./fail2ban-manager.sh --ban 192.168.1.100 --jail sshd
#   ./fail2ban-manager.sh --stats --json
#
# Dependencies:
#   - fail2ban-client
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Permission denied
################################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

VERBOSE=false
SHOW_STATUS=false
JAIL_NAME=""
LIST_JAILS=false
SHOW_BANNED=false
BAN_IP=""
UNBAN_IP=""
SHOW_STATS=false
EXPORT_FILE=""
JSON_OUTPUT=false
USE_COLOR=true

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
${WHITE}Fail2ban Manager - Fail2ban Configuration Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -s, --status            Show fail2ban status
    -j, --jail NAME         Specify jail name
    --list                  List all jails
    --banned                List banned IPs
    --ban IP                Ban specific IP
    --unban IP              Unban specific IP
    --stats                 Show ban statistics
    --export FILE           Export banned IPs to file
    --json                  Output in JSON format
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Show fail2ban status
    $(basename "$0") --status

    # List all jails
    $(basename "$0") --list

    # List banned IPs in sshd jail
    $(basename "$0") --banned --jail sshd

    # Ban an IP
    $(basename "$0") --ban 192.168.1.100 --jail sshd

    # Unban an IP
    $(basename "$0") --unban 192.168.1.100 --jail sshd

    # Show statistics
    $(basename "$0") --stats --json

    # Export banned IPs
    $(basename "$0") --export /tmp/banned_ips.txt

EOF
}

check_root() {
    [[ $EUID -eq 0 ]] || error_exit "This script requires root privileges" 4
}

check_dependencies() {
    command -v fail2ban-client &> /dev/null || error_exit "fail2ban-client not found" 3
}

get_fail2ban_status() {
    if ! fail2ban-client ping &> /dev/null; then
        warning "Fail2ban is not running"
        return 1
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        fail2ban-client status 2>/dev/null || echo "{}"
    else
        echo ""
        echo -e "${WHITE}━━━ FAIL2BAN STATUS ━━━${NC}"
        fail2ban-client status 2>/dev/null
        echo ""
    fi
}

list_jails() {
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,/ /g' | xargs)

    if [[ -z "$jails" ]]; then
        warning "No jails configured"
        return 0
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{\"jails\": ["
        local first=true
        for jail in $jails; do
            [[ "$first" != true ]] && echo ","
            echo -n "    \"$jail\""
            first=false
        done
        echo ""
        echo "  ]}"
    else
        echo ""
        echo -e "${WHITE}━━━ CONFIGURED JAILS ━━━${NC}"
        for jail in $jails; do
            echo "  • $jail"
        done
        echo ""
    fi
}

list_banned_ips() {
    local jail="${1:-}"

    if [[ -z "$jail" ]]; then
        local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,/ /g' | xargs)

        for j in $jails; do
            list_banned_ips "$j"
        done
        return
    fi

    local status=$(fail2ban-client status "$jail" 2>/dev/null)
    local banned=$(echo "$status" | grep "Banned IP list:" | cut -d: -f2 | xargs)
    local total=$(echo "$status" | grep "Currently banned:" | awk '{print $NF}')

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"jail\": \"$jail\","
        echo "  \"total_banned\": ${total:-0},"
        echo "  \"banned_ips\": ["

        if [[ -n "$banned" ]]; then
            local first=true
            for ip in $banned; do
                [[ "$first" != true ]] && echo ","
                echo -n "    \"$ip\""
                first=false
            done
            echo ""
        fi

        echo "  ]"
        echo "}"
    else
        echo ""
        echo -e "${WHITE}━━━ BANNED IPs: $jail ━━━${NC}"
        echo -e "${CYAN}Total banned:${NC} ${total:-0}"

        if [[ -n "$banned" ]]; then
            echo ""
            for ip in $banned; do
                echo "  ${RED}✗${NC} $ip"
            done
        fi
        echo ""
    fi
}

ban_ip() {
    local ip="$1"
    local jail="${2:-sshd}"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address: $ip" 2
    fi

    info "Banning IP $ip in jail $jail..."

    if fail2ban-client set "$jail" banip "$ip" 2>&1; then
        success "IP $ip banned successfully"
    else
        error_exit "Failed to ban IP $ip" 1
    fi
}

unban_ip() {
    local ip="$1"
    local jail="${2:-}"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_exit "Invalid IP address: $ip" 2
    fi

    if [[ -z "$jail" ]]; then
        # Try all jails
        local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,/ /g' | xargs)

        local unbanned=false
        for j in $jails; do
            if fail2ban-client set "$j" unbanip "$ip" 2>/dev/null; then
                success "IP $ip unbanned from $j"
                unbanned=true
            fi
        done

        [[ "$unbanned" == false ]] && warning "IP $ip not found in any jail"
    else
        info "Unbanning IP $ip from jail $jail..."

        if fail2ban-client set "$jail" unbanip "$ip" 2>&1; then
            success "IP $ip unbanned successfully"
        else
            error_exit "Failed to unban IP $ip" 1
        fi
    fi
}

show_statistics() {
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,/ /g' | xargs)

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"statistics\": ["

        local first=true
        for jail in $jails; do
            local status=$(fail2ban-client status "$jail" 2>/dev/null)
            local total=$(echo "$status" | grep "Total banned:" | awk '{print $NF}')
            local current=$(echo "$status" | grep "Currently banned:" | awk '{print $NF}')
            local failed=$(echo "$status" | grep "Total failed:" | awk '{print $NF}')

            [[ "$first" != true ]] && echo ","

            cat << EOF
    {
      "jail": "$jail",
      "total_banned": ${total:-0},
      "currently_banned": ${current:-0},
      "total_failed": ${failed:-0}
    }
EOF
            first=false
        done

        echo ""
        echo "  ]"
        echo "}"
    else
        echo ""
        echo -e "${WHITE}━━━ FAIL2BAN STATISTICS ━━━${NC}"
        echo ""

        printf "${CYAN}%-15s %-15s %-15s %-15s${NC}\n" "JAIL" "TOTAL BANNED" "CURRENT BANNED" "TOTAL FAILED"
        echo "────────────────────────────────────────────────────────────────"

        for jail in $jails; do
            local status=$(fail2ban-client status "$jail" 2>/dev/null)
            local total=$(echo "$status" | grep "Total banned:" | awk '{print $NF}')
            local current=$(echo "$status" | grep "Currently banned:" | awk '{print $NF}')
            local failed=$(echo "$status" | grep "Total failed:" | awk '{print $NF}')

            printf "%-15s %-15s %-15s %-15s\n" "$jail" "${total:-0}" "${current:-0}" "${failed:-0}"
        done

        echo ""
    fi
}

export_banned_ips() {
    local file="$1"
    local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | sed 's/,/ /g' | xargs)

    > "$file"

    for jail in $jails; do
        local banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" | cut -d: -f2 | xargs)

        if [[ -n "$banned" ]]; then
            for ip in $banned; do
                echo "$ip # $jail" >> "$file"
            done
        fi
    done

    success "Banned IPs exported to: $file"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -s|--status) SHOW_STATUS=true; shift ;;
        -j|--jail) JAIL_NAME="$2"; shift 2 ;;
        --list) LIST_JAILS=true; shift ;;
        --banned) SHOW_BANNED=true; shift ;;
        --ban) BAN_IP="$2"; shift 2 ;;
        --unban) UNBAN_IP="$2"; shift 2 ;;
        --stats) SHOW_STATS=true; shift ;;
        --export) EXPORT_FILE="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_root
check_dependencies

if [[ "$SHOW_STATUS" == true ]]; then
    get_fail2ban_status
elif [[ "$LIST_JAILS" == true ]]; then
    list_jails
elif [[ "$SHOW_BANNED" == true ]]; then
    list_banned_ips "$JAIL_NAME"
elif [[ -n "$BAN_IP" ]]; then
    ban_ip "$BAN_IP" "${JAIL_NAME:-sshd}"
elif [[ -n "$UNBAN_IP" ]]; then
    unban_ip "$UNBAN_IP" "$JAIL_NAME"
elif [[ "$SHOW_STATS" == true ]]; then
    show_statistics
elif [[ -n "$EXPORT_FILE" ]]; then
    export_banned_ips "$EXPORT_FILE"
else
    get_fail2ban_status
fi
