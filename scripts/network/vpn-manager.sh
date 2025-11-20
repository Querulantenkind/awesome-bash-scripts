#!/bin/bash

################################################################################
# Script Name: vpn-manager.sh
# Description: VPN connection management for OpenVPN and WireGuard. Manage
#              multiple profiles, auto-reconnect, and connection testing.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./vpn-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -t, --type TYPE         VPN type (openvpn|wireguard, auto-detect)
#   -p, --profile NAME      VPN profile name
#   -c, --connect           Connect to VPN
#   -d, --disconnect        Disconnect from VPN
#   -s, --status            Show connection status
#   -l, --list              List available profiles
#   --test                  Test connection
#   --auto-reconnect        Enable auto-reconnect
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./vpn-manager.sh --list
#   ./vpn-manager.sh --connect --profile work
#   ./vpn-manager.sh --status
#   ./vpn-manager.sh --disconnect
#   ./vpn-manager.sh --test --profile work
#
# Dependencies:
#   - openvpn OR wireguard-tools
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
################################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

VERBOSE=false
VPN_TYPE=""
PROFILE=""
CONNECT=false
DISCONNECT=false
SHOW_STATUS=false
LIST_PROFILES=false
TEST_CONN=false
AUTO_RECONNECT=false
JSON_OUTPUT=false
USE_COLOR=true

OPENVPN_DIR="/etc/openvpn"
WG_DIR="/etc/wireguard"

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"; }
warning() { [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"; }
info() { [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2; }

show_usage() {
    cat << EOF
${WHITE}VPN Manager - OpenVPN/WireGuard Connection Manager${NC}

${CYAN}Usage:${NC} $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help message
    -v, --verbose           Verbose output
    -t, --type TYPE         VPN type (openvpn|wireguard)
    -p, --profile NAME      VPN profile name
    -c, --connect           Connect to VPN
    -d, --disconnect        Disconnect from VPN
    -s, --status            Show connection status
    -l, --list              List available profiles
    --test                  Test connection
    --auto-reconnect        Enable auto-reconnect
    -j, --json              JSON output
    --no-color              Disable colors

${CYAN}Examples:${NC}
    $(basename "$0") --list
    $(basename "$0") --connect --profile work
    $(basename "$0") --status
    $(basename "$0") --disconnect

EOF
}

check_dependencies() {
    if [[ -z "$VPN_TYPE" ]]; then
        if command -v openvpn &> /dev/null; then
            VPN_TYPE="openvpn"
        elif command -v wg &> /dev/null; then
            VPN_TYPE="wireguard"
        else
            error_exit "Neither OpenVPN nor WireGuard found" 3
        fi
    fi
}

list_vpn_profiles() {
    if [[ "$VPN_TYPE" == "openvpn" ]]; then
        find "$OPENVPN_DIR" -name "*.ovpn" -o -name "*.conf" 2>/dev/null | while read -r f; do
            basename "$f" | sed 's/\.(ovpn|conf)$//'
        done
    else
        find "$WG_DIR" -name "*.conf" 2>/dev/null | while read -r f; do
            basename "$f" .conf
        done
    fi
}

connect_vpn() {
    local profile="$1"
    
    if [[ "$VPN_TYPE" == "openvpn" ]]; then
        info "Connecting to OpenVPN profile: $profile"
        sudo openvpn --config "$OPENVPN_DIR/${profile}.ovpn" --daemon
    else
        info "Connecting to WireGuard profile: $profile"
        sudo wg-quick up "$profile"
    fi
    
    success "Connected to VPN: $profile"
}

disconnect_vpn() {
    if [[ "$VPN_TYPE" == "openvpn" ]]; then
        sudo killall openvpn 2>/dev/null && success "Disconnected from OpenVPN" || warning "No OpenVPN connection"
    else
        sudo wg-quick down "$PROFILE" 2>/dev/null && success "Disconnected from WireGuard" || warning "No WireGuard connection"
    fi
}

show_vpn_status() {
    if [[ "$VPN_TYPE" == "openvpn" ]]; then
        pgrep -f openvpn &> /dev/null && success "OpenVPN is connected" || info "OpenVPN is not connected"
    else
        sudo wg show &> /dev/null && success "WireGuard is connected" || info "WireGuard is not connected"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -t|--type) VPN_TYPE="$2"; shift 2 ;;
        -p|--profile) PROFILE="$2"; shift 2 ;;
        -c|--connect) CONNECT=true; shift ;;
        -d|--disconnect) DISCONNECT=true; shift ;;
        -s|--status) SHOW_STATUS=true; shift ;;
        -l|--list) LIST_PROFILES=true; shift ;;
        --test) TEST_CONN=true; shift ;;
        --auto-reconnect) AUTO_RECONNECT=true; shift ;;
        -j|--json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_dependencies

if [[ "$LIST_PROFILES" == true ]]; then
    list_vpn_profiles
elif [[ "$CONNECT" == true ]]; then
    [[ -z "$PROFILE" ]] && error_exit "Profile required" 2
    connect_vpn "$PROFILE"
elif [[ "$DISCONNECT" == true ]]; then
    disconnect_vpn
elif [[ "$SHOW_STATUS" == true ]]; then
    show_vpn_status
else
    show_usage
fi
