#!/bin/bash

################################################################################
# Script Name: network-diagnostics.sh
# Description: Comprehensive network troubleshooting and diagnostic tool. Performs
#              connectivity tests, DNS resolution checks, ping tests, traceroute,
#              port connectivity verification, interface status monitoring, and
#              generates detailed diagnostic reports. Supports multiple test modes.
# Author: Luca
# Created: 2025-11-20
# Modified: 2025-11-20
# Version: 1.0.0
#
# Usage: ./network-diagnostics.sh [options] [host]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -a, --all               Run all diagnostic tests
#   -c, --connectivity      Test internet connectivity
#   -d, --dns HOST          Test DNS resolution
#   -p, --ping HOST         Ping test to host
#   -t, --traceroute HOST   Traceroute to host
#   -P, --port HOST:PORT    Test port connectivity
#   -i, --interface         Show network interface status
#   -r, --route             Show routing table
#   -g, --gateway           Check gateway connectivity
#   -s, --speed             Run speed test (requires speedtest-cli)
#   -n, --nameservers       Check DNS nameservers
#   -j, --json              Output in JSON format
#   -o, --output FILE       Save output to file
#   -l, --log FILE          Log diagnostics to file
#   --no-color              Disable colored output
#   --timeout SECONDS       Connection timeout (default: 5)
#   --count NUM             Ping count (default: 4)
#   --report                Generate full diagnostic report
#
# Examples:
#   # Run all diagnostics
#   ./network-diagnostics.sh --all
#
#   # Test specific host connectivity
#   ./network-diagnostics.sh --ping google.com
#
#   # Check DNS resolution
#   ./network-diagnostics.sh --dns example.com
#
#   # Test port connectivity
#   ./network-diagnostics.sh --port google.com:443
#
#   # Traceroute to host
#   ./network-diagnostics.sh --traceroute 8.8.8.8
#
#   # Generate full diagnostic report
#   ./network-diagnostics.sh --report -o network-report.txt
#
#   # Check interfaces and routing
#   ./network-diagnostics.sh -i -r -g
#
# Dependencies:
#   - ping, traceroute, dig/nslookup
#   - nc (netcat) or telnet for port testing
#   - speedtest-cli (optional, for speed tests)
#
# Exit Codes:
#   0 - Success (all tests passed)
#   1 - General error
#   2 - Invalid argument
#   3 - Network connectivity issue
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
JSON_OUTPUT=false
OUTPUT_FILE=""
LOG_FILE=""
USE_COLOR=true
RUN_ALL=false
TEST_CONNECTIVITY=false
TEST_DNS=""
TEST_PING=""
TEST_TRACEROUTE=""
TEST_PORT=""
SHOW_INTERFACES=false
SHOW_ROUTES=false
TEST_GATEWAY=false
TEST_SPEED=false
TEST_NAMESERVERS=false
GENERATE_REPORT=false
TIMEOUT=5
PING_COUNT=4

# Test hosts for connectivity check
CONNECTIVITY_HOSTS=("8.8.8.8" "1.1.1.1" "google.com")

# Statistics
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit "${2:-1}"
}

success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo "✓ $1"
    fi
    ((TESTS_PASSED++))
}

fail() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${RED}✗ $1${NC}"
    else
        echo "✗ $1"
    fi
    ((TESTS_FAILED++))
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
        if [[ "$USE_COLOR" == true ]]; then
            echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
        else
            echo "[VERBOSE] $1" >&2
        fi
    fi
}

section_header() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        if [[ "$USE_COLOR" == true ]]; then
            echo ""
            echo -e "${WHITE}━━━ $1 ━━━${NC}"
        else
            echo ""
            echo "━━━ $1 ━━━"
        fi
    fi
}

show_usage() {
    cat << 'EOF'
Network Diagnostics - Comprehensive Network Troubleshooting Tool

Usage:
    network-diagnostics.sh [OPTIONS] [HOST]

Options:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --all               Run all diagnostic tests
    -c, --connectivity      Test internet connectivity
    -d, --dns HOST          Test DNS resolution
    -p, --ping HOST         Ping test to host
    -t, --traceroute HOST   Traceroute to host
    -P, --port HOST:PORT    Test port connectivity
    -i, --interface         Show network interface status
    -r, --route             Show routing table
    -g, --gateway           Check gateway connectivity
    -s, --speed             Run speed test
    -n, --nameservers       Check DNS nameservers
    -j, --json              Output in JSON format
    -o, --output FILE       Save output to file
    -l, --log FILE          Log diagnostics to file
    --no-color              Disable colored output
    --timeout SECONDS       Connection timeout (default: 5)
    --count NUM             Ping count (default: 4)
    --report                Generate full diagnostic report

Examples:
    # Run all diagnostics
    network-diagnostics.sh --all

    # Test specific host connectivity
    network-diagnostics.sh --ping google.com

    # Check DNS resolution
    network-diagnostics.sh --dns example.com

    # Test port connectivity
    network-diagnostics.sh --port google.com:443

    # Traceroute to host
    network-diagnostics.sh --traceroute 8.8.8.8

    # Generate full diagnostic report
    network-diagnostics.sh --report -o network-report.txt

    # Check interfaces and routing
    network-diagnostics.sh -i -r -g

Features:
    • Internet connectivity verification
    • DNS resolution testing
    • Ping tests with statistics
    • Traceroute path analysis
    • Port connectivity checks
    • Network interface status
    • Routing table display
    • Gateway connectivity
    • Speed testing (optional)
    • Comprehensive diagnostic reports
    • JSON output support

EOF
}

check_dependencies() {
    local missing_deps=()

    for cmd in ping ip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 1
    fi
}

################################################################################
# Diagnostic Functions
################################################################################

test_internet_connectivity() {
    section_header "INTERNET CONNECTIVITY TEST"
    ((TESTS_TOTAL++))

    verbose "Testing connectivity to multiple hosts..."

    local connected=false

    for host in "${CONNECTIVITY_HOSTS[@]}"; do
        verbose "Testing: $host"

        if ping -c 1 -W "$TIMEOUT" "$host" &>/dev/null; then
            success "Connected to internet (via $host)"
            connected=true
            break
        fi
    done

    if [[ "$connected" == false ]]; then
        fail "No internet connectivity detected"
        return 1
    fi

    return 0
}

test_dns_resolution() {
    local host="$1"

    section_header "DNS RESOLUTION TEST: $host"
    ((TESTS_TOTAL++))

    verbose "Resolving: $host"

    local resolver=""
    if command -v dig &> /dev/null; then
        resolver="dig"
    elif command -v nslookup &> /dev/null; then
        resolver="nslookup"
    elif command -v host &> /dev/null; then
        resolver="host"
    else
        warning "No DNS tools available (dig, nslookup, host)"
        return 1
    fi

    verbose "Using resolver: $resolver"

    local result=""
    case "$resolver" in
        dig)
            result=$(dig +short "$host" 2>&1)
            ;;
        nslookup)
            result=$(nslookup "$host" 2>&1 | grep -A1 "Name:" | tail -1 | awk '{print $2}')
            ;;
        host)
            result=$(host "$host" 2>&1 | grep "has address" | awk '{print $4}')
            ;;
    esac

    if [[ -n "$result" ]] && [[ "$result" != *"not found"* ]] && [[ "$result" != *"NXDOMAIN"* ]]; then
        success "DNS resolution successful"
        info "Resolved to: $result"
        return 0
    else
        fail "DNS resolution failed for $host"
        return 1
    fi
}

test_ping_host() {
    local host="$1"

    section_header "PING TEST: $host"
    ((TESTS_TOTAL++))

    verbose "Pinging $host ($PING_COUNT packets)..."

    local ping_output
    if ping_output=$(ping -c "$PING_COUNT" -W "$TIMEOUT" "$host" 2>&1); then
        success "Ping test successful to $host"

        # Extract statistics
        local transmitted=$(echo "$ping_output" | grep "transmitted" | awk '{print $1}')
        local received=$(echo "$ping_output" | grep "transmitted" | awk '{print $4}')
        local loss=$(echo "$ping_output" | grep "transmitted" | awk '{print $6}')
        local rtt=$(echo "$ping_output" | grep "min/avg/max" | awk -F'/' '{print $5}')

        info "Packets: $transmitted transmitted, $received received, $loss loss"
        [[ -n "$rtt" ]] && info "Average RTT: ${rtt}ms"

        return 0
    else
        fail "Ping test failed to $host"
        verbose "Error: $ping_output"
        return 1
    fi
}

test_traceroute_host() {
    local host="$1"

    section_header "TRACEROUTE: $host"
    ((TESTS_TOTAL++))

    if ! command -v traceroute &> /dev/null && ! command -v tracepath &> /dev/null; then
        warning "Traceroute not available"
        return 1
    fi

    verbose "Tracing route to $host..."

    local trace_cmd="traceroute"
    command -v traceroute &> /dev/null || trace_cmd="tracepath"

    info "Route to $host:"
    if $trace_cmd -m 15 "$host" 2>&1; then
        success "Traceroute completed"
        return 0
    else
        fail "Traceroute failed"
        return 1
    fi
}

test_port_connectivity() {
    local target="$1"

    section_header "PORT CONNECTIVITY TEST: $target"
    ((TESTS_TOTAL++))

    # Parse host:port
    local host="${target%:*}"
    local port="${target##*:}"

    if [[ "$host" == "$port" ]]; then
        error_exit "Port not specified. Use format HOST:PORT" 2
    fi

    verbose "Testing connection to $host:$port..."

    # Try different methods
    if command -v nc &> /dev/null; then
        if timeout "$TIMEOUT" nc -zv "$host" "$port" &>/dev/null; then
            success "Port $port is open on $host"
            return 0
        fi
    elif command -v telnet &> /dev/null; then
        if timeout "$TIMEOUT" bash -c "echo '' | telnet $host $port" &>/dev/null; then
            success "Port $port is open on $host"
            return 0
        fi
    elif command -v timeout &> /dev/null && [[ -e /dev/tcp ]]; then
        if timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
            success "Port $port is open on $host"
            return 0
        fi
    fi

    fail "Port $port is closed or unreachable on $host"
    return 1
}

show_network_interfaces() {
    section_header "NETWORK INTERFACES"

    verbose "Gathering interface information..."

    if command -v ip &> /dev/null; then
        info "Active network interfaces:"
        ip -brief addr show | while read -r iface state addr; do
            local color="$GREEN"
            [[ "$state" != "UP" ]] && color="$RED"

            echo -e "  ${color}${iface}${NC} - ${state} - ${addr}"
        done
    else
        warning "ip command not available"
        ifconfig 2>/dev/null || echo "No interface information available"
    fi
}

show_routing_table() {
    section_header "ROUTING TABLE"

    verbose "Displaying routing table..."

    if command -v ip &> /dev/null; then
        ip route show
    elif command -v route &> /dev/null; then
        route -n
    elif command -v netstat &> /dev/null; then
        netstat -rn
    else
        warning "No routing tools available"
    fi
}

test_gateway_connectivity() {
    section_header "GATEWAY CONNECTIVITY TEST"
    ((TESTS_TOTAL++))

    verbose "Finding default gateway..."

    local gateway
    if command -v ip &> /dev/null; then
        gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    elif command -v route &> /dev/null; then
        gateway=$(route -n | grep '^0.0.0.0' | awk '{print $2}' | head -1)
    fi

    if [[ -z "$gateway" ]]; then
        fail "No default gateway found"
        return 1
    fi

    info "Default gateway: $gateway"
    verbose "Testing gateway connectivity..."

    if ping -c 2 -W "$TIMEOUT" "$gateway" &>/dev/null; then
        success "Gateway is reachable"
        return 0
    else
        fail "Gateway is unreachable"
        return 1
    fi
}

check_nameservers() {
    section_header "DNS NAMESERVERS"
    ((TESTS_TOTAL++))

    verbose "Checking DNS nameservers..."

    if [[ ! -f /etc/resolv.conf ]]; then
        warning "No /etc/resolv.conf found"
        return 1
    fi

    local nameservers=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}')

    if [[ -z "$nameservers" ]]; then
        fail "No nameservers configured"
        return 1
    fi

    info "Configured nameservers:"
    local all_ok=true

    while read -r ns; do
        verbose "Testing nameserver: $ns"

        if ping -c 1 -W "$TIMEOUT" "$ns" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $ns - reachable"
        else
            echo -e "  ${RED}✗${NC} $ns - unreachable"
            all_ok=false
        fi
    done <<< "$nameservers"

    if [[ "$all_ok" == true ]]; then
        success "All nameservers are reachable"
        return 0
    else
        fail "Some nameservers are unreachable"
        return 1
    fi
}

run_speed_test() {
    section_header "NETWORK SPEED TEST"

    if ! command -v speedtest-cli &> /dev/null; then
        warning "speedtest-cli not installed"
        info "Install with: pip install speedtest-cli"
        return 1
    fi

    verbose "Running speed test..."
    info "This may take a minute..."

    speedtest-cli --simple 2>&1
}

################################################################################
# Report Generation
################################################################################

generate_diagnostic_report() {
    section_header "COMPREHENSIVE NETWORK DIAGNOSTIC REPORT"

    echo -e "${CYAN}Generated:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}Hostname:${NC}  $(hostname)"
    echo -e "${CYAN}OS:${NC}        $(uname -s) $(uname -r)"
    echo ""

    # Run all tests
    test_internet_connectivity || true
    show_network_interfaces
    show_routing_table
    test_gateway_connectivity || true
    check_nameservers || true
    test_dns_resolution "google.com" || true
    test_ping_host "8.8.8.8" || true

    # Summary
    section_header "DIAGNOSTIC SUMMARY"
    echo -e "${CYAN}Tests Run:${NC}    $TESTS_TOTAL"
    echo -e "${GREEN}Passed:${NC}       $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}       $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        success "Network diagnostics completed - all tests passed"
    else
        echo ""
        warning "Network diagnostics completed - some tests failed"
    fi
}

generate_json_report() {
    cat << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "hostname": "$(hostname)",
  "tests": {
    "total": $TESTS_TOTAL,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED
  },
  "status": "$([ $TESTS_FAILED -eq 0 ] && echo "healthy" || echo "issues_detected")"
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
        -a|--all)
            RUN_ALL=true
            shift
            ;;
        -c|--connectivity)
            TEST_CONNECTIVITY=true
            shift
            ;;
        -d|--dns)
            [[ -z "${2:-}" ]] && error_exit "--dns requires a hostname" 2
            TEST_DNS="$2"
            shift 2
            ;;
        -p|--ping)
            [[ -z "${2:-}" ]] && error_exit "--ping requires a hostname" 2
            TEST_PING="$2"
            shift 2
            ;;
        -t|--traceroute)
            [[ -z "${2:-}" ]] && error_exit "--traceroute requires a hostname" 2
            TEST_TRACEROUTE="$2"
            shift 2
            ;;
        -P|--port)
            [[ -z "${2:-}" ]] && error_exit "--port requires HOST:PORT format" 2
            TEST_PORT="$2"
            shift 2
            ;;
        -i|--interface)
            SHOW_INTERFACES=true
            shift
            ;;
        -r|--route)
            SHOW_ROUTES=true
            shift
            ;;
        -g|--gateway)
            TEST_GATEWAY=true
            shift
            ;;
        -s|--speed)
            TEST_SPEED=true
            shift
            ;;
        -n|--nameservers)
            TEST_NAMESERVERS=true
            shift
            ;;
        --report)
            GENERATE_REPORT=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            USE_COLOR=false
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "--output requires a file path" 2
            OUTPUT_FILE="$2"
            shift 2
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
        --timeout)
            [[ -z "${2:-}" ]] && error_exit "--timeout requires seconds" 2
            TIMEOUT="$2"
            shift 2
            ;;
        --count)
            [[ -z "${2:-}" ]] && error_exit "--count requires a number" 2
            PING_COUNT="$2"
            shift 2
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            # Assume it's a host for ping test
            TEST_PING="$1"
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# Run diagnostics
if [[ "$JSON_OUTPUT" == false ]]; then
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║              NETWORK DIAGNOSTICS                                ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
fi

if [[ "$GENERATE_REPORT" == true ]] || [[ "$RUN_ALL" == true ]]; then
    output=$(generate_diagnostic_report)
elif [[ "$JSON_OUTPUT" == true ]]; then
    output=$(generate_json_report)
else
    # Run individual tests
    [[ "$TEST_CONNECTIVITY" == true ]] && test_internet_connectivity || true
    [[ -n "$TEST_DNS" ]] && test_dns_resolution "$TEST_DNS" || true
    [[ -n "$TEST_PING" ]] && test_ping_host "$TEST_PING" || true
    [[ -n "$TEST_TRACEROUTE" ]] && test_traceroute_host "$TEST_TRACEROUTE" || true
    [[ -n "$TEST_PORT" ]] && test_port_connectivity "$TEST_PORT" || true
    [[ "$SHOW_INTERFACES" == true ]] && show_network_interfaces
    [[ "$SHOW_ROUTES" == true ]] && show_routing_table
    [[ "$TEST_GATEWAY" == true ]] && test_gateway_connectivity || true
    [[ "$TEST_NAMESERVERS" == true ]] && check_nameservers || true
    [[ "$TEST_SPEED" == true ]] && run_speed_test || true

    # If no tests specified, show usage
    if [[ $TESTS_TOTAL -eq 0 ]] && \
       [[ "$SHOW_INTERFACES" == false ]] && \
       [[ "$SHOW_ROUTES" == false ]]; then
        show_usage
        exit 0
    fi

    output=""
fi

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$output" > "$OUTPUT_FILE"
    success "Report saved to: $OUTPUT_FILE"
elif [[ -n "$output" ]]; then
    echo "$output"
fi

# Exit with appropriate code
if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 3
fi

verbose "Network diagnostics completed"
exit 0
