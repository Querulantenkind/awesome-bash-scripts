#!/bin/bash

################################################################################
# Script Name: network-monitor.sh
# Description: Comprehensive network monitoring tool with connection tracking,
#              bandwidth monitoring, port scanning, and connectivity testing.
#              Provides real-time network statistics and alerts.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./network-monitor.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -w, --watch SECONDS     Continuous monitoring mode
#   -i, --interface IFACE   Monitor specific interface
#   -p, --ports             Show listening ports
#   -c, --connections       Show active connections
#   -b, --bandwidth         Monitor bandwidth usage
#   -t, --test HOST         Test connectivity to host
#   -s, --scan HOST         Port scan host (top 100 ports)
#   -l, --latency HOST      Monitor latency to host
#   -j, --json              Output in JSON format
#   --top-connections N     Show top N connections by data transfer
#   --log FILE              Log output to file
#
# Examples:
#   ./network-monitor.sh
#   ./network-monitor.sh --watch 5 --bandwidth
#   ./network-monitor.sh --interface eth0 --bandwidth
#   ./network-monitor.sh --ports --connections
#   ./network-monitor.sh --test google.com
#   ./network-monitor.sh --latency 8.8.8.8 --watch 1
#   ./network-monitor.sh --scan 192.168.1.1
#
# Dependencies:
#   - ss or netstat
#   - ip (iproute2)
#   - ping
#   - nc (netcat) - optional for port scanning
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
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
WATCH_MODE=false
WATCH_INTERVAL=5
INTERFACE=""
SHOW_PORTS=false
SHOW_CONNECTIONS=false
SHOW_BANDWIDTH=false
TEST_HOST=""
SCAN_HOST=""
LATENCY_HOST=""
JSON_OUTPUT=false
TOP_CONNECTIONS=0
LOG_FILE=""
USE_COLOR=true

# Temporary files for bandwidth calculation
PREV_STATS="/tmp/.netmon_$$"

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
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

log_message() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}Network Monitor - Comprehensive Network Monitoring${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -w, --watch SECONDS     Continuous monitoring (default: 5s)
    -i, --interface IFACE   Monitor specific network interface
    -p, --ports             Show listening ports
    -c, --connections       Show active connections
    -b, --bandwidth         Monitor bandwidth usage
    -t, --test HOST         Test connectivity to host
    -s, --scan HOST         Port scan host (common ports)
    -l, --latency HOST      Monitor latency/ping to host
    -j, --json              Output in JSON format
    --top-connections N     Show top N connections
    --log FILE              Log output to file

${CYAN}Examples:${NC}
    # Basic network overview
    $SCRIPT_NAME

    # Continuous bandwidth monitoring
    $SCRIPT_NAME --watch 5 --bandwidth

    # Monitor specific interface
    $SCRIPT_NAME --interface eth0 --bandwidth

    # Show ports and connections
    $SCRIPT_NAME --ports --connections

    # Test connectivity
    $SCRIPT_NAME --test google.com

    # Monitor latency
    $SCRIPT_NAME --latency 8.8.8.8 --watch 1

    # Port scan a host
    $SCRIPT_NAME --scan 192.168.1.1

${CYAN}Features:${NC}
    • Network interface statistics
    • Bandwidth monitoring (real-time)
    • Active connection tracking
    • Listening port detection
    • Connectivity testing
    • Latency monitoring
    • Port scanning
    • JSON export
    • Continuous watch mode

EOF
}

check_dependencies() {
    local missing_deps=()
    
    # Check for ss or netstat
    if ! command -v ss &> /dev/null && ! command -v netstat &> /dev/null; then
        missing_deps+=("ss or netstat")
    fi
    
    if ! command -v ip &> /dev/null; then
        missing_deps+=("ip")
    fi
    
    if ! command -v ping &> /dev/null; then
        missing_deps+=("ping")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi
    
    # Optional dependencies
    if [[ -n "$SCAN_HOST" ]] && ! command -v nc &> /dev/null; then
        warning "netcat (nc) not found - port scanning will be limited"
    fi
}

################################################################################
# Network Information Functions
################################################################################

get_default_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

get_all_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v lo
}

get_interface_info() {
    local iface="$1"
    
    # Get IP address
    local ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | grep -v "^fe80" | head -1)
    
    # Get MAC address
    local mac=$(ip link show "$iface" 2>/dev/null | grep -oP '(?<=link/ether\s)[0-9a-f:]+')
    
    # Get state
    local state=$(ip link show "$iface" 2>/dev/null | grep -oP '(?<=state )\w+')
    
    # Get MTU
    local mtu=$(ip link show "$iface" 2>/dev/null | grep -oP '(?<=mtu )\d+')
    
    echo "$ipv4|$ipv6|$mac|$state|$mtu"
}

get_interface_stats() {
    local iface="$1"
    
    local rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
    local tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
    local rx_packets=$(cat "/sys/class/net/$iface/statistics/rx_packets" 2>/dev/null || echo 0)
    local tx_packets=$(cat "/sys/class/net/$iface/statistics/tx_packets" 2>/dev/null || echo 0)
    local rx_errors=$(cat "/sys/class/net/$iface/statistics/rx_errors" 2>/dev/null || echo 0)
    local tx_errors=$(cat "/sys/class/net/$iface/statistics/tx_errors" 2>/dev/null || echo 0)
    local rx_dropped=$(cat "/sys/class/net/$iface/statistics/rx_dropped" 2>/dev/null || echo 0)
    local tx_dropped=$(cat "/sys/class/net/$iface/statistics/tx_dropped" 2>/dev/null || echo 0)
    
    echo "$rx_bytes|$tx_bytes|$rx_packets|$tx_packets|$rx_errors|$tx_errors|$rx_dropped|$tx_dropped"
}

calculate_bandwidth() {
    local iface="$1"
    local interval="${2:-1}"
    
    IFS='|' read -r rx1 tx1 _ <<< "$(get_interface_stats "$iface")"
    sleep "$interval"
    IFS='|' read -r rx2 tx2 _ <<< "$(get_interface_stats "$iface")"
    
    local rx_rate=$(( (rx2 - rx1) / interval ))
    local tx_rate=$(( (tx2 - tx1) / interval ))
    
    echo "$rx_rate|$tx_rate"
}

format_bytes() {
    local bytes=$1
    
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

format_rate() {
    local bytes_per_sec=$1
    
    if (( bytes_per_sec >= 1048576 )); then
        echo "$(echo "scale=2; $bytes_per_sec / 1048576" | bc) MB/s"
    elif (( bytes_per_sec >= 1024 )); then
        echo "$(echo "scale=2; $bytes_per_sec / 1024" | bc) KB/s"
    else
        echo "$bytes_per_sec B/s"
    fi
}

################################################################################
# Connection Functions
################################################################################

get_listening_ports() {
    if command -v ss &> /dev/null; then
        ss -tuln | grep LISTEN | awk '{print $5}' | sed 's/.*://' | sort -n | uniq
    else
        netstat -tuln | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -n | uniq
    fi
}

get_listening_ports_detailed() {
    echo -e "${WHITE}━━━ LISTENING PORTS ━━━${NC}"
    printf "${CYAN}%-10s %-8s %-20s %-s${NC}\n" "Protocol" "Port" "Address" "Program"
    
    if command -v ss &> /dev/null; then
        sudo ss -tulnp 2>/dev/null | grep LISTEN | while IFS= read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local addr=$(echo "$line" | awk '{print $5}')
            local port=$(echo "$addr" | sed 's/.*://')
            local program=$(echo "$line" | grep -oP '(?<=users:\(\().*?(?=,)' | head -1)
            
            printf "%-10s %-8s %-20s %-s\n" "$proto" "$port" "$addr" "${program:-unknown}"
        done
    else
        sudo netstat -tulnp 2>/dev/null | grep LISTEN | while IFS= read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local addr=$(echo "$line" | awk '{print $4}')
            local port=$(echo "$addr" | sed 's/.*://')
            local program=$(echo "$line" | awk '{print $7}')
            
            printf "%-10s %-8s %-20s %-s\n" "$proto" "$port" "$addr" "${program:-unknown}"
        done
    fi
}

get_active_connections() {
    echo -e "\n${WHITE}━━━ ACTIVE CONNECTIONS ━━━${NC}"
    printf "${CYAN}%-10s %-22s %-22s %-s${NC}\n" "Protocol" "Local Address" "Remote Address" "State"
    
    if command -v ss &> /dev/null; then
        ss -tun | tail -n +2 | head -20 | while IFS= read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local state=$(echo "$line" | awk '{print $2}')
            local local_addr=$(echo "$line" | awk '{print $5}')
            local remote_addr=$(echo "$line" | awk '{print $6}')
            
            printf "%-10s %-22s %-22s %-s\n" "$proto" "${local_addr:0:22}" "${remote_addr:0:22}" "$state"
        done
    else
        netstat -tun | tail -n +3 | head -20 | while IFS= read -r line; do
            local proto=$(echo "$line" | awk '{print $1}')
            local local_addr=$(echo "$line" | awk '{print $4}')
            local remote_addr=$(echo "$line" | awk '{print $5}')
            local state=$(echo "$line" | awk '{print $6}')
            
            printf "%-10s %-22s %-22s %-s\n" "$proto" "${local_addr:0:22}" "${remote_addr:0:22}" "$state"
        done
    fi
}

get_connection_count() {
    if command -v ss &> /dev/null; then
        local established=$(ss -t state established | tail -n +2 | wc -l)
        local time_wait=$(ss -t state time-wait | tail -n +2 | wc -l)
        local close_wait=$(ss -t state close-wait | tail -n +2 | wc -l)
    else
        local established=$(netstat -tn | grep ESTABLISHED | wc -l)
        local time_wait=$(netstat -tn | grep TIME_WAIT | wc -l)
        local close_wait=$(netstat -tn | grep CLOSE_WAIT | wc -l)
    fi
    
    echo "$established|$time_wait|$close_wait"
}

################################################################################
# Testing Functions
################################################################################

test_connectivity() {
    local host="$1"
    
    echo -e "${WHITE}━━━ CONNECTIVITY TEST: $host ━━━${NC}"
    
    # Resolve hostname
    echo -e "${CYAN}Resolving hostname...${NC}"
    local ip=$(getent hosts "$host" | awk '{print $1}' | head -1)
    
    if [[ -z "$ip" ]]; then
        echo -e "${RED}✗ Failed to resolve hostname${NC}"
        return 1
    fi
    
    success "Resolved to: $ip"
    
    # Ping test
    echo -e "\n${CYAN}Ping test (5 packets)...${NC}"
    local ping_result=$(ping -c 5 -W 2 "$host" 2>&1)
    
    if echo "$ping_result" | grep -q "0% packet loss"; then
        success "Ping successful"
        
        local avg_time=$(echo "$ping_result" | grep -oP 'avg = \K[0-9.]+' || echo "$ping_result" | grep -oP 'avg/[^/]+/[^/]+/\K[0-9.]+')
        echo -e "${CYAN}Average latency:${NC} ${avg_time} ms"
    else
        echo -e "${RED}✗ Ping failed or packet loss detected${NC}"
    fi
    
    # Port tests
    echo -e "\n${CYAN}Testing common ports...${NC}"
    for port in 80 443 22; do
        if timeout 2 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            success "Port $port is open"
        else
            echo -e "${YELLOW}Port $port is closed or filtered${NC}"
        fi
    done
}

scan_ports() {
    local host="$1"
    
    echo -e "${WHITE}━━━ PORT SCAN: $host ━━━${NC}"
    echo -e "${YELLOW}Scanning common ports...${NC}\n"
    
    local common_ports=(20 21 22 23 25 53 80 110 143 443 465 587 993 995 3306 3389 5432 8080 8443)
    local open_ports=()
    
    for port in "${common_ports[@]}"; do
        if timeout 1 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            open_ports+=("$port")
            echo -e "${GREEN}✓ Port $port: OPEN${NC}"
        fi
    done
    
    echo ""
    if [[ ${#open_ports[@]} -eq 0 ]]; then
        warning "No open ports found"
    else
        success "Found ${#open_ports[@]} open ports: ${open_ports[*]}"
    fi
}

monitor_latency() {
    local host="$1"
    
    echo -e "${CYAN}Monitoring latency to $host (Press Ctrl+C to stop)${NC}\n"
    
    ping "$host" | while IFS= read -r line; do
        if [[ "$line" =~ time=([0-9.]+) ]]; then
            local latency="${BASH_REMATCH[1]}"
            local timestamp=$(date '+%H:%M:%S')
            
            if (( $(echo "$latency < 50" | bc -l) )); then
                echo -e "[$timestamp] ${GREEN}Latency: ${latency} ms${NC}"
            elif (( $(echo "$latency < 100" | bc -l) )); then
                echo -e "[$timestamp] ${YELLOW}Latency: ${latency} ms${NC}"
            else
                echo -e "[$timestamp] ${RED}Latency: ${latency} ms${NC}"
            fi
            
            log_message "Latency to $host: ${latency} ms"
        fi
    done
}

################################################################################
# Display Functions
################################################################################

display_header() {
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                 NETWORK MONITOR                                 ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Host:${NC}     $(hostname)"
    echo -e "${CYAN}Time:${NC}     $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

display_interface_info() {
    local iface="$1"
    
    IFS='|' read -r ipv4 ipv6 mac state mtu <<< "$(get_interface_info "$iface")"
    IFS='|' read -r rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped <<< "$(get_interface_stats "$iface")"
    
    echo -e "${WHITE}━━━ INTERFACE: $iface ━━━${NC}"
    echo -e "${CYAN}State:${NC}        $state"
    echo -e "${CYAN}IPv4:${NC}         ${ipv4:-N/A}"
    [[ -n "$ipv6" ]] && echo -e "${CYAN}IPv6:${NC}         $ipv6"
    echo -e "${CYAN}MAC:${NC}          ${mac:-N/A}"
    echo -e "${CYAN}MTU:${NC}          ${mtu:-N/A}"
    echo -e "${CYAN}RX:${NC}           $(format_bytes $rx_bytes) ($rx_packets packets)"
    echo -e "${CYAN}TX:${NC}           $(format_bytes $tx_bytes) ($tx_packets packets)"
    
    if [[ $rx_errors -gt 0 ]] || [[ $tx_errors -gt 0 ]]; then
        echo -e "${RED}Errors:${NC}       RX: $rx_errors, TX: $tx_errors"
    fi
    
    if [[ $rx_dropped -gt 0 ]] || [[ $tx_dropped -gt 0 ]]; then
        echo -e "${YELLOW}Dropped:${NC}      RX: $rx_dropped, TX: $tx_dropped"
    fi
    
    echo ""
}

display_bandwidth() {
    local iface="$1"
    
    echo -e "${WHITE}━━━ BANDWIDTH (Real-time) ━━━${NC}"
    
    IFS='|' read -r rx_rate tx_rate <<< "$(calculate_bandwidth "$iface" 1)"
    
    echo -e "${CYAN}Download:${NC}     $(format_rate $rx_rate)"
    echo -e "${CYAN}Upload:${NC}       $(format_rate $tx_rate)"
    echo ""
}

display_connection_summary() {
    IFS='|' read -r established time_wait close_wait <<< "$(get_connection_count)"
    
    echo -e "${WHITE}━━━ CONNECTION SUMMARY ━━━${NC}"
    echo -e "${CYAN}Established:${NC}  $established"
    echo -e "${CYAN}Time-Wait:${NC}    $time_wait"
    echo -e "${CYAN}Close-Wait:${NC}   $close_wait"
    echo ""
}

generate_json_output() {
    local iface="${INTERFACE:-$(get_default_interface)}"
    
    IFS='|' read -r ipv4 ipv6 mac state mtu <<< "$(get_interface_info "$iface")"
    IFS='|' read -r rx_bytes tx_bytes rx_packets tx_packets _ _ _ _ <<< "$(get_interface_stats "$iface")"
    IFS='|' read -r established time_wait close_wait <<< "$(get_connection_count)"
    
    cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "hostname": "$(hostname)",
  "interface": {
    "name": "$iface",
    "state": "$state",
    "ipv4": "${ipv4:-null}",
    "ipv6": "${ipv6:-null}",
    "mac": "${mac:-null}",
    "mtu": ${mtu:-0},
    "rx_bytes": $rx_bytes,
    "tx_bytes": $tx_bytes,
    "rx_packets": $rx_packets,
    "tx_packets": $tx_packets
  },
  "connections": {
    "established": $established,
    "time_wait": $time_wait,
    "close_wait": $close_wait
  }
}
EOF
}

################################################################################
# Main Monitoring Function
################################################################################

run_monitoring() {
    local iface="${INTERFACE:-$(get_default_interface)}"
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        generate_json_output
    else
        [[ "$WATCH_MODE" == true ]] && clear
        
        display_header
        display_interface_info "$iface"
        
        if [[ "$SHOW_BANDWIDTH" == true ]]; then
            display_bandwidth "$iface"
        fi
        
        if [[ "$SHOW_CONNECTIONS" == true ]]; then
            display_connection_summary
            get_active_connections
        fi
        
        if [[ "$SHOW_PORTS" == true ]]; then
            get_listening_ports_detailed
        fi
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
        -w|--watch)
            WATCH_MODE=true
            if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL="$2"
                shift 2
            else
                shift
            fi
            ;;
        -i|--interface)
            [[ -z "${2:-}" ]] && error_exit "--interface requires an interface name" 2
            INTERFACE="$2"
            shift 2
            ;;
        -p|--ports)
            SHOW_PORTS=true
            shift
            ;;
        -c|--connections)
            SHOW_CONNECTIONS=true
            shift
            ;;
        -b|--bandwidth)
            SHOW_BANDWIDTH=true
            shift
            ;;
        -t|--test)
            [[ -z "${2:-}" ]] && error_exit "--test requires a hostname" 2
            TEST_HOST="$2"
            shift 2
            ;;
        -s|--scan)
            [[ -z "${2:-}" ]] && error_exit "--scan requires a hostname" 2
            SCAN_HOST="$2"
            shift 2
            ;;
        -l|--latency)
            [[ -z "${2:-}" ]] && error_exit "--latency requires a hostname" 2
            LATENCY_HOST="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        --log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            error_exit "Unexpected argument: $1" 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Handle special modes
if [[ -n "$TEST_HOST" ]]; then
    test_connectivity "$TEST_HOST"
    exit 0
fi

if [[ -n "$SCAN_HOST" ]]; then
    scan_ports "$SCAN_HOST"
    exit 0
fi

if [[ -n "$LATENCY_HOST" ]]; then
    monitor_latency "$LATENCY_HOST"
    exit 0
fi

# Main monitoring loop
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

# Cleanup
[[ -f "$PREV_STATS" ]] && rm -f "$PREV_STATS"

