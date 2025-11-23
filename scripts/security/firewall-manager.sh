#!/bin/bash

################################################################################
# Script Name: firewall-manager.sh
# Description: Universal firewall management tool supporting UFW, firewalld,
#              and iptables with easy rule management and common profiles.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.1
#
# Usage: ./firewall-manager.sh [options] [action]
#
# Actions:
#   status              Show firewall status
#   enable              Enable firewall
#   disable             Disable firewall
#   allow PORT          Allow port
#   deny PORT           Deny port
#   list                List all rules
#   reset               Reset to default
#
# Options:
#   -h, --help          Show help
#   -v, --verbose       Verbose output
#   --profile NAME      Apply security profile (ssh, web, mail, custom)
#
# Examples:
#   ./firewall-manager.sh status
#   ./firewall-manager.sh enable
#   ./firewall-manager.sh allow 80
#   ./firewall-manager.sh --profile web
#
# Exit Codes:
#   0 - Success
#   1 - Error
################################################################################

set -euo pipefail

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
PROFILE=""

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

show_usage() {
    cat << 'EOF'
Firewall Manager - Universal Firewall Control

Usage: firewall-manager.sh [OPTIONS] ACTION

Actions:
    status          Show firewall status
    enable          Enable firewall
    disable         Disable firewall
    allow PORT      Allow incoming port
    deny PORT       Deny port
    list            List all rules
    reset           Reset to defaults

Options:
    -h, --help              Show this help
    -v, --verbose           Verbose output
    --profile NAME          Apply profile (ssh, web, mail, database)

Profiles:
    ssh         Allow SSH (22)
    web         Allow HTTP (80) and HTTPS (443)
    mail        Allow SMTP (25), IMAP (143), IMAPS (993)
    database    Allow MySQL (3306), PostgreSQL (5432)

Examples:
    # Check status
    firewall-manager.sh status

    # Enable firewall
    firewall-manager.sh enable

    # Allow specific port
    firewall-manager.sh allow 8080

    # Apply web server profile
    firewall-manager.sh --profile web

    # List all rules
    firewall-manager.sh list

Supported Firewalls:
    • UFW (Ubuntu/Debian)
    • firewalld (Red Hat/Fedora/CentOS)
    • iptables (Generic Linux)

EOF
}

detect_firewall() {
    if command -v ufw &> /dev/null; then
        echo "ufw"
    elif command -v firewall-cmd &> /dev/null; then
        echo "firewalld"
    elif command -v iptables &> /dev/null; then
        echo "iptables"
    else
        error_exit "No supported firewall found"
    fi
}

fw_status() {
    case "$FW_TYPE" in
        ufw)
            sudo ufw status verbose
            ;;
        firewalld)
            sudo firewall-cmd --state
            sudo firewall-cmd --list-all
            ;;
        iptables)
            sudo iptables -L -n -v
            ;;
    esac
}

fw_enable() {
    case "$FW_TYPE" in
        ufw)
            sudo ufw --force enable
            success "UFW enabled"
            ;;
        firewalld)
            sudo systemctl enable firewalld
            sudo systemctl start firewalld
            success "firewalld enabled"
            ;;
        iptables)
            warning "iptables enabled by default, configure rules manually"
            ;;
    esac
}

fw_disable() {
    case "$FW_TYPE" in
        ufw)
            sudo ufw disable
            success "UFW disabled"
            ;;
        firewalld)
            sudo systemctl stop firewalld
            sudo systemctl disable firewalld
            success "firewalld disabled"
            ;;
        iptables)
            sudo iptables -F
            sudo iptables -X
            success "iptables flushed"
            ;;
    esac
}

fw_allow() {
    local port="$1"
    case "$FW_TYPE" in
        ufw)
            sudo ufw allow "$port"
            success "Allowed port $port"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --add-port="${port}/tcp"
            sudo firewall-cmd --reload
            success "Allowed port $port"
            ;;
        iptables)
            sudo iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            success "Allowed port $port"
            ;;
    esac
}

fw_deny() {
    local port="$1"
    case "$FW_TYPE" in
        ufw)
            sudo ufw deny "$port"
            success "Denied port $port"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --remove-port="${port}/tcp"
            sudo firewall-cmd --reload
            success "Denied port $port"
            ;;
        iptables)
            sudo iptables -A INPUT -p tcp --dport "$port" -j DROP
            success "Denied port $port"
            ;;
    esac
}

apply_profile() {
    local profile="$1"
    info "Applying profile: $profile"
    
    case "$profile" in
        ssh)
            fw_allow 22
            ;;
        web)
            fw_allow 80
            fw_allow 443
            ;;
        mail)
            fw_allow 25
            fw_allow 143
            fw_allow 993
            ;;
        database)
            fw_allow 3306
            fw_allow 5432
            ;;
        *)
            error_exit "Unknown profile: $profile"
            ;;
    esac
    
    success "Profile $profile applied"
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        status|enable|disable|list) ACTION="$1"; shift; break ;;
        allow|deny) ACTION="$1"; PORT="$2"; shift 2; break ;;
        *) error_exit "Unknown option: $1" ;;
    esac
done

# Detect firewall
FW_TYPE=$(detect_firewall)
info "Detected firewall: $FW_TYPE"

# Apply profile if specified
if [[ -n "$PROFILE" ]]; then
    apply_profile "$PROFILE"
    exit 0
fi

# Execute action
case "${ACTION:-}" in
    status) fw_status ;;
    enable) fw_enable ;;
    disable) fw_disable ;;
    allow) fw_allow "${PORT:-}" ;;
    deny) fw_deny "${PORT:-}" ;;
    list) fw_status ;;
    "") show_usage ;;
    *) error_exit "Unknown action: $ACTION" ;;
esac

exit 0
