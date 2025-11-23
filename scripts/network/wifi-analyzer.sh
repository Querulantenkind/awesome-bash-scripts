#!/bin/bash

################################################################################
# Script Name: wifi-analyzer.sh
# Description: Advanced Wi-Fi diagnostics, scanning, and channel planning tool.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
################################################################################

set -euo pipefail

for arg in "$@"; do
    if [[ "$arg" == "--no-color" ]]; then
        export NO_COLOR=true
        break
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

INTERFACE=""
PERFORM_SCAN=false
CHANNEL_ANALYSIS=false
TOP_N=15
MONITOR=false
INTERVAL=5
OUTPUT_FORMAT="table"
EXPORT_FILE=""
VERBOSE=false
SCAN_DATA=""
SCAN_FIELDS="BSSID,SSID,CHAN,FREQ,RATE,SIGNAL,SECURITY"
SCAN_SEPARATOR=';'
declare -A CHANNEL_COUNTS=()
declare -A CHANNEL_SIGNAL_SUM=()

usage() {
    cat <<'USAGE'
Usage: wifi-analyzer.sh [options]

Options:
  -h, --help                Show help message
  -i, --interface IFACE     Wi-Fi interface (auto-detect if omitted)
  --scan                    Perform Wi-Fi scan and display nearby networks
  --channel-plan            Analyze channels and recommend optimal ones
  --top N                   Show top N networks (default: 15)
  --monitor SECONDS         Continuous monitoring interval
  --format FORMAT           Output format: table (default), json, csv
  --export FILE             Save report to file (honors format)
  --json                    Shortcut for --format json
  --csv                     Shortcut for --format csv
  --no-color                Disable ANSI colors
  -v, --verbose             Verbose logging
USAGE
}

require_dependencies() {
    require_command nmcli NetworkManager
    require_command iw wireless-tools
}

detect_interface() {
    [[ -n "$INTERFACE" ]] && return
    INTERFACE=$(nmcli -t -f DEVICE,TYPE,STATE dev status | awk -F: '$2 == "wifi" && $3 != "unavailable" {print $1; exit}')
    [[ -n "$INTERFACE" ]] || error_exit "No Wi-Fi interface detected. Use --interface" 2
}

collect_summary() {
    SUMMARY_INTERFACE="$INTERFACE"
    local nm_show link_output

    nm_show=$(nmcli -t dev show "$INTERFACE" 2>/dev/null || true)
    link_output=$(iw dev "$INTERFACE" link 2>/dev/null || echo "Not connected.")

    SUMMARY_STATE=$(echo "$nm_show" | awk -F: '/GENERAL.STATE/ {print $2}')
    SUMMARY_CONNECTION=$(echo "$nm_show" | awk -F: '/GENERAL.CONNECTION/ {print $2}')
    SUMMARY_IP4=$(echo "$nm_show" | awk -F: '/IP4.ADDRESS\\[1\\]/ {print $2}')
    SUMMARY_IP6=$(echo "$nm_show" | awk -F: '/IP6.ADDRESS\\[1\\]/ {print $2}')

    SUMMARY_STATE=${SUMMARY_STATE:-disconnected}
    SUMMARY_CONNECTION=${SUMMARY_CONNECTION:-None}
    SUMMARY_IP4=${SUMMARY_IP4:--}
    SUMMARY_IP6=${SUMMARY_IP6:--}

    if [[ "$link_output" == "Not connected." ]]; then
        SUMMARY_SSID="Not connected"
        SUMMARY_SIGNAL="-"
        SUMMARY_QUALITY="0%"
        SUMMARY_FREQ="-"
        SUMMARY_CHANNEL="-"
        SUMMARY_TX="-"
        SUMMARY_RX="-"
        SUMMARY_BSSID="-"
    else
        SUMMARY_SSID=$(echo "$link_output" | awk -F': ' '/SSID/ {print $2}' | head -n1)
        SUMMARY_SIGNAL=$(echo "$link_output" | awk '/signal:/ {print $2}')
        SUMMARY_TX=$(echo "$link_output" | awk -F': ' '/tx bitrate/ {print $2}')
        SUMMARY_RX=$(echo "$link_output" | awk -F': ' '/rx bitrate/ {print $2}')
        SUMMARY_FREQ=$(echo "$link_output" | awk '/freq:/ {print $2 " MHz"}')
        SUMMARY_BSSID=$(echo "$link_output" | awk '/Connected to/ {print $3}')

        local freq_mhz signal_dbm channel calc_quality
        freq_mhz=$(echo "$link_output" | awk '/freq:/ {print $2}')
        signal_dbm=$(echo "$link_output" | awk '/signal:/ {print $2}')

        if [[ -n "$freq_mhz" ]]; then
            if (( freq_mhz < 4000 )); then
                channel=$(( (freq_mhz - 2407) / 5 ))
            else
                channel=$(( (freq_mhz - 5000) / 5 ))
            fi
            SUMMARY_CHANNEL="${channel:--}"
        else
            SUMMARY_CHANNEL="-"
        fi

        if [[ "$signal_dbm" =~ -?[0-9]+ ]]; then
            calc_quality=$(( (signal_dbm + 100) * 2 ))
            (( calc_quality < 0 )) && calc_quality=0
            (( calc_quality > 100 )) && calc_quality=100
            SUMMARY_QUALITY="${calc_quality}%"
        else
            SUMMARY_QUALITY="-"
        fi
    fi
}

run_scan() {
    SCAN_DATA=$(nmcli --terse --fields "$SCAN_FIELDS" --separator "$SCAN_SEPARATOR" dev wifi list 2>/dev/null || true)
}

print_summary_table() {
    print_header "WI-FI SUMMARY" 70
    local signal_display="$SUMMARY_SIGNAL"
    [[ "$signal_display" != "-" ]] && signal_display="${signal_display} dBm"
    printf "%-18s %s\n" "Interface:" "$SUMMARY_INTERFACE"
    printf "%-18s %s\n" "State:" "$SUMMARY_STATE"
    printf "%-18s %s\n" "Connection:" "$SUMMARY_CONNECTION"
    printf "%-18s %s\n" "SSID:" "${SUMMARY_SSID:-$SUMMARY_CONNECTION}"
    printf "%-18s %s\n" "BSSID:" "${SUMMARY_BSSID:--}"
    printf "%-18s %s\n" "Signal:" "$signal_display"
    printf "%-18s %s\n" "Quality:" "$SUMMARY_QUALITY"
    printf "%-18s %s\n" "Frequency:" "$SUMMARY_FREQ"
    printf "%-18s %s\n" "Channel:" "$SUMMARY_CHANNEL"
    printf "%-18s %s\n" "TX Bitrate:" "${SUMMARY_TX:-Unknown}"
    printf "%-18s %s\n" "RX Bitrate:" "${SUMMARY_RX:-Unknown}"
    printf "%-18s %s\n" "IPv4:" "$SUMMARY_IP4"
    printf "%-18s %s\n" "IPv6:" "$SUMMARY_IP6"
    print_separator
}

print_scan_table() {
    [[ -n "$SCAN_DATA" ]] || { print_warning "No scan data available"; return; }

    print_header "NEARBY NETWORKS (TOP $TOP_N)" 90
    printf "%-4s %-22s %-6s %-8s %-8s %-10s %-20s\n" "#" "SSID" "CHAN" "SIGNAL" "RATE" "SECURITY" "BSSID"
    print_separator

    local index=0
    while IFS="$SCAN_SEPARATOR" read -r bssid ssid chan freq rate signal security; do
        [[ -z "$bssid" ]] && continue
        ssid=$(unescape_nm "${ssid:-<hidden>}")
        [[ -z "$ssid" ]] && ssid="<hidden>"
        security=$(unescape_nm "${security:-open}")
        rate=$(unescape_nm "${rate:-n/a}")
        ((index++))
        printf "%-4s %-22s %-6s %-8s %-8s %-10s %-20s\n" "$index" "${ssid:0:22}" "${chan:-?}" "${signal:-?} dBm" "$rate" "$security" "$bssid"
        (( index >= TOP_N )) && break
    done <<< "$SCAN_DATA"
}

calculate_channel_stats() {
    CHANNEL_COUNTS=()
    CHANNEL_SIGNAL_SUM=()
    [[ -n "$SCAN_DATA" ]] || return 1

    while IFS="$SCAN_SEPARATOR" read -r _ ssid chan freq rate signal security; do
        [[ -z "$chan" || -z "$freq" ]] && continue
        local freq_mhz=$(echo "$freq" | tr -cd '0-9')
        [[ -z "$freq_mhz" ]] && continue
        local band key signal_dbm
        if (( freq_mhz < 4000 )); then
            band="2.4 GHz"
        else
            band="5 GHz"
        fi
        signal_dbm=${signal%% *}
        [[ "$signal_dbm" =~ ^-?[0-9]+$ ]] || signal_dbm=-100
        key="${band}:${chan}"
        (( CHANNEL_COUNTS[$key]++ ))
        CHANNEL_SIGNAL_SUM[$key]=$(( CHANNEL_SIGNAL_SUM[$key] + signal_dbm ))
    done <<< "$SCAN_DATA"
}

analyze_channels() {
    calculate_channel_stats || { print_warning "Channel analysis requires scan data"; return; }

    print_header "CHANNEL RECOMMENDATIONS" 80
    printf "%-10s %-10s %-10s %-12s\n" "Band" "Channel" "Networks" "Avg Signal"
    print_separator

    local -a table_lines=()
    for key in "${!CHANNEL_COUNTS[@]}"; do
        local band="${key%%:*}"
        local chan="${key##*:}"
        local count=${CHANNEL_COUNTS[$key]}
        local avg=$(( CHANNEL_SIGNAL_SUM[$key] / count ))
        table_lines+=("$band;$chan;$count;$avg")
    done

    if [[ ${#table_lines[@]} -eq 0 ]]; then
        print_warning "No channel data available"
        return
    fi

    printf '%s\n' "${table_lines[@]}" | sort -t';' -k1,1 -k3,3n | while IFS=';' read -r band chan count avg; do
        printf "%-10s %-10s %-10s %-12s\n" "$band" "$chan" "$count" "${avg} dBm"
    done

    print_separator

    for band in "2.4 GHz" "5 GHz"; do
        local best_channel="" best_count=999 best_avg=-200
        for key in "${!CHANNEL_COUNTS[@]}"; do
            [[ "${key%%:*}" != "$band" ]] && continue
            local chan="${key##*:}"
            local count=${CHANNEL_COUNTS[$key]}
            local avg=$(( CHANNEL_SIGNAL_SUM[$key] / count ))
            if (( count < best_count )) || { (( count == best_count )) && (( avg > best_avg )); }; then
                best_channel="$chan"
                best_count=$count
                best_avg=$avg
            fi
        done
        if [[ -n "$best_channel" ]]; then
            printf "%s best channel: %s (networks: %d, avg signal: %d dBm)\n" "$band" "$best_channel" "$best_count" "$best_avg"
        fi
    done
}

json_escape() {
    local input="$1"
    input=${input//\\/\\\\}
    input=${input//\"/\\\"}
    input=${input//$'\n'/\\n}
    echo -n "$input"
}

unescape_nm() {
    local value="$1"
    value=${value//\\$SCAN_SEPARATOR/$SCAN_SEPARATOR}
    value=${value//\\:/:}
    value=${value//\\\\/\\}
    echo "$value"
}

export_report() {
    case "$OUTPUT_FORMAT" in
        json)
            export_json_report
            ;;
        csv)
            export_csv_report
            ;;
        *)
            error_exit "Unsupported export format: $OUTPUT_FORMAT" 2
            ;;
    esac
}

export_json_report() {
    calculate_channel_stats || true

    cat <<EOF
{
  "interface": {
    "name": "$(json_escape "$SUMMARY_INTERFACE")",
    "state": "$(json_escape "$SUMMARY_STATE")",
    "connection": "$(json_escape "$SUMMARY_CONNECTION")",
    "ssid": "$(json_escape "${SUMMARY_SSID:-$SUMMARY_CONNECTION}")",
    "bssid": "$(json_escape "${SUMMARY_BSSID:--}")",
    "signal_dbm": "$SUMMARY_SIGNAL",
    "quality": "$SUMMARY_QUALITY",
    "frequency": "$(json_escape "$SUMMARY_FREQ")",
    "channel": "$(json_escape "$SUMMARY_CHANNEL")",
    "tx_bitrate": "$(json_escape "${SUMMARY_TX:-Unknown}")",
    "rx_bitrate": "$(json_escape "${SUMMARY_RX:-Unknown}")",
    "ipv4": "$(json_escape "$SUMMARY_IP4")",
    "ipv6": "$(json_escape "$SUMMARY_IP6")"
  },
  "networks": [
EOF

    local first=true
    while IFS="$SCAN_SEPARATOR" read -r bssid ssid chan freq rate signal security; do
        [[ -z "$bssid" ]] && continue
        ssid=$(unescape_nm "${ssid:-<hidden>}")
        security=$(unescape_nm "${security:-open}")
        rate=$(unescape_nm "${rate:-n/a}")
        freq=$(unescape_nm "${freq:-0}")
        signal=${signal%% *}
        [[ "$signal" =~ ^-?[0-9]+$ ]] || signal=-100
        if [[ "$first" == true ]]; then
            first=false
        else
            printf ",\n"
        fi
        printf "    {\"ssid\":\"%s\",\"channel\":%s,\"frequency\":\"%s\",\"signal\":%s,\"rate\":\"%s\",\"security\":\"%s\",\"bssid\":\"%s\"}" \
            "$(json_escape "$ssid")" "${chan:-0}" "$(json_escape "$freq")" "$signal" "$(json_escape "$rate")" "$(json_escape "$security")" "$(json_escape "$bssid")"
    done <<< "$SCAN_DATA"
    echo
    echo "  ],"
    echo "  \"channels\": {"

    for band in "2.4 GHz" "5 GHz"; do
        echo "    \"${band}\": ["
        local emitted=false
        for key in "${!CHANNEL_COUNTS[@]}"; do
            [[ "${key%%:*}" != "$band" ]] && continue
            local chan="${key##*:}"
            local count=${CHANNEL_COUNTS[$key]}
            local avg=$(( CHANNEL_SIGNAL_SUM[$key] / count ))
            if [[ "$emitted" == true ]]; then
                printf ",\n"
            fi
            emitted=true
            printf "      {\"channel\":%s,\"networks\":%s,\"avg_signal\":%s}" "$chan" "$count" "$avg"
        done
        echo
        if [[ "$band" == "5 GHz" ]]; then
            echo "    ]"
        else
            echo "    ],"
        fi
    done
    echo "  }"
    echo "}"
}

export_csv_report() {
    echo "# interface,$SUMMARY_INTERFACE"
    echo "# state,$SUMMARY_STATE"
    echo "# ssid,${SUMMARY_SSID:-$SUMMARY_CONNECTION}"
    echo "# signal,$SUMMARY_SIGNAL"
    echo "SSID,Channel,Frequency,Signal,Rate,Security,BSSID"
    while IFS="$SCAN_SEPARATOR" read -r bssid ssid chan freq rate signal security; do
        [[ -z "$bssid" ]] && continue
        ssid=$(unescape_nm "${ssid:-<hidden>}")
        rate=$(unescape_nm "${rate:-n/a}")
        security=$(unescape_nm "${security:-open}")
        freq=$(unescape_nm "$freq")
        signal=${signal%% *}
        printf '"%s",%s,"%s",%s,"%s","%s","%s"\n' \
            "${ssid//\"/\"\"}" "${chan:-0}" "${freq//\"/\"\"}" "${signal:-0}" "${rate//\"/\"\"}" "${security//\"/\"\"}" "${bssid//\"/\"\"}"
    done <<< "$SCAN_DATA"
}

monitor_loop() {
    while true; do
        clear
        collect_summary
        print_summary_table
        if [[ "$PERFORM_SCAN" == true ]]; then
            run_scan
            print_scan_table
            [[ "$CHANNEL_ANALYSIS" == true ]] && analyze_channels
        fi
        printf "Updated: %s | Interface: %s | Interval: %ss\n" "$(date '+%H:%M:%S')" "$INTERFACE" "$INTERVAL"
        sleep "$INTERVAL"
    done
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -i|--interface) INTERFACE="$2"; shift 2 ;;
            --scan) PERFORM_SCAN=true; shift ;;
            --channel-plan) CHANNEL_ANALYSIS=true; PERFORM_SCAN=true; shift ;;
            --top) TOP_N="$2"; shift 2 ;;
            --monitor) MONITOR=true; INTERVAL="$2"; shift 2 ;;
            --format) OUTPUT_FORMAT="$2"; shift 2 ;;
            --export) EXPORT_FILE="$2"; shift 2 ;;
            --json) OUTPUT_FORMAT="json"; shift ;;
            --csv) OUTPUT_FORMAT="csv"; shift ;;
            --no-color) NO_COLOR=true; shift ;;
            -v|--verbose) VERBOSE=true; LOG_LEVEL=$LOG_DEBUG; shift ;;
            *) error_exit "Unknown option: $1" 2 ;;
        esac
    done
}

main() {
    parse_args "$@"
    require_dependencies
    detect_interface

    [[ "$OUTPUT_FORMAT" != "table" ]] && PERFORM_SCAN=true

    if [[ "$MONITOR" == true ]]; then
        monitor_loop
        exit 0
    fi

    collect_summary
    [[ "$PERFORM_SCAN" == true ]] && run_scan

    local export_format="$OUTPUT_FORMAT"
    if [[ -n "$EXPORT_FILE" && "$export_format" == "table" ]]; then
        export_format="json"
    fi

    case "$OUTPUT_FORMAT" in
        table)
            print_summary_table
            [[ "$PERFORM_SCAN" == true ]] && print_scan_table
            [[ "$CHANNEL_ANALYSIS" == true ]] && analyze_channels
            ;;
        json|csv)
            [[ "$PERFORM_SCAN" != true ]] && run_scan
            export_report
            ;;
        *) error_exit "Unsupported format: $OUTPUT_FORMAT" 2 ;;
    esac

    if [[ -n "$EXPORT_FILE" ]]; then
        local original_format="$OUTPUT_FORMAT"
        OUTPUT_FORMAT="$export_format"
        [[ "$PERFORM_SCAN" != true ]] && run_scan
        export_report > "$EXPORT_FILE"
        OUTPUT_FORMAT="$original_format"
        print_success "Report exported to $EXPORT_FILE"
    fi
}

main "$@"
