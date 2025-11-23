#!/bin/bash

################################################################################
# Script Name: metrics-reporter.sh
# Description: Comprehensive metrics collection and reporting tool that gathers
#              system, application, and custom metrics with multi-format output
#              and integration support for monitoring systems.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./metrics-reporter.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -t, --type TYPE         Metric type: system, process, network, disk, custom
#   -m, --metric NAME       Specific metric name
#   -p, --process NAME      Process name for process metrics
#   --interval SECONDS      Collection interval (default: 60)
#   --duration SECONDS      Collection duration (0 = once)
#   --threshold VALUE       Alert threshold
#   -o, --output FILE       Save output to file
#   -f, --format FORMAT     Output format: text, json, prometheus, influx, graphite
#   --timestamp             Include timestamps
#   --labels KEY=VAL        Add custom labels (can specify multiple)
#   --aggregate             Aggregate metrics over duration
#   --percentiles           Calculate percentiles (p50, p95, p99)
#   -v, --verbose           Verbose output
#
# Examples:
#   ./metrics-reporter.sh -t system --format prometheus
#   ./metrics-reporter.sh -t process -p nginx --interval 10
#   ./metrics-reporter.sh -t network --format influx --timestamp
#   ./metrics-reporter.sh -t custom -m my_metric --labels env=prod
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

METRIC_TYPES=()
METRIC_NAMES=()
PROCESS_NAME=""
INTERVAL=60
DURATION=0
THRESHOLD=""
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
USE_TIMESTAMP=false
declare -A LABELS
AGGREGATE_MODE=false
CALC_PERCENTILES=false
VERBOSE=false

# Metric storage
declare -a METRIC_VALUES
declare -A METRIC_HISTORY

################################################################################
# System Metrics
################################################################################

collect_system_metrics() {
    local timestamp=$(date +%s)
    
    # CPU metrics
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local load_1=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    local load_5=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs)
    local load_15=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | xargs)
    
    # Memory metrics
    local mem_total=$(free -b | awk 'NR==2 {print $2}')
    local mem_used=$(free -b | awk 'NR==2 {print $3}')
    local mem_free=$(free -b | awk 'NR==2 {print $4}')
    local mem_available=$(free -b | awk 'NR==2 {print $7}')
    local mem_percent=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
    
    # Swap metrics
    local swap_total=$(free -b | awk 'NR==3 {print $2}')
    local swap_used=$(free -b | awk 'NR==3 {print $3}')
    local swap_percent=0
    [[ $swap_total -gt 0 ]] && swap_percent=$(awk "BEGIN {printf \"%.2f\", ($swap_used/$swap_total)*100}")
    
    # Disk metrics
    local disk_total=$(df -B1 / | awk 'NR==2 {print $2}')
    local disk_used=$(df -B1 / | awk 'NR==2 {print $3}')
    local disk_free=$(df -B1 / | awk 'NR==2 {print $4}')
    local disk_percent=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Network metrics (if available)
    local net_rx=0
    local net_tx=0
    if [[ -f /proc/net/dev ]]; then
        local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
        if [[ -n "$default_iface" ]]; then
            net_rx=$(cat "/sys/class/net/$default_iface/statistics/rx_bytes" 2>/dev/null || echo 0)
            net_tx=$(cat "/sys/class/net/$default_iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        fi
    fi
    
    # Output metrics
    emit_metric "cpu_usage_percent" "$cpu_usage" "$timestamp"
    emit_metric "load_average_1m" "$load_1" "$timestamp"
    emit_metric "load_average_5m" "$load_5" "$timestamp"
    emit_metric "load_average_15m" "$load_15" "$timestamp"
    emit_metric "memory_total_bytes" "$mem_total" "$timestamp"
    emit_metric "memory_used_bytes" "$mem_used" "$timestamp"
    emit_metric "memory_free_bytes" "$mem_free" "$timestamp"
    emit_metric "memory_available_bytes" "$mem_available" "$timestamp"
    emit_metric "memory_usage_percent" "$mem_percent" "$timestamp"
    emit_metric "swap_total_bytes" "$swap_total" "$timestamp"
    emit_metric "swap_used_bytes" "$swap_used" "$timestamp"
    emit_metric "swap_usage_percent" "$swap_percent" "$timestamp"
    emit_metric "disk_total_bytes" "$disk_total" "$timestamp"
    emit_metric "disk_used_bytes" "$disk_used" "$timestamp"
    emit_metric "disk_free_bytes" "$disk_free" "$timestamp"
    emit_metric "disk_usage_percent" "$disk_percent" "$timestamp"
    emit_metric "network_receive_bytes_total" "$net_rx" "$timestamp"
    emit_metric "network_transmit_bytes_total" "$net_tx" "$timestamp"
}

################################################################################
# Process Metrics
################################################################################

collect_process_metrics() {
    local process="$1"
    local timestamp=$(date +%s)
    
    # Find process PIDs
    local pids=($(pgrep -f "$process"))
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        warning "Process not found: $process"
        return 1
    fi
    
    local total_cpu=0
    local total_mem=0
    local total_threads=0
    local total_fds=0
    
    for pid in "${pids[@]}"; do
        if [[ -d "/proc/$pid" ]]; then
            # CPU usage
            local cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | xargs || echo 0)
            total_cpu=$(awk "BEGIN {print $total_cpu + $cpu}")
            
            # Memory usage
            local mem=$(ps -p "$pid" -o rss= 2>/dev/null | xargs || echo 0)
            total_mem=$((total_mem + mem * 1024))
            
            # Thread count
            local threads=$(ps -p "$pid" -o nlwp= 2>/dev/null | xargs || echo 0)
            total_threads=$((total_threads + threads))
            
            # Open file descriptors
            local fds=$(ls -l "/proc/$pid/fd" 2>/dev/null | wc -l || echo 0)
            total_fds=$((total_fds + fds))
        fi
    done
    
    # Process count
    local proc_count=${#pids[@]}
    
    # Output metrics
    emit_metric "process_count" "$proc_count" "$timestamp" "process=\"$process\""
    emit_metric "process_cpu_percent" "$total_cpu" "$timestamp" "process=\"$process\""
    emit_metric "process_memory_bytes" "$total_mem" "$timestamp" "process=\"$process\""
    emit_metric "process_threads_total" "$total_threads" "$timestamp" "process=\"$process\""
    emit_metric "process_open_fds_total" "$total_fds" "$timestamp" "process=\"$process\""
}

################################################################################
# Network Metrics
################################################################################

collect_network_metrics() {
    local timestamp=$(date +%s)
    
    # Network interfaces
    for iface in /sys/class/net/*; do
        local iface_name=$(basename "$iface")
        
        # Skip loopback
        [[ "$iface_name" == "lo" ]] && continue
        
        # Interface status
        local operstate=$(cat "$iface/operstate" 2>/dev/null || echo "unknown")
        local rx_bytes=$(cat "$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        local tx_bytes=$(cat "$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        local rx_packets=$(cat "$iface/statistics/rx_packets" 2>/dev/null || echo 0)
        local tx_packets=$(cat "$iface/statistics/tx_packets" 2>/dev/null || echo 0)
        local rx_errors=$(cat "$iface/statistics/rx_errors" 2>/dev/null || echo 0)
        local tx_errors=$(cat "$iface/statistics/tx_errors" 2>/dev/null || echo 0)
        local rx_dropped=$(cat "$iface/statistics/rx_dropped" 2>/dev/null || echo 0)
        local tx_dropped=$(cat "$iface/statistics/tx_dropped" 2>/dev/null || echo 0)
        
        emit_metric "network_interface_up" "$([[ "$operstate" == "up" ]] && echo 1 || echo 0)" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_receive_bytes_total" "$rx_bytes" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_transmit_bytes_total" "$tx_bytes" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_receive_packets_total" "$rx_packets" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_transmit_packets_total" "$tx_packets" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_receive_errors_total" "$rx_errors" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_transmit_errors_total" "$tx_errors" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_receive_dropped_total" "$rx_dropped" "$timestamp" "interface=\"$iface_name\""
        emit_metric "network_transmit_dropped_total" "$tx_dropped" "$timestamp" "interface=\"$iface_name\""
    done
    
    # Connection statistics
    if command_exists ss; then
        local tcp_established=$(ss -tan | grep ESTAB | wc -l)
        local tcp_listen=$(ss -tln | wc -l)
        local tcp_time_wait=$(ss -tan | grep TIME-WAIT | wc -l)
        
        emit_metric "tcp_connections_established" "$tcp_established" "$timestamp"
        emit_metric "tcp_connections_listen" "$tcp_listen" "$timestamp"
        emit_metric "tcp_connections_time_wait" "$tcp_time_wait" "$timestamp"
    fi
}

################################################################################
# Disk Metrics
################################################################################

collect_disk_metrics() {
    local timestamp=$(date +%s)
    
    # Disk usage per mount point
    df -B1 | tail -n +2 | while read -r filesystem size used avail use_percent mountpoint; do
        local use_val=${use_percent%\%}
        
        emit_metric "disk_total_bytes" "$size" "$timestamp" "mountpoint=\"$mountpoint\",device=\"$filesystem\""
        emit_metric "disk_used_bytes" "$used" "$timestamp" "mountpoint=\"$mountpoint\",device=\"$filesystem\""
        emit_metric "disk_available_bytes" "$avail" "$timestamp" "mountpoint=\"$mountpoint\",device=\"$filesystem\""
        emit_metric "disk_usage_percent" "$use_val" "$timestamp" "mountpoint=\"$mountpoint\",device=\"$filesystem\""
    done
    
    # Inode usage
    df -i | tail -n +2 | while read -r filesystem inodes iused ifree iuse_percent mountpoint; do
        local iuse_val=${iuse_percent%\%}
        
        emit_metric "disk_inodes_total" "$inodes" "$timestamp" "mountpoint=\"$mountpoint\""
        emit_metric "disk_inodes_used" "$iused" "$timestamp" "mountpoint=\"$mountpoint\""
        emit_metric "disk_inodes_free" "$ifree" "$timestamp" "mountpoint=\"$mountpoint\""
        emit_metric "disk_inodes_usage_percent" "$iuse_val" "$timestamp" "mountpoint=\"$mountpoint\""
    done
    
    # Disk I/O statistics (if available)
    if [[ -f /proc/diskstats ]]; then
        while read -r major minor device reads reads_merged sectors_read ms_reading writes writes_merged sectors_written ms_writing io_in_progress ms_io time_io; do
            # Skip loop and ram devices
            [[ "$device" =~ ^(loop|ram) ]] && continue
            
            emit_metric "disk_reads_total" "$reads" "$timestamp" "device=\"$device\""
            emit_metric "disk_writes_total" "$writes" "$timestamp" "device=\"$device\""
            emit_metric "disk_read_bytes_total" "$((sectors_read * 512))" "$timestamp" "device=\"$device\""
            emit_metric "disk_written_bytes_total" "$((sectors_written * 512))" "$timestamp" "device=\"$device\""
        done < /proc/diskstats
    fi
}

################################################################################
# Metric Emission Functions
################################################################################

emit_metric() {
    local name="$1"
    local value="$2"
    local timestamp="${3:-$(date +%s)}"
    local extra_labels="${4:-}"
    
    # Store for aggregation
    if [[ "$AGGREGATE_MODE" == true ]] || [[ "$CALC_PERCENTILES" == true ]]; then
        METRIC_HISTORY["$name"]+="$value "
    fi
    
    # Build labels
    local all_labels="$extra_labels"
    for key in "${!LABELS[@]}"; do
        [[ -n "$all_labels" ]] && all_labels+=","
        all_labels+="$key=\"${LABELS[$key]}\""
    done
    
    # Format output
    case "$OUTPUT_FORMAT" in
        prometheus)
            if [[ -n "$all_labels" ]]; then
                echo "${name}{${all_labels}} $value"
            else
                echo "$name $value"
            fi
            ;;
        influx)
            local tags=""
            [[ -n "$all_labels" ]] && tags=",${all_labels//\"/}"
            echo "${name}${tags} value=$value ${timestamp}000000000"
            ;;
        graphite)
            local metric_path="$name"
            [[ -n "$all_labels" ]] && metric_path+=".${all_labels//[\{\}\",= ]/}"
            echo "$metric_path $value $timestamp"
            ;;
        json)
            # Accumulate for batch output
            ;;
        csv)
            echo "$timestamp,$name,$value,$all_labels"
            ;;
        *)
            # Text format
            local ts_str=""
            [[ "$USE_TIMESTAMP" == true ]] && ts_str="[$timestamp] "
            
            if [[ -n "$all_labels" ]]; then
                echo "${ts_str}${name}{${all_labels}} = $value"
            else
                echo "${ts_str}${name} = $value"
            fi
            ;;
    esac
}

################################################################################
# Aggregation Functions
################################################################################

aggregate_metrics() {
    print_header "AGGREGATED METRICS" 70
    echo
    
    for metric_name in "${!METRIC_HISTORY[@]}"; do
        local values=(${METRIC_HISTORY[$metric_name]})
        local count=${#values[@]}
        
        [[ $count -eq 0 ]] && continue
        
        # Calculate statistics
        local sum=0
        local min=${values[0]}
        local max=${values[0]}
        
        for val in "${values[@]}"; do
            sum=$(awk "BEGIN {print $sum + $val}")
            min=$(awk "BEGIN {print ($val < $min) ? $val : $min}")
            max=$(awk "BEGIN {print ($val > $max) ? $val : $max}")
        done
        
        local avg=$(awk "BEGIN {printf \"%.2f\", $sum / $count}")
        
        echo -e "${BOLD_CYAN}$metric_name${NC}"
        printf "  Samples: %d\n" "$count"
        printf "  Average: %.2f\n" "$avg"
        printf "  Min:     %.2f\n" "$min"
        printf "  Max:     %.2f\n" "$max"
        
        # Calculate percentiles if requested
        if [[ "$CALC_PERCENTILES" == true ]]; then
            IFS=$'\n' sorted=($(sort -n <<<"${values[*]}"))
            unset IFS
            
            local p50_idx=$(( count * 50 / 100 ))
            local p95_idx=$(( count * 95 / 100 ))
            local p99_idx=$(( count * 99 / 100 ))
            
            printf "  P50:     %.2f\n" "${sorted[$p50_idx]}"
            printf "  P95:     %.2f\n" "${sorted[$p95_idx]}"
            printf "  P99:     %.2f\n" "${sorted[$p99_idx]}"
        fi
        
        echo
    done
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Metrics Reporter - Comprehensive Metrics Collection${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -t, --type TYPE         Metric type: system, process, network, disk, custom
    -m, --metric NAME       Specific metric name
    -p, --process NAME      Process name for process metrics
    --interval SECONDS      Collection interval (default: 60)
    --duration SECONDS      Collection duration (0 = once)
    --threshold VALUE       Alert threshold
    -o, --output FILE       Save output to file
    -f, --format FORMAT     Output format: text, json, prometheus, influx, graphite
    --timestamp             Include timestamps
    --labels KEY=VAL        Add custom labels
    --aggregate             Aggregate metrics over duration
    --percentiles           Calculate percentiles (p50, p95, p99)
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # System metrics in Prometheus format
    $(basename "$0") -t system --format prometheus
    
    # Process metrics with monitoring
    $(basename "$0") -t process -p nginx --interval 10 --duration 300
    
    # Network metrics with InfluxDB format
    $(basename "$0") -t network --format influx --timestamp
    
    # Aggregated metrics with percentiles
    $(basename "$0") -t system --interval 5 --duration 60 --aggregate --percentiles
    
    # Custom labels for multi-environment setup
    $(basename "$0") -t system --labels env=prod,region=us-east --format prometheus

${CYAN}Metric Types:${NC}
    system    - CPU, memory, swap, disk, network
    process   - Process-specific metrics (requires -p)
    network   - Network interfaces and connections
    disk      - Disk usage and I/O statistics
    custom    - Custom metric (requires -m)

${CYAN}Output Formats:${NC}
    text       - Human-readable text
    json       - JSON format
    prometheus - Prometheus exposition format
    influx     - InfluxDB line protocol
    graphite   - Graphite plaintext format
    csv        - CSV format

${CYAN}Integration Examples:${NC}
    # Prometheus Node Exporter compatible
    $(basename "$0") -t system --format prometheus > metrics.prom
    
    # InfluxDB ingestion
    $(basename "$0") -t system --format influx | curl -XPOST 'http://localhost:8086/write?db=metrics' --data-binary @-
    
    # Graphite Carbon plaintext
    $(basename "$0") -t system --format graphite | nc graphite.example.com 2003

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
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "Metric type required" 2
            METRIC_TYPES+=("$2")
            shift 2
            ;;
        -m|--metric)
            [[ -z "${2:-}" ]] && error_exit "Metric name required" 2
            METRIC_NAMES+=("$2")
            shift 2
            ;;
        -p|--process)
            [[ -z "${2:-}" ]] && error_exit "Process name required" 2
            PROCESS_NAME="$2"
            shift 2
            ;;
        --interval)
            [[ -z "${2:-}" ]] && error_exit "Interval required" 2
            INTERVAL="$2"
            shift 2
            ;;
        --duration)
            [[ -z "${2:-}" ]] && error_exit "Duration required" 2
            DURATION="$2"
            shift 2
            ;;
        --threshold)
            [[ -z "${2:-}" ]] && error_exit "Threshold required" 2
            THRESHOLD="$2"
            shift 2
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
        --timestamp)
            USE_TIMESTAMP=true
            shift
            ;;
        --labels)
            [[ -z "${2:-}" ]] && error_exit "Labels required" 2
            IFS='=' read -r key val <<< "$2"
            LABELS["$key"]="$val"
            shift 2
            ;;
        --aggregate)
            AGGREGATE_MODE=true
            shift
            ;;
        --percentiles)
            CALC_PERCENTILES=true
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

# Default to system metrics if none specified
[[ ${#METRIC_TYPES[@]} -eq 0 ]] && METRIC_TYPES=("system")

# Redirect output if needed
[[ -n "$OUTPUT_FILE" ]] && exec > "$OUTPUT_FILE"

# CSV header
[[ "$OUTPUT_FORMAT" == "csv" ]] && echo "timestamp,metric,value,labels"

# Collection loop
start_time=$(date +%s)
iteration=0

while true; do
    for type in "${METRIC_TYPES[@]}"; do
        case "$type" in
            system)
                collect_system_metrics
                ;;
            process)
                [[ -z "$PROCESS_NAME" ]] && error_exit "Process name required for process metrics (-p)" 2
                collect_process_metrics "$PROCESS_NAME"
                ;;
            network)
                collect_network_metrics
                ;;
            disk)
                collect_disk_metrics
                ;;
            custom)
                [[ ${#METRIC_NAMES[@]} -eq 0 ]] && error_exit "Metric name required for custom metrics (-m)" 2
                for name in "${METRIC_NAMES[@]}"; do
                    emit_metric "$name" "0" "$(date +%s)"
                done
                ;;
        esac
    done
    
    ((iteration++))
    
    # Check duration
    if [[ $DURATION -gt 0 ]]; then
        elapsed=$(($(date +%s) - start_time))
        [[ $elapsed -ge $DURATION ]] && break
    else
        break
    fi
    
    sleep "$INTERVAL"
done

# Output aggregation if requested
if [[ "$AGGREGATE_MODE" == true ]]; then
    aggregate_metrics
fi

