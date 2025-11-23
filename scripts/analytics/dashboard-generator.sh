#!/bin/bash

################################################################################
# Script Name: dashboard-generator.sh
# Description: Custom dashboard generator that creates real-time terminal and HTML
#              dashboards from metrics, logs, and system data with customizable
#              layouts, widgets, and auto-refresh capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./dashboard-generator.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -c, --config FILE       Dashboard config file
#   -t, --type TYPE         Dashboard type: terminal, html, both
#   --widgets WIDGET,...    Widgets to display (cpu,memory,disk,network,logs,custom)
#   --layout LAYOUT         Layout: single, split, grid
#   --refresh SECONDS       Auto-refresh interval (default: 5)
#   --title TITLE           Dashboard title
#   --theme THEME           Color theme: dark, light, matrix, minimal
#   -o, --output FILE       Save HTML to file
#   --data-source FILE      Custom data source
#   --alert-threshold KEY=VAL  Alert thresholds
#   --no-color              Disable colors (terminal mode)
#   -v, --verbose           Verbose output
#
# Examples:
#   ./dashboard-generator.sh --widgets cpu,memory,disk
#   ./dashboard-generator.sh -t html -o dashboard.html --theme dark
#   ./dashboard-generator.sh --layout grid --refresh 10
#   ./dashboard-generator.sh -c mydashboard.conf
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

CONFIG_FILE=""
DASHBOARD_TYPE="terminal"
WIDGETS=("cpu" "memory" "disk")
LAYOUT="grid"
REFRESH_INTERVAL=5
DASHBOARD_TITLE="System Dashboard"
THEME="dark"
OUTPUT_FILE=""
DATA_SOURCE=""
declare -A ALERT_THRESHOLDS
USE_COLOR=true
VERBOSE=false

################################################################################
# Widget Functions
################################################################################

widget_cpu() {
    echo -e "${BOLD_CYAN}CPU${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    # CPU bar
    local bar_width=20
    local filled=$(printf "%.0f" "$(echo "$cpu_usage * $bar_width / 100" | bc -l)")
    local empty=$((bar_width - filled))
    
    printf "Usage: %5.1f%% [" "$cpu_usage"
    
    # Color based on usage
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        echo -n -e "${RED}"
    elif (( $(echo "$cpu_usage > 50" | bc -l) )); then
        echo -n -e "${YELLOW}"
    else
        echo -n -e "${GREEN}"
    fi
    
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    echo -n -e "${NC}"
    for ((i=0; i<empty; i++)); do echo -n "░"; done
    echo "]"
    
    echo "Load: $load_avg"
    
    # Top processes
    echo
    echo "Top Processes:"
    ps aux --sort=-%cpu | head -4 | tail -3 | awk '{printf "  %-12s %5.1f%%\n", substr($11,1,12), $3}'
}

widget_memory() {
    echo -e "${BOLD_CYAN}MEMORY${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    local mem_total=$(free -h | awk 'NR==2 {print $2}')
    local mem_used=$(free -h | awk 'NR==2 {print $3}')
    local mem_percent=$(free | awk 'NR==2 {printf "%.1f", ($3/$2) * 100}')
    
    # Memory bar
    local bar_width=20
    local filled=$(printf "%.0f" "$(echo "$mem_percent * $bar_width / 100" | bc -l)")
    local empty=$((bar_width - filled))
    
    printf "Used: %6s/%6s [" "$mem_used" "$mem_total"
    
    if (( $(echo "$mem_percent > 80" | bc -l) )); then
        echo -n -e "${RED}"
    elif (( $(echo "$mem_percent > 60" | bc -l) )); then
        echo -n -e "${YELLOW}"
    else
        echo -n -e "${GREEN}"
    fi
    
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    echo -n -e "${NC}"
    for ((i=0; i<empty; i++)); do echo -n "░"; done
    printf "] %.1f%%\n" "$mem_percent"
    
    # Swap
    local swap_used=$(free -h | awk 'NR==3 {print $3}')
    local swap_total=$(free -h | awk 'NR==3 {print $2}')
    echo "Swap: $swap_used/$swap_total"
    
    # Cache
    local cached=$(free -h | awk 'NR==2 {print $6}')
    echo "Cached: $cached"
}

widget_disk() {
    echo -e "${BOLD_CYAN}DISK${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    df -h | grep -E "^/dev/" | head -3 | while read -r line; do
        local device=$(echo "$line" | awk '{print $1}' | cut -d'/' -f3)
        local size=$(echo "$line" | awk '{print $2}')
        local used=$(echo "$line" | awk '{print $3}')
        local percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
        local mount=$(echo "$line" | awk '{print $6}')
        
        printf "%-15s %6s/%6s" "$mount" "$used" "$size"
        
        # Color based on usage
        if (( percent > 85 )); then
            echo -e " ${RED}${percent}%${NC}"
        elif (( percent > 70 )); then
            echo -e " ${YELLOW}${percent}%${NC}"
        else
            echo -e " ${GREEN}${percent}%${NC}"
        fi
    done
    
    # I/O stats
    if [[ -f /proc/diskstats ]]; then
        echo
        echo "Recent I/O:"
        local device=$(df / | tail -1 | awk '{print $1}' | cut -d'/' -f3 | sed 's/[0-9]*$//')
        if [[ -f "/sys/block/$device/stat" ]]; then
            read -r reads _ _ _ writes _ _ _ _ _ _ < "/sys/block/$device/stat"
            printf "  Reads: %10d\n" "$reads"
            printf "  Writes: %10d\n" "$writes"
        fi
    fi
}

widget_network() {
    echo -e "${BOLD_CYAN}NETWORK${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    # Active interfaces
    local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [[ -n "$default_iface" ]]; then
        local ip_addr=$(ip -4 addr show "$default_iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        local state=$(cat "/sys/class/net/$default_iface/operstate" 2>/dev/null || echo "unknown")
        
        printf "%-10s %15s [%s]\n" "$default_iface" "$ip_addr" "$state"
        
        # Traffic stats
        local rx_bytes=$(cat "/sys/class/net/$default_iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        local tx_bytes=$(cat "/sys/class/net/$default_iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        
        printf "  RX: %s\n" "$(human_readable $rx_bytes)"
        printf "  TX: %s\n" "$(human_readable $tx_bytes)"
    fi
    
    # Connection count
    if command_exists ss; then
        local connections=$(ss -tan | grep ESTAB | wc -l)
        echo
        echo "Connections: $connections"
    fi
    
    # Listening ports
    echo
    echo "Top Ports:"
    if command_exists ss; then
        ss -tuln | grep LISTEN | awk '{print $5}' | cut -d':' -f2 | sort -n | uniq | head -3 | xargs
    fi
}

widget_processes() {
    echo -e "${BOLD_CYAN}PROCESSES${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    local total=$(ps aux | wc -l)
    local running=$(ps aux | grep -c " R ")
    local sleeping=$(ps aux | grep -c " S ")
    
    printf "Total: %d (Running: %d, Sleeping: %d)\n" "$total" "$running" "$sleeping"
    echo
    
    echo "Top by CPU:"
    ps aux --sort=-%cpu | head -4 | tail -3 | awk '{printf "  %-20s %5.1f%%\n", substr($11,1,20), $3}'
    
    echo
    echo "Top by Memory:"
    ps aux --sort=-%mem | head -4 | tail -3 | awk '{printf "  %-20s %5.1f%%\n", substr($11,1,20), $4}'
}

widget_uptime() {
    echo -e "${BOLD_CYAN}SYSTEM${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    local uptime_str=$(uptime -p | sed 's/up //')
    local boot_time=$(who -b | awk '{print $3, $4}')
    
    echo "Uptime: $uptime_str"
    echo "Boot: $boot_time"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    
    # Users
    local user_count=$(who | wc -l)
    echo "Users: $user_count logged in"
}

widget_logs() {
    echo -e "${BOLD_CYAN}RECENT LOGS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    if command_exists journalctl; then
        journalctl -n 5 --no-pager --output=short 2>/dev/null | tail -5 | while read -r line; do
            if echo "$line" | grep -qi "error\|fail"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -qi "warn"; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done | cut -c1-80
    else
        tail -5 /var/log/syslog 2>/dev/null || tail -5 /var/log/messages 2>/dev/null || echo "No logs available"
    fi
}

################################################################################
# Layout Functions
################################################################################

render_terminal_single() {
    clear
    
    print_header "$DASHBOARD_TITLE" 80
    echo
    
    for widget in "${WIDGETS[@]}"; do
        case "$widget" in
            cpu) widget_cpu ;;
            memory) widget_memory ;;
            disk) widget_disk ;;
            network) widget_network ;;
            processes) widget_processes ;;
            uptime) widget_uptime ;;
            logs) widget_logs ;;
        esac
        echo
    done
    
    echo -e "${GRAY}Last update: $(date '+%Y-%m-%d %H:%M:%S') | Refresh: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit${NC}"
}

render_terminal_grid() {
    clear
    
    print_header "$DASHBOARD_TITLE" 160
    echo
    
    # Create 2x2 grid
    local col1_widgets=()
    local col2_widgets=()
    
    for ((i=0; i<${#WIDGETS[@]}; i++)); do
        if (( i % 2 == 0 )); then
            col1_widgets+=("${WIDGETS[$i]}")
        else
            col2_widgets+=("${WIDGETS[$i]}")
        fi
    done
    
    # Render columns side by side
    local max_rows=$(( ${#col1_widgets[@]} > ${#col2_widgets[@]} ? ${#col1_widgets[@]} : ${#col2_widgets[@]} ))
    
    for ((i=0; i<max_rows; i++)); do
        if [[ $i -lt ${#col1_widgets[@]} ]]; then
            {
                case "${col1_widgets[$i]}" in
                    cpu) widget_cpu ;;
                    memory) widget_memory ;;
                    disk) widget_disk ;;
                    network) widget_network ;;
                    processes) widget_processes ;;
                    uptime) widget_uptime ;;
                    logs) widget_logs ;;
                esac
            } | while IFS= read -r line; do
                printf "%-75s" "$line"
                
                # Render second column
                if [[ $i -lt ${#col2_widgets[@]} ]]; then
                    {
                        case "${col2_widgets[$i]}" in
                            cpu) widget_cpu ;;
                            memory) widget_memory ;;
                            disk) widget_disk ;;
                            network) widget_network ;;
                            processes) widget_processes ;;
                            uptime) widget_uptime ;;
                            logs) widget_logs ;;
                        esac
                    } | head -1
                else
                    echo
                fi
            done
        fi
        echo
    done
    
    echo -e "${GRAY}Last update: $(date '+%Y-%m-%d %H:%M:%S') | Refresh: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit${NC}"
}

################################################################################
# HTML Generation
################################################################################

generate_html() {
    cat << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0a0a0a;
            color: #e0e0e0;
            padding: 20px;
        }
        .header {
            text-align: center;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 { color: white; font-size: 2.5em; }
        .header .time { color: #f0f0f0; margin-top: 10px; }
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
        }
        .widget {
            background: #1a1a1a;
            border: 1px solid #333;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        .widget h2 {
            color: #4fc3f7;
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 2px solid #4fc3f7;
            padding-bottom: 10px;
        }
        .metric {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #2a2a2a;
        }
        .metric:last-child { border-bottom: none; }
        .metric-label { color: #9e9e9e; }
        .metric-value {
            font-weight: bold;
            color: #76ff03;
        }
        .progress-bar {
            width: 100%;
            height: 20px;
            background: #2a2a2a;
            border-radius: 10px;
            overflow: hidden;
            margin: 10px 0;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #4caf50, #8bc34a);
            transition: width 0.3s ease;
        }
        .progress-fill.warning { background: linear-gradient(90deg, #ff9800, #ffc107); }
        .progress-fill.danger { background: linear-gradient(90deg, #f44336, #ff5722); }
        .status-ok { color: #4caf50; }
        .status-warn { color: #ff9800; }
        .status-error { color: #f44336; }
        .auto-refresh {
            text-align: center;
            margin-top: 30px;
            color: #757575;
            font-size: 0.9em;
        }
    </style>
    <script>
        function updateDashboard() {
            location.reload();
        }
        setTimeout(updateDashboard, 5000);
    </script>
</head>
<body>
    <div class="header">
        <h1>🖥️ System Dashboard</h1>
        <div class="time" id="current-time"></div>
    </div>
    <div class="dashboard">
EOF
    
    # Generate widget HTML
    for widget in "${WIDGETS[@]}"; do
        echo "<div class=\"widget\">"
        
        case "$widget" in
            cpu)
                local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
                local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs | cut -d',' -f1)
                
                cat << CPUHTML
            <h2>💻 CPU</h2>
            <div class="metric">
                <span class="metric-label">Usage</span>
                <span class="metric-value">${cpu_usage}%</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${cpu_usage}%"></div>
            </div>
            <div class="metric">
                <span class="metric-label">Load Average</span>
                <span class="metric-value">${load_avg}</span>
            </div>
CPUHTML
                ;;
                
            memory)
                local mem_used=$(free -h | awk 'NR==2 {print $3}')
                local mem_total=$(free -h | awk 'NR==2 {print $2}')
                local mem_percent=$(free | awk 'NR==2 {printf "%.1f", ($3/$2) * 100}')
                
                cat << MEMHTML
            <h2>🧠 Memory</h2>
            <div class="metric">
                <span class="metric-label">Used / Total</span>
                <span class="metric-value">${mem_used} / ${mem_total}</span>
            </div>
            <div class="progress-bar">
                <div class="progress-fill" style="width: ${mem_percent}%"></div>
            </div>
            <div class="metric">
                <span class="metric-label">Usage</span>
                <span class="metric-value">${mem_percent}%</span>
            </div>
MEMHTML
                ;;
                
            disk)
                cat << 'DISKHTML'
            <h2>💾 Disk</h2>
DISKHTML
                df -h | grep -E "^/dev/" | head -3 | while read -r line; do
                    local mount=$(echo "$line" | awk '{print $6}')
                    local used=$(echo "$line" | awk '{print $3}')
                    local total=$(echo "$line" | awk '{print $2}')
                    local percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
                    
                    cat << DISKLINEHTML
            <div class="metric">
                <span class="metric-label">${mount}</span>
                <span class="metric-value">${used} / ${total} (${percent}%)</span>
            </div>
DISKLINEHTML
                done
                ;;
                
            network)
                local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
                local ip_addr=$(ip -4 addr show "$default_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "N/A")
                
                cat << NETHTML
            <h2>🌐 Network</h2>
            <div class="metric">
                <span class="metric-label">Interface</span>
                <span class="metric-value">${default_iface}</span>
            </div>
            <div class="metric">
                <span class="metric-label">IP Address</span>
                <span class="metric-value">${ip_addr}</span>
            </div>
NETHTML
                ;;
        esac
        
        echo "</div>"
    done
    
    cat << 'EOF'
    </div>
    <div class="auto-refresh">
        Auto-refresh in 5 seconds... | Generated: <span id="gen-time"></span>
    </div>
    <script>
        document.getElementById('current-time').textContent = new Date().toLocaleString();
        document.getElementById('gen-time').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Dashboard Generator - Custom System Dashboards${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -c, --config FILE       Dashboard config file
    -t, --type TYPE         Dashboard type: terminal, html, both
    --widgets WIDGET,...    Widgets to display
    --layout LAYOUT         Layout: single, split, grid
    --refresh SECONDS       Auto-refresh interval (default: 5)
    --title TITLE           Dashboard title
    --theme THEME           Color theme: dark, light, matrix
    -o, --output FILE       Save HTML to file
    --data-source FILE      Custom data source
    --no-color              Disable colors
    -v, --verbose           Verbose output

${CYAN}Available Widgets:${NC}
    cpu         - CPU usage and load
    memory      - Memory and swap usage
    disk        - Disk usage and I/O
    network     - Network interfaces and traffic
    processes   - Running processes
    uptime      - System uptime and info
    logs        - Recent system logs

${CYAN}Examples:${NC}
    # Terminal dashboard with default widgets
    $(basename "$0")
    
    # Custom widgets in grid layout
    $(basename "$0") --widgets cpu,memory,disk,network --layout grid
    
    # Generate HTML dashboard
    $(basename "$0") -t html -o dashboard.html --theme dark
    
    # Real-time monitoring
    $(basename "$0") --refresh 2 --widgets cpu,memory,processes
    
    # Full monitoring dashboard
    $(basename "$0") --widgets cpu,memory,disk,network,processes,uptime,logs --layout grid

${CYAN}Layouts:${NC}
    single      - Vertical stack of widgets
    grid        - 2-column grid layout

${CYAN}Notes:${NC}
    - Terminal dashboards auto-refresh based on --refresh interval
    - HTML dashboards include auto-refresh via JavaScript
    - Use Ctrl+C to exit terminal dashboard
    - Requires appropriate permissions for system metrics

EOF
}

################################################################################
# Main Execution
################################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--config)
            [[ -z "${2:-}" ]] && error_exit "Config file required" 2
            CONFIG_FILE="$2"
            shift 2
            ;;
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "Dashboard type required" 2
            DASHBOARD_TYPE="$2"
            shift 2
            ;;
        --widgets)
            [[ -z "${2:-}" ]] && error_exit "Widgets required" 2
            IFS=',' read -ra WIDGETS <<< "$2"
            shift 2
            ;;
        --layout)
            [[ -z "${2:-}" ]] && error_exit "Layout required" 2
            LAYOUT="$2"
            shift 2
            ;;
        --refresh)
            [[ -z "${2:-}" ]] && error_exit "Refresh interval required" 2
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --title)
            [[ -z "${2:-}" ]] && error_exit "Title required" 2
            DASHBOARD_TITLE="$2"
            shift 2
            ;;
        --theme)
            [[ -z "${2:-}" ]] && error_exit "Theme required" 2
            THEME="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --data-source)
            [[ -z "${2:-}" ]] && error_exit "Data source required" 2
            DATA_SOURCE="$2"
            shift 2
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Main execution
case "$DASHBOARD_TYPE" in
    terminal)
        while true; do
            case "$LAYOUT" in
                grid)
                    render_terminal_grid
                    ;;
                *)
                    render_terminal_single
                    ;;
            esac
            sleep "$REFRESH_INTERVAL"
        done
        ;;
        
    html)
        if [[ -n "$OUTPUT_FILE" ]]; then
            generate_html > "$OUTPUT_FILE"
            success "HTML dashboard generated: $OUTPUT_FILE"
        else
            generate_html
        fi
        ;;
        
    both)
        if [[ -n "$OUTPUT_FILE" ]]; then
            generate_html > "$OUTPUT_FILE"
            success "HTML dashboard generated: $OUTPUT_FILE"
        fi
        
        echo
        info "Starting terminal dashboard in 3 seconds..."
        sleep 3
        
        while true; do
            render_terminal_single
            sleep "$REFRESH_INTERVAL"
        done
        ;;
        
    *)
        error_exit "Invalid dashboard type: $DASHBOARD_TYPE" 2
        ;;
esac

