#!/bin/bash

################################################################################
# Script Name: port-scanner.sh
# Description: Advanced network port scanner with service detection, parallel
#              scanning, and multiple output formats. Supports TCP/UDP scanning,
#              banner grabbing, and common vulnerability checks.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./port-scanner.sh [options] <host>
#
# Options:
#   -h, --help              Show help message
#   -p, --ports PORTS       Ports to scan (default: common ports)
#                          Examples: 80, 1-1000, 80,443,8080
#   -t, --timeout SECONDS   Connection timeout (default: 2)
#   -j, --threads NUM       Parallel scanning threads (default: 50)
#   --tcp                   TCP scan (default)
#   --udp                   UDP scan (requires root)
#   --all                   Scan all ports (1-65535)
#   --common                Scan common ports only (default)
#   --top NUM               Scan top N most common ports
#   -b, --banner            Grab service banners
#   -s, --service           Detect services
#   -o, --output FILE       Save results to file
#   -f, --format FORMAT     Output format: text, json, csv, xml (default: text)
#   -v, --verbose           Verbose output
#   -q, --quiet             Quiet mode
#   --stealth               Stealth scan (SYN scan, requires root)
#
# Examples:
#   ./port-scanner.sh example.com
#   ./port-scanner.sh -p 1-1000 -j 100 192.168.1.1
#   ./port-scanner.sh --banner --service -o scan.json -f json example.com
#   sudo ./port-scanner.sh --udp --top 100 example.com
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependencies
#   4 - Permission denied
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

# Scanning parameters
TIMEOUT=2
THREADS=50
SCAN_TYPE="tcp"
GRAB_BANNER=false
DETECT_SERVICE=false
STEALTH_MODE=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"

# Port definitions
declare -a COMMON_PORTS=(20 21 22 23 25 53 80 110 111 135 139 143 443 445 993 995 1723 3306 3389 5900 8080 8443 8888)
declare -a TOP_100_PORTS=(7 9 13 21 22 23 25 26 37 53 79 80 81 88 106 110 111 113 119 135 139 143 144 179 199 389 427 443 444 445 465 513 514 515 543 544 548 554 587 631 646 873 990 993 995 1025 1026 1027 1028 1029 1110 1433 1720 1723 1755 1900 2000 2001 2049 2121 2717 3000 3128 3306 3389 3986 4899 5000 5009 5051 5060 5101 5190 5357 5432 5631 5666 5800 5900 6000 6001 6646 7000 7001 7002 7003 7004 7005 7006 7007 7008 7009 7100 7103 7106 7200 7201 7402 7435 7443 7496 7512 7625 7627 7676 7741 7777 7778 7800 7911 7920 7921 7999 8000 8001 8002 8007 8008 8009 8010 8011 8021 8022 8031 8042 8045 8080 8081 8082 8083 8084 8085 8086 8087 8088 8089 8090 8093 8099 8100 8180 8181 8192 8193 8194 8200 8222 8254 8290 8291 8292 8300 8333 8383 8400 8402 8443 8500 8600 8649 8651 8652 8654 8701 8800 8873 8888 8899 8994 9000 9001 9002 9003 9009 9010 9011 9040 9050 9071 9080 9081 9090 9091 9099 9100 9101 9102 9103 9110 9111 9200 9207 9220 9290 9415 9418 9485 9500 9502 9503 9535 9575 9593 9594 9595 9618 9666 9876 9877 9878 9898 9900 9917 9929 9943 9944 9968 9998 9999 10000 10001 10002 10003 10004 10009 10010 10012 10024 10025 10082 10180 10215 10243 10566 10616 10617 10621 10626 10628 10629 10778 11110 11111 11967 12000 12174 12265 12345 13456 13722 13782 13783 14000 14238 14441 14442 15000 15002 15003 15004 15660 15742 16000 16001 16012 16016 16018 16080 16113 16992 16993 17877 17988 18040 18101 18988 19101 19283 19315 19350 19780 19801 19842 20000 20005 20031 20221 20222 20828 21571 22939 23502 24444 24800 25734 25735 26214 27000 27352 27353 27355 27356 27715 28201 30000 30718 30951 31038 31337 32768 32769 32770 32771 32772 32773 32774 32775 32776 32777 32778 32779 32780 32781 32782 32783 32784 32785 33354 33899 34571 34572 34573 35500 38292 40193 40911 41511 42510 44176 44442 44443 44501 45100 48080 49152 49153 49154 49155 49156 49157 49158 49159 49160 49161 49163 49165 49167 49175 49176 49400 49999 50000 50001 50002 50003 50006 50300 50389 50500 50636 50800 51103 51493 52673 52822 52848 52869 54045 54328 55055 55056 55555 55600 56737 56738 57294 57797 58080 60020 60443 61532 61900 62078 63331 64623 64680 65000 65129 65389)

# Service signatures
declare -A SERVICE_SIGNATURES=(
    ["SSH"]="SSH-"
    ["HTTP"]="HTTP/"
    ["FTP"]="220"
    ["SMTP"]="220.*SMTP"
    ["POP3"]="\\+OK"
    ["IMAP"]="\\* OK"
    ["MySQL"]="mysql_native_password"
    ["PostgreSQL"]="FATAL"
    ["Redis"]="\\-ERR"
    ["MongoDB"]="MongoDB"
    ["Elasticsearch"]="\"cluster_name\""
)

# Results storage
declare -A SCAN_RESULTS
TOTAL_PORTS=0
OPEN_PORTS=0

################################################################################
# Port Scanning Functions
################################################################################

# Check if port is open using TCP
check_tcp_port() {
    local host="$1"
    local port="$2"
    local nc_output
    
    if command_exists nc; then
        # Use netcat with timeout
        if nc -z -w "$TIMEOUT" "$host" "$port" 2>/dev/null; then
            return 0
        fi
    elif command_exists timeout && command_exists bash; then
        # Use bash TCP socket with timeout
        if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            return 0
        fi
    else
        # Pure bash TCP socket (less reliable)
        if (echo >/dev/tcp/"$host"/"$port") 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Check if port is open using UDP (requires root)
check_udp_port() {
    local host="$1"
    local port="$2"
    
    if ! is_root; then
        log_error "UDP scanning requires root privileges"
        return 1
    fi
    
    if command_exists nc; then
        # Send empty UDP packet and check response
        if echo -n "" | nc -u -w "$TIMEOUT" "$host" "$port" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Perform stealth SYN scan (requires root)
check_syn_scan() {
    local host="$1"
    local port="$2"
    
    if ! is_root; then
        log_error "Stealth scanning requires root privileges"
        return 1
    fi
    
    # Use hping3 if available
    if command_exists hping3; then
        if hping3 -S -p "$port" -c 1 "$host" 2>/dev/null | grep -q "flags=SA"; then
            return 0
        fi
    fi
    
    return 1
}

# Grab service banner
grab_banner() {
    local host="$1"
    local port="$2"
    local banner=""
    
    if command_exists nc; then
        banner=$(echo "" | nc -w "$TIMEOUT" "$host" "$port" 2>/dev/null | head -n1 | tr -d '\r\n' || true)
    elif command_exists timeout; then
        banner=$(timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port; echo '' >&3; head -n1 <&3" 2>/dev/null | tr -d '\r\n' || true)
    fi
    
    echo "$banner"
}

# Detect service from banner
detect_service_from_banner() {
    local banner="$1"
    local service="Unknown"
    
    for svc in "${!SERVICE_SIGNATURES[@]}"; do
        if [[ "$banner" =~ ${SERVICE_SIGNATURES[$svc]} ]]; then
            service="$svc"
            break
        fi
    done
    
    echo "$service"
}

# Detect service from port number
detect_service_from_port() {
    local port="$1"
    
    case "$port" in
        20) echo "FTP-DATA" ;;
        21) echo "FTP" ;;
        22) echo "SSH" ;;
        23) echo "Telnet" ;;
        25) echo "SMTP" ;;
        53) echo "DNS" ;;
        80) echo "HTTP" ;;
        110) echo "POP3" ;;
        143) echo "IMAP" ;;
        443) echo "HTTPS" ;;
        445) echo "SMB" ;;
        3306) echo "MySQL" ;;
        3389) echo "RDP" ;;
        5432) echo "PostgreSQL" ;;
        5900) echo "VNC" ;;
        6379) echo "Redis" ;;
        8080) echo "HTTP-Proxy" ;;
        8443) echo "HTTPS-Alt" ;;
        27017) echo "MongoDB" ;;
        *) echo "Unknown" ;;
    esac
}

# Scan single port
scan_port() {
    local host="$1"
    local port="$2"
    local status="closed"
    local service=""
    local banner=""
    
    ((TOTAL_PORTS++))
    
    # Check if port is open
    case "$SCAN_TYPE" in
        tcp)
            if check_tcp_port "$host" "$port"; then
                status="open"
            fi
            ;;
        udp)
            if check_udp_port "$host" "$port"; then
                status="open"
            fi
            ;;
        syn)
            if check_syn_scan "$host" "$port"; then
                status="open"
            fi
            ;;
    esac
    
    if [[ "$status" == "open" ]]; then
        ((OPEN_PORTS++))
        
        # Grab banner if requested
        if [[ "$GRAB_BANNER" == true ]] && [[ "$SCAN_TYPE" == "tcp" ]]; then
            banner=$(grab_banner "$host" "$port")
        fi
        
        # Detect service
        if [[ "$DETECT_SERVICE" == true ]]; then
            if [[ -n "$banner" ]]; then
                service=$(detect_service_from_banner "$banner")
            else
                service=$(detect_service_from_port "$port")
            fi
        fi
        
        # Store result
        SCAN_RESULTS["$port"]="$status|$service|$banner"
        
        # Display result
        if [[ "$QUIET" != true ]]; then
            display_port_result "$port" "$status" "$service" "$banner"
        fi
    else
        # Only store closed ports in verbose mode
        if [[ "$VERBOSE" == true ]]; then
            SCAN_RESULTS["$port"]="$status||"
            if [[ "$QUIET" != true ]]; then
                display_port_result "$port" "$status" "" ""
            fi
        fi
    fi
}

# Display port result
display_port_result() {
    local port="$1"
    local status="$2"
    local service="$3"
    local banner="$4"
    
    case "$OUTPUT_FORMAT" in
        text)
            if [[ "$status" == "open" ]]; then
                printf "${GREEN}%-6d %-10s${NC}" "$port" "$status"
                [[ -n "$service" ]] && printf " ${CYAN}%-15s${NC}" "$service"
                [[ -n "$banner" ]] && printf " ${GRAY}%s${NC}" "${banner:0:50}"
                echo
            elif [[ "$VERBOSE" == true ]]; then
                printf "${RED}%-6d %-10s${NC}\n" "$port" "$status"
            fi
            ;;
    esac
}

################################################################################
# Parallel Scanning
################################################################################

# Worker function for parallel scanning
scan_worker() {
    local host="$1"
    local port
    
    while read -r port; do
        scan_port "$host" "$port"
    done
}

# Parallel port scanning
parallel_scan() {
    local host="$1"
    local ports=("${@:2}")
    local fifo_dir=$(mktemp -d)
    local fifo="$fifo_dir/ports"
    
    # Create named pipe
    mkfifo "$fifo"
    
    # Start worker processes
    for ((i=0; i<THREADS; i++)); do
        scan_worker "$host" < "$fifo" &
    done
    
    # Feed ports to workers
    for port in "${ports[@]}"; do
        echo "$port"
    done > "$fifo"
    
    # Wait for all workers
    wait
    
    # Cleanup
    rm -rf "$fifo_dir"
}

################################################################################
# Output Functions
################################################################################

# Generate JSON output
generate_json_output() {
    local host="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "{"
    echo "  \"host\": \"$host\","
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"scan_type\": \"$SCAN_TYPE\","
    echo "  \"total_ports\": $TOTAL_PORTS,"
    echo "  \"open_ports\": $OPEN_PORTS,"
    echo "  \"results\": ["
    
    local first=true
    for port in $(echo "${!SCAN_RESULTS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r status service banner <<< "${SCAN_RESULTS[$port]}"
        
        [[ "$status" != "open" ]] && [[ "$VERBOSE" != true ]] && continue
        
        [[ "$first" != true ]] && echo ","
        echo -n "    {\"port\": $port, \"status\": \"$status\""
        [[ -n "$service" ]] && echo -n ", \"service\": \"$service\""
        [[ -n "$banner" ]] && echo -n ", \"banner\": \"$(echo "$banner" | sed 's/"/\\"/g')\""
        echo -n "}"
        
        first=false
    done
    
    echo
    echo "  ]"
    echo "}"
}

# Generate CSV output
generate_csv_output() {
    echo "Port,Status,Service,Banner"
    
    for port in $(echo "${!SCAN_RESULTS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r status service banner <<< "${SCAN_RESULTS[$port]}"
        [[ "$status" != "open" ]] && [[ "$VERBOSE" != true ]] && continue
        
        echo "$port,$status,$service,\"$banner\""
    done
}

# Generate XML output
generate_xml_output() {
    local host="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    echo "<portscan>"
    echo "  <host>$host</host>"
    echo "  <timestamp>$timestamp</timestamp>"
    echo "  <scan_type>$SCAN_TYPE</scan_type>"
    echo "  <summary>"
    echo "    <total_ports>$TOTAL_PORTS</total_ports>"
    echo "    <open_ports>$OPEN_PORTS</open_ports>"
    echo "  </summary>"
    echo "  <ports>"
    
    for port in $(echo "${!SCAN_RESULTS[@]}" | tr ' ' '\n' | sort -n); do
        IFS='|' read -r status service banner <<< "${SCAN_RESULTS[$port]}"
        [[ "$status" != "open" ]] && [[ "$VERBOSE" != true ]] && continue
        
        echo "    <port number=\"$port\" status=\"$status\">"
        [[ -n "$service" ]] && echo "      <service>$service</service>"
        [[ -n "$banner" ]] && echo "      <banner><![CDATA[$banner]]></banner>"
        echo "    </port>"
    done
    
    echo "  </ports>"
    echo "</portscan>"
}

################################################################################
# Main Functions
################################################################################

# Parse port specification
parse_ports() {
    local port_spec="$1"
    local ports=()
    
    if [[ "$port_spec" == "all" ]]; then
        # All ports
        for ((i=1; i<=65535; i++)); do
            ports+=("$i")
        done
    elif [[ "$port_spec" == "common" ]]; then
        # Common ports
        ports=("${COMMON_PORTS[@]}")
    elif [[ "$port_spec" =~ ^top-([0-9]+)$ ]]; then
        # Top N ports
        local n="${BASH_REMATCH[1]}"
        ports=("${TOP_100_PORTS[@]:0:$n}")
    elif [[ "$port_spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        # Port range
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        for ((i=start; i<=end && i<=65535; i++)); do
            ports+=("$i")
        done
    else
        # Comma-separated ports
        IFS=',' read -ra ports <<< "$port_spec"
    fi
    
    echo "${ports[@]}"
}

# Validate host
validate_host() {
    local host="$1"
    
    # Check if it's an IP address
    if validate_ip "$host"; then
        echo "$host"
        return 0
    fi
    
    # Try to resolve hostname
    if command_exists host; then
        if host "$host" > /dev/null 2>&1; then
            echo "$host"
            return 0
        fi
    elif command_exists nslookup; then
        if nslookup "$host" > /dev/null 2>&1; then
            echo "$host"
            return 0
        fi
    elif command_exists getent; then
        if getent hosts "$host" > /dev/null 2>&1; then
            echo "$host"
            return 0
        fi
    fi
    
    return 1
}

# Main scanning function
perform_scan() {
    local host="$1"
    local port_spec="$2"
    
    # Validate host
    if ! validate_host "$host" > /dev/null; then
        error_exit "Invalid host: $host" 2
    fi
    
    # Parse ports
    local ports=($(parse_ports "$port_spec"))
    
    if [[ ${#ports[@]} -eq 0 ]]; then
        error_exit "No ports to scan" 2
    fi
    
    # Display scan info
    if [[ "$QUIET" != true ]]; then
        print_header "PORT SCANNER" 60
        echo "Host: $host"
        echo "Scan Type: ${SCAN_TYPE^^}"
        echo "Ports: ${#ports[@]} ports"
        echo "Threads: $THREADS"
        echo "Timeout: ${TIMEOUT}s"
        [[ "$GRAB_BANNER" == true ]] && echo "Banner Grabbing: Enabled"
        [[ "$DETECT_SERVICE" == true ]] && echo "Service Detection: Enabled"
        print_separator
        
        if [[ "$OUTPUT_FORMAT" == "text" ]]; then
            printf "${BOLD}%-6s %-10s %-15s %s${NC}\n" "PORT" "STATE" "SERVICE" "BANNER"
            print_separator
        fi
    fi
    
    # Perform scan
    if [[ ${#ports[@]} -le 10 ]] || [[ "$THREADS" -eq 1 ]]; then
        # Sequential scan for small port lists
        for port in "${ports[@]}"; do
            scan_port "$host" "$port"
        done
    else
        # Parallel scan for larger port lists
        parallel_scan "$host" "${ports[@]}"
    fi
    
    # Generate output
    case "$OUTPUT_FORMAT" in
        json)
            generate_json_output "$host"
            ;;
        csv)
            generate_csv_output
            ;;
        xml)
            generate_xml_output "$host"
            ;;
        text)
            if [[ "$QUIET" != true ]]; then
                print_separator
                echo "Scan complete: $OPEN_PORTS open ports found out of $TOTAL_PORTS scanned"
            fi
            ;;
    esac
}

# Show usage
show_usage() {
    cat << EOF
${WHITE}Advanced Port Scanner${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] <host>

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -p, --ports PORTS       Ports to scan (default: common ports)
                           Examples: 80, 1-1000, 80,443,8080
    -t, --timeout SECONDS   Connection timeout (default: 2)
    -j, --threads NUM       Parallel scanning threads (default: 50)
    --tcp                   TCP scan (default)
    --udp                   UDP scan (requires root)
    --all                   Scan all ports (1-65535)
    --common                Scan common ports only (default)
    --top NUM               Scan top N most common ports
    -b, --banner            Grab service banners
    -s, --service           Detect services
    -o, --output FILE       Save results to file
    -f, --format FORMAT     Output format: text, json, csv, xml
    -v, --verbose           Verbose output
    -q, --quiet             Quiet mode
    --stealth               Stealth scan (SYN scan, requires root)

${CYAN}Examples:${NC}
    # Scan common ports
    $(basename "$0") example.com
    
    # Scan specific ports
    $(basename "$0") -p 80,443,8080 example.com
    
    # Scan port range with banner grabbing
    $(basename "$0") -p 1-1000 --banner example.com
    
    # Fast scan with 100 threads
    $(basename "$0") -p 1-65535 -j 100 192.168.1.1
    
    # Service detection with JSON output
    $(basename "$0") --service -o scan.json -f json example.com
    
    # UDP scan (requires root)
    sudo $(basename "$0") --udp --top 100 example.com

${CYAN}Output Formats:${NC}
    text    Human-readable text output (default)
    json    JSON format for parsing
    csv     CSV format for spreadsheets
    xml     XML format for integration

${CYAN}Notes:${NC}
    - UDP and stealth scanning require root privileges
    - Large port ranges benefit from increased threads
    - Banner grabbing may slow down scans
    - Service detection uses both banners and port numbers

EOF
}

################################################################################
# Main Execution
################################################################################

# Check for help
if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

# Initialize variables
HOST=""
PORT_SPEC="common"
QUIET=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -p|--ports)
            [[ -z "${2:-}" ]] && error_exit "Ports required" 2
            PORT_SPEC="$2"
            shift 2
            ;;
        -t|--timeout)
            [[ -z "${2:-}" ]] && error_exit "Timeout required" 2
            TIMEOUT="$2"
            shift 2
            ;;
        -j|--threads)
            [[ -z "${2:-}" ]] && error_exit "Thread count required" 2
            THREADS="$2"
            shift 2
            ;;
        --tcp)
            SCAN_TYPE="tcp"
            shift
            ;;
        --udp)
            SCAN_TYPE="udp"
            shift
            ;;
        --stealth|--syn)
            SCAN_TYPE="syn"
            STEALTH_MODE=true
            shift
            ;;
        --all)
            PORT_SPEC="all"
            shift
            ;;
        --common)
            PORT_SPEC="common"
            shift
            ;;
        --top)
            [[ -z "${2:-}" ]] && error_exit "Number required" 2
            PORT_SPEC="top-$2"
            shift 2
            ;;
        -b|--banner)
            GRAB_BANNER=true
            shift
            ;;
        -s|--service)
            DETECT_SERVICE=true
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            HOST="$1"
            shift
            ;;
    esac
done

# Validate arguments
[[ -z "$HOST" ]] && error_exit "Host required" 2

# Check privileges for special scan types
if [[ "$SCAN_TYPE" == "udp" ]] || [[ "$SCAN_TYPE" == "syn" ]]; then
    require_root
fi

# Perform scan
if [[ -n "$OUTPUT_FILE" ]]; then
    perform_scan "$HOST" "$PORT_SPEC" > "$OUTPUT_FILE"
    [[ "$QUIET" != true ]] && success "Results saved to $OUTPUT_FILE"
else
    perform_scan "$HOST" "$PORT_SPEC"
fi
