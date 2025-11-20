#!/bin/bash

################################################################################
# Script Name: system-info.sh
# Description: Comprehensive system information gathering and reporting tool.
#              Collects hardware, software, network, and performance data with
#              multiple output formats and detailed analysis capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./system-info.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -a, --all               Show all information
#   -s, --system            Show system information
#   -c, --cpu               Show CPU information
#   -m, --memory            Show memory information
#   -d, --disk              Show disk information
#   -n, --network           Show network information
#   -p, --processes         Show process information
#   -u, --users             Show user information
#   -j, --json              Output in JSON format
#   -o, --output FILE       Save output to file
#   -l, --log               Create detailed log file
#   --hardware              Show detailed hardware info
#   --software              Show installed software
#   --services              Show system services
#
# Examples:
#   ./system-info.sh --all
#   ./system-info.sh --system --cpu --memory
#   ./system-info.sh --json -o system-report.json
#   ./system-info.sh --hardware --software
#
# Dependencies:
#   - lscpu, lsblk, lshw (optional for detailed info)
#   - dmidecode (optional for hardware details)
#
# Exit Codes:
#   0 - Success
#   1 - General error
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
SHOW_ALL=false
SHOW_SYSTEM=false
SHOW_CPU=false
SHOW_MEMORY=false
SHOW_DISK=false
SHOW_NETWORK=false
SHOW_PROCESSES=false
SHOW_USERS=false
SHOW_HARDWARE=false
SHOW_SOFTWARE=false
SHOW_SERVICES=false
JSON_OUTPUT=false
OUTPUT_FILE=""
CREATE_LOG=false
USE_COLOR=true

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

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}" >&2
    fi
}

section_header() {
    if [[ "$JSON_OUTPUT" == false ]]; then
        echo ""
        echo -e "${WHITE}━━━ $1 ━━━${NC}"
    fi
}

show_usage() {
    cat << EOF
${WHITE}System Information - Comprehensive System Reporting Tool${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --all               Show all information
    -s, --system            Show system information
    -c, --cpu               Show CPU information
    -m, --memory            Show memory information
    -d, --disk              Show disk information
    -n, --network           Show network information
    -p, --processes         Show process information
    -u, --users             Show user information
    -j, --json              Output in JSON format
    -o, --output FILE       Save output to file
    -l, --log               Create detailed log file
    --hardware              Show detailed hardware info
    --software              Show installed software summary
    --services              Show system services status

${CYAN}Examples:${NC}
    # Show all information
    $SCRIPT_NAME --all

    # Show specific categories
    $SCRIPT_NAME --system --cpu --memory

    # Generate JSON report
    $SCRIPT_NAME --all --json -o system-report.json

    # Quick system overview
    $SCRIPT_NAME -s -c -m -d

    # Detailed hardware report
    $SCRIPT_NAME --hardware --software

${CYAN}Features:${NC}
    • Complete system information gathering
    • Hardware detection and reporting
    • Software inventory
    • Network configuration details
    • User and process information
    • Service status reporting
    • JSON export capability
    • Detailed logging

EOF
}

################################################################################
# System Information Functions
################################################################################

get_system_info() {
    section_header "SYSTEM INFORMATION"
    
    local hostname=$(hostname)
    local kernel=$(uname -r)
    local os=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d'"' -f2 || echo "Unknown")
    local architecture=$(uname -m)
    local uptime=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    local load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    local date=$(date '+%Y-%m-%d %H:%M:%S')
    local timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || date +%Z)
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "system": {
    "hostname": "$hostname",
    "kernel": "$kernel",
    "os": "$os",
    "architecture": "$architecture",
    "uptime": "$uptime",
    "load_average": "$load",
    "date": "$date",
    "timezone": "$timezone"
  }
}
EOF
    else
        echo -e "${CYAN}Hostname:${NC}        $hostname"
        echo -e "${CYAN}Operating System:${NC} $os"
        echo -e "${CYAN}Kernel:${NC}          $kernel"
        echo -e "${CYAN}Architecture:${NC}    $architecture"
        echo -e "${CYAN}Uptime:${NC}          $uptime"
        echo -e "${CYAN}Load Average:${NC}    $load"
        echo -e "${CYAN}Date/Time:${NC}       $date"
        echo -e "${CYAN}Timezone:${NC}        $timezone"
    fi
}

get_cpu_info() {
    section_header "CPU INFORMATION"
    
    local cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs || cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | xargs)
    local cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
    local cpu_threads=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}' || echo "$cpu_cores")
    local cpu_arch=$(lscpu 2>/dev/null | grep "Architecture" | awk '{print $2}' || uname -m)
    local cpu_mhz=$(lscpu 2>/dev/null | grep "CPU MHz" | awk '{print $3}' || echo "N/A")
    local cpu_max_mhz=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{print $4}' || echo "N/A")
    local cpu_cache=$(lscpu 2>/dev/null | grep "L3 cache" | awk '{print $3, $4}' || echo "N/A")
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
  "cpu": {
    "model": "$cpu_model",
    "cores": $cpu_cores,
    "threads": $cpu_threads,
    "architecture": "$cpu_arch",
    "current_mhz": "$cpu_mhz",
    "max_mhz": "$cpu_max_mhz",
    "cache": "$cpu_cache",
    "usage_percent": $cpu_usage
  },
EOF
    else
        echo -e "${CYAN}Model:${NC}           $cpu_model"
        echo -e "${CYAN}Cores:${NC}           $cpu_cores"
        echo -e "${CYAN}Threads:${NC}         $cpu_threads"
        echo -e "${CYAN}Architecture:${NC}    $cpu_arch"
        echo -e "${CYAN}Current Speed:${NC}   ${cpu_mhz} MHz"
        echo -e "${CYAN}Max Speed:${NC}       ${cpu_max_mhz} MHz"
        echo -e "${CYAN}Cache:${NC}           $cpu_cache"
        echo -e "${CYAN}Usage:${NC}           ${cpu_usage}%"
    fi
}

get_memory_info() {
    section_header "MEMORY INFORMATION"
    
    local mem_total=$(free -m | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -m | awk '/^Mem:/ {print $3}')
    local mem_free=$(free -m | awk '/^Mem:/ {print $4}')
    local mem_available=$(free -m | awk '/^Mem:/ {print $7}')
    local mem_percent=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc)
    
    local swap_total=$(free -m | awk '/^Swap:/ {print $2}')
    local swap_used=$(free -m | awk '/^Swap:/ {print $3}')
    local swap_free=$(free -m | awk '/^Swap:/ {print $4}')
    local swap_percent=0
    if [[ $swap_total -gt 0 ]]; then
        swap_percent=$(echo "scale=2; ($swap_used / $swap_total) * 100" | bc)
    fi
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
  "memory": {
    "ram": {
      "total_mb": $mem_total,
      "used_mb": $mem_used,
      "free_mb": $mem_free,
      "available_mb": $mem_available,
      "usage_percent": $mem_percent
    },
    "swap": {
      "total_mb": $swap_total,
      "used_mb": $swap_used,
      "free_mb": $swap_free,
      "usage_percent": $swap_percent
    }
  },
EOF
    else
        echo -e "${CYAN}RAM Total:${NC}       ${mem_total} MB"
        echo -e "${CYAN}RAM Used:${NC}        ${mem_used} MB (${mem_percent}%)"
        echo -e "${CYAN}RAM Free:${NC}        ${mem_free} MB"
        echo -e "${CYAN}RAM Available:${NC}   ${mem_available} MB"
        echo ""
        echo -e "${CYAN}Swap Total:${NC}      ${swap_total} MB"
        echo -e "${CYAN}Swap Used:${NC}       ${swap_used} MB (${swap_percent}%)"
        echo -e "${CYAN}Swap Free:${NC}       ${swap_free} MB"
    fi
}

get_disk_info() {
    section_header "DISK INFORMATION"
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        echo '  "disks": ['
        local first=true
        while read -r line; do
            local device=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local avail=$(echo "$line" | awk '{print $4}')
            local percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
            local mount=$(echo "$line" | awk '{print $6}')
            
            [[ "$first" == false ]] && echo ","
            first=false
            
            cat << EOF
    {
      "device": "$device",
      "size": "$size",
      "used": "$used",
      "available": "$avail",
      "usage_percent": $percent,
      "mount_point": "$mount"
    }
EOF
        done < <(df -h | grep -E '^/dev/' | grep -v '/snap/')
        echo '  ],'
    else
        printf "${CYAN}%-20s %-8s %-8s %-8s %-6s %-s${NC}\n" "Device" "Size" "Used" "Avail" "Use%" "Mounted on"
        df -h | grep -E '^/dev/' | grep -v '/snap/' | while read -r line; do
            printf "%-20s %-8s %-8s %-8s %-6s %-s\n" $line
        done
    fi
}

get_network_info() {
    section_header "NETWORK INFORMATION"
    
    local hostname=$(hostname)
    local fqdn=$(hostname -f 2>/dev/null || echo "N/A")
    local primary_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "N/A")
    local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "N/A")
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    local dns_servers=$(cat /etc/resolv.conf 2>/dev/null | grep ^nameserver | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
  "network": {
    "hostname": "$hostname",
    "fqdn": "$fqdn",
    "primary_ip": "$primary_ip",
    "public_ip": "$public_ip",
    "gateway": "$gateway",
    "dns_servers": "$dns_servers",
    "interfaces": [
EOF
        local first=true
        for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
            local state=$(ip link show "$iface" | grep -oP 'state \K\w+')
            local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1 || echo "N/A")
            local mac=$(ip link show "$iface" | grep -oP 'link/ether \K\S+' || echo "N/A")
            
            [[ "$first" == false ]] && echo ","
            first=false
            
            cat << EOF
      {
        "name": "$iface",
        "state": "$state",
        "ip": "$ip",
        "mac": "$mac"
      }
EOF
        done
        echo '    ]'
        echo '  },'
    else
        echo -e "${CYAN}Hostname:${NC}        $hostname"
        echo -e "${CYAN}FQDN:${NC}            $fqdn"
        echo -e "${CYAN}Primary IP:${NC}      $primary_ip"
        echo -e "${CYAN}Public IP:${NC}       $public_ip"
        echo -e "${CYAN}Gateway:${NC}         $gateway"
        echo -e "${CYAN}DNS Servers:${NC}     $dns_servers"
        echo ""
        echo -e "${CYAN}Network Interfaces:${NC}"
        for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
            local state=$(ip link show "$iface" | grep -oP 'state \K\w+')
            local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1 || echo "N/A")
            local mac=$(ip link show "$iface" | grep -oP 'link/ether \K\S+' || echo "N/A")
            echo -e "  ${CYAN}$iface:${NC} $state - IP: $ip - MAC: $mac"
        done
    fi
}

get_process_info() {
    section_header "PROCESS INFORMATION"
    
    local total_processes=$(ps aux | wc -l)
    local running_processes=$(ps aux | awk '$8 == "R" || $8 == "R+"' | wc -l)
    local sleeping_processes=$(ps aux | awk '$8 ~ /^S/' | wc -l)
    local zombie_processes=$(ps aux | awk '$8 == "Z"' | wc -l)
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
  "processes": {
    "total": $total_processes,
    "running": $running_processes,
    "sleeping": $sleeping_processes,
    "zombie": $zombie_processes,
    "top_cpu": [
EOF
        local first=true
        ps aux --sort=-%cpu | head -6 | tail -5 | while read -r line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            local mem=$(echo "$line" | awk '{print $4}')
            local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i" "; print ""}' | sed 's/ $//')
            
            [[ "$first" == false ]] && echo ","
            first=false
            
            echo "      {\"pid\": $pid, \"cpu\": $cpu, \"memory\": $mem, \"command\": \"$cmd\"}"
        done
        echo '    ]'
        echo '  },'
    else
        echo -e "${CYAN}Total Processes:${NC}    $total_processes"
        echo -e "${CYAN}Running:${NC}            $running_processes"
        echo -e "${CYAN}Sleeping:${NC}           $sleeping_processes"
        echo -e "${CYAN}Zombie:${NC}             $zombie_processes"
        echo ""
        echo -e "${CYAN}Top CPU Consumers:${NC}"
        printf "  %-8s %-6s %-6s %-s\n" "PID" "CPU%" "MEM%" "Command"
        ps aux --sort=-%cpu | head -6 | tail -5 | awk '{printf "  %-8s %-6s %-6s %-s\n", $2, $3"%", $4"%", $11}'
    fi
}

get_user_info() {
    section_header "USER INFORMATION"
    
    local current_user=$(whoami)
    local total_users=$(cat /etc/passwd | grep -v nologin | grep -v false | wc -l)
    local logged_in=$(who | wc -l)
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
  "users": {
    "current": "$current_user",
    "total_system_users": $total_users,
    "logged_in": $logged_in,
    "active_sessions": [
EOF
        local first=true
        who | while read -r line; do
            local user=$(echo "$line" | awk '{print $1}')
            local tty=$(echo "$line" | awk '{print $2}')
            local from=$(echo "$line" | awk '{print $5}' | tr -d '()')
            
            [[ "$first" == false ]] && echo ","
            first=false
            
            echo "      {\"user\": \"$user\", \"tty\": \"$tty\", \"from\": \"$from\"}"
        done
        echo '    ]'
        echo '  }'
        echo '}'
    else
        echo -e "${CYAN}Current User:${NC}       $current_user"
        echo -e "${CYAN}Total Users:${NC}        $total_users"
        echo -e "${CYAN}Logged In:${NC}          $logged_in"
        echo ""
        echo -e "${CYAN}Active Sessions:${NC}"
        who | awk '{printf "  %-12s %-8s %s\n", $1, $2, $5}'
    fi
}

get_hardware_info() {
    section_header "HARDWARE INFORMATION"
    
    verbose "Gathering hardware information..."
    
    # Check for hardware info tools
    if command -v dmidecode &> /dev/null && [[ $EUID -eq 0 ]]; then
        local manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null)
        local product=$(dmidecode -s system-product-name 2>/dev/null)
        local serial=$(dmidecode -s system-serial-number 2>/dev/null)
        local bios_version=$(dmidecode -s bios-version 2>/dev/null)
        local bios_date=$(dmidecode -s bios-release-date 2>/dev/null)
    else
        local manufacturer="N/A (requires root + dmidecode)"
        local product="N/A"
        local serial="N/A"
        local bios_version="N/A"
        local bios_date="N/A"
    fi
    
    echo -e "${CYAN}Manufacturer:${NC}    $manufacturer"
    echo -e "${CYAN}Product:${NC}         $product"
    echo -e "${CYAN}Serial Number:${NC}   $serial"
    echo -e "${CYAN}BIOS Version:${NC}    $bios_version"
    echo -e "${CYAN}BIOS Date:${NC}       $bios_date"
}

get_software_info() {
    section_header "SOFTWARE INFORMATION"
    
    # Package manager detection
    local pkg_manager="unknown"
    local pkg_count=0
    
    if command -v dpkg &> /dev/null; then
        pkg_manager="dpkg (Debian/Ubuntu)"
        pkg_count=$(dpkg -l | grep ^ii | wc -l)
    elif command -v rpm &> /dev/null; then
        pkg_manager="rpm (Red Hat/Fedora)"
        pkg_count=$(rpm -qa | wc -l)
    elif command -v pacman &> /dev/null; then
        pkg_manager="pacman (Arch)"
        pkg_count=$(pacman -Q | wc -l)
    fi
    
    echo -e "${CYAN}Package Manager:${NC}  $pkg_manager"
    echo -e "${CYAN}Packages Installed:${NC} $pkg_count"
    
    # Shell info
    echo -e "${CYAN}Default Shell:${NC}   $SHELL"
    echo -e "${CYAN}Shell Version:${NC}   $($SHELL --version | head -1)"
}

get_services_info() {
    section_header "SYSTEM SERVICES"
    
    if command -v systemctl &> /dev/null; then
        local total=$(systemctl list-units --type=service --all --no-pager --no-legend | wc -l)
        local active=$(systemctl list-units --type=service --state=active --no-pager --no-legend | wc -l)
        local failed=$(systemctl list-units --type=service --state=failed --no-pager --no-legend | wc -l)
        
        echo -e "${CYAN}Total Services:${NC}   $total"
        echo -e "${CYAN}Active:${NC}           $active"
        echo -e "${CYAN}Failed:${NC}           $failed"
        
        if [[ $failed -gt 0 ]]; then
            echo ""
            echo -e "${YELLOW}Failed Services:${NC}"
            systemctl list-units --type=service --state=failed --no-pager --no-legend | awk '{print "  "$1}'
        fi
    else
        echo "systemd not available"
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
        -a|--all)
            SHOW_ALL=true
            shift
            ;;
        -s|--system)
            SHOW_SYSTEM=true
            shift
            ;;
        -c|--cpu)
            SHOW_CPU=true
            shift
            ;;
        -m|--memory)
            SHOW_MEMORY=true
            shift
            ;;
        -d|--disk)
            SHOW_DISK=true
            shift
            ;;
        -n|--network)
            SHOW_NETWORK=true
            shift
            ;;
        -p|--processes)
            SHOW_PROCESSES=true
            shift
            ;;
        -u|--users)
            SHOW_USERS=true
            shift
            ;;
        --hardware)
            SHOW_HARDWARE=true
            shift
            ;;
        --software)
            SHOW_SOFTWARE=true
            shift
            ;;
        --services)
            SHOW_SERVICES=true
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
            CREATE_LOG=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

# If no specific options, show system, cpu, memory, disk
if [[ "$SHOW_ALL" == false ]] && \
   [[ "$SHOW_SYSTEM" == false ]] && \
   [[ "$SHOW_CPU" == false ]] && \
   [[ "$SHOW_MEMORY" == false ]] && \
   [[ "$SHOW_DISK" == false ]] && \
   [[ "$SHOW_NETWORK" == false ]] && \
   [[ "$SHOW_PROCESSES" == false ]] && \
   [[ "$SHOW_USERS" == false ]] && \
   [[ "$SHOW_HARDWARE" == false ]] && \
   [[ "$SHOW_SOFTWARE" == false ]] && \
   [[ "$SHOW_SERVICES" == false ]]; then
    SHOW_SYSTEM=true
    SHOW_CPU=true
    SHOW_MEMORY=true
    SHOW_DISK=true
fi

# Set all flags if --all is specified
if [[ "$SHOW_ALL" == true ]]; then
    SHOW_SYSTEM=true
    SHOW_CPU=true
    SHOW_MEMORY=true
    SHOW_DISK=true
    SHOW_NETWORK=true
    SHOW_PROCESSES=true
    SHOW_USERS=true
    SHOW_HARDWARE=true
    SHOW_SOFTWARE=true
    SHOW_SERVICES=true
fi

# Header
if [[ "$JSON_OUTPUT" == false ]]; then
    echo ""
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║             SYSTEM INFORMATION REPORT                          ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
fi

# Collect information
output=""

if [[ "$JSON_OUTPUT" == true ]]; then
    output+="{\n"
fi

[[ "$SHOW_SYSTEM" == true ]] && output+="$(get_system_info)\n"
[[ "$SHOW_CPU" == true ]] && output+="$(get_cpu_info)\n"
[[ "$SHOW_MEMORY" == true ]] && output+="$(get_memory_info)\n"
[[ "$SHOW_DISK" == true ]] && output+="$(get_disk_info)\n"
[[ "$SHOW_NETWORK" == true ]] && output+="$(get_network_info)\n"
[[ "$SHOW_PROCESSES" == true ]] && output+="$(get_process_info)\n"
[[ "$SHOW_USERS" == true ]] && output+="$(get_user_info)\n"
[[ "$SHOW_HARDWARE" == true ]] && output+="$(get_hardware_info)\n"
[[ "$SHOW_SOFTWARE" == true ]] && output+="$(get_software_info)\n"
[[ "$SHOW_SERVICES" == true ]] && output+="$(get_services_info)\n"

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "$output" > "$OUTPUT_FILE"
    success "Report saved to: $OUTPUT_FILE"
else
    echo -e "$output"
fi

verbose "System information gathering completed"

