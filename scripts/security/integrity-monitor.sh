#!/bin/bash

################################################################################
# Script Name: integrity-monitor.sh
# Description: File integrity monitoring tool that creates secure baselines,
#              scans for tampering, watches critical paths, and exports reports
#              (text or JSON). Supports notifications and scheduled scans.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage:
#   integrity-monitor.sh [init|scan|watch|report] [options]
#
# Commands:
#   init                Build a new baseline for specified paths
#   scan                Compare current state against baseline (default)
#   watch               Continuous scanning at interval
#   report              Show last scan report (if available)
#
# Options:
#   -p, --path PATH     Add directory/file to monitor (repeatable)
#   -b, --baseline FILE Baseline file path (default: $ABS_LOG_DIR/integrity/baseline.db)
#   -f, --format FORMAT Output format: table (default) or json
#   -i, --interval SEC  Interval for watch mode (default: 30)
#   -a, --hash ALGO     Hash algorithm: sha256 (default), sha1, md5
#   -n, --notify        Send notifications on changes
#   -v, --verbose       Verbose logging
#   -h, --help          Show help message
#
# Baseline format: hash|size|mtime|mode|path (one per file)
################################################################################

set -euo pipefail

COMMAND="${1:-scan}"
case "$COMMAND" in
    init|scan|watch|report)
        shift
        ;;
    -h|--help)
        COMMAND="help"
        ;;
    *)
        COMMAND="scan"
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"
source "${SCRIPT_DIR}/../../lib/notifications.sh"
load_notification_config "${ABS_CONFIG_DIR}/notifications.conf"

TARGET_PATHS=()
BASELINE_DIR="${ABS_LOG_DIR}/integrity"
mkdir -p "$BASELINE_DIR"
BASELINE_FILE="$BASELINE_DIR/baseline.db"
REPORT_FILE="$BASELINE_DIR/last-report.json"
OUTPUT_FORMAT="table"
HASH_ALGO="sha256"
HASH_CMD="sha256sum"
INTERVAL=30
SEND_NOTIFICATIONS=false
VERBOSE=false

json_escape() {
    local input="$1"
    input=${input//\\/\\\\}
    input=${input//\"/\\\"}
    input=${input//$'\n'/\\n}
    echo -n "$input"
}

usage() {
    sed -n '1,80p' "$0"
}

set_hash_cmd() {
    case "$HASH_ALGO" in
        sha256) HASH_CMD="sha256sum" ;;
        sha1) HASH_CMD="sha1sum" ;;
        md5) HASH_CMD="md5sum" ;;
        *) error_exit "Unsupported hash algorithm: $HASH_ALGO" 2 ;;
    esac
    require_command "$HASH_CMD" coreutils
}

add_path() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        error_exit "Path not found: $path" 2
    fi
    TARGET_PATHS+=("$path")
}

parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--path) add_path "$2"; shift 2 ;;
            -b|--baseline) BASELINE_FILE="$2"; shift 2 ;;
            -f|--format) OUTPUT_FORMAT="$2"; shift 2 ;;
            -a|--hash) HASH_ALGO="$2"; shift 2 ;;
            -i|--interval) INTERVAL="$2"; shift 2 ;;
            -n|--notify) SEND_NOTIFICATIONS=true; shift ;;
            -v|--verbose) VERBOSE=true; LOG_LEVEL=$LOG_DEBUG; shift ;;
            -h|--help) usage; exit 0 ;;
            --) shift; break ;;
            *) error_exit "Unknown option: $1" 2 ;;
        esac
    done
}

compute_hash() {
    local file="$1"
    "$HASH_CMD" "$file" | awk '{print $1}'
}

collect_files() {
    local path
    for path in "${TARGET_PATHS[@]}"; do
        if [[ -d "$path" ]]; then
            find "$path" -xdev \( -path "$BASELINE_DIR" -o -path "$BASELINE_DIR/*" \) -prune -o -type f -print0
        else
            printf '%s\0' "$path"
        fi
    done
}

create_baseline() {
    [[ ${#TARGET_PATHS[@]} -gt 0 ]] || TARGET_PATHS=("/etc")
    [[ -n "$BASELINE_FILE" ]] || error_exit "Baseline file not defined" 2
    tmp_file=$(mktemp)
    collect_files | while IFS= read -r -d '' file; do
        local hash size mtime mode
        hash=$(compute_hash "$file")
        size=$(stat -c %s "$file")
        mtime=$(stat -c %Y "$file")
        mode=$(stat -c %a "$file")
        printf '%s|%s|%s|%s|%s
' "$hash" "$size" "$mtime" "$mode" "$file" >> "$tmp_file"
    done
    mv "$tmp_file" "$BASELINE_FILE"
    print_success "Baseline created: $BASELINE_FILE"
}

load_baseline() {
    [[ -f "$BASELINE_FILE" ]] || error_exit "Baseline not found: $BASELINE_FILE" 2
    declare -gA BASELINE_HASHES=()
    declare -gA BASELINE_META=()
    while IFS='|' read -r hash size mtime mode path; do
        [[ -z "$path" ]] && continue
        BASELINE_HASHES["$path"]="$hash"
        BASELINE_META["$path"]="$size|$mtime|$mode"
    done < "$BASELINE_FILE"
    BASELINE_COUNT=${#BASELINE_HASHES[@]}
}

scan_paths() {
    load_baseline
    [[ ${#TARGET_PATHS[@]} -gt 0 ]] || TARGET_PATHS=("/etc")
    declare -A CURRENT_HASHES=()
    declare -gA MODIFIED_FILES=()
    declare -gA PERMISSION_CHANGES=()
    declare -a NEW_FILES=()
    declare -a DELETED_FILES=()

    collect_files | while IFS= read -r -d '' file; do
        local hash size mtime mode baseline_key baseline_meta
        hash=$(compute_hash "$file")
        size=$(stat -c %s "$file")
        mtime=$(stat -c %Y "$file")
        mode=$(stat -c %a "$file")
        CURRENT_HASHES["$file"]="$hash|$size|$mtime|$mode"
        if [[ -n "${BASELINE_HASHES[$file]:-}" ]]; then
            baseline_meta=${BASELINE_META[$file]}
            IFS='|' read -r b_size b_mtime b_mode <<< "$baseline_meta"
            if [[ "$hash" != "${BASELINE_HASHES[$file]}" || "$size" != "$b_size" ]]; then
                MODIFIED_FILES["$file"]="$hash|$size|$mtime"
            fi
            if [[ "$mode" != "$b_mode" ]]; then
                PERMISSION_CHANGES["$file"]="$b_mode->$mode"
            fi
        else
            NEW_FILES+=("$file")
        fi
    done

    for path in "${!BASELINE_HASHES[@]}"; do
        [[ -n "${CURRENT_HASHES[$path]:-}" ]] && continue
        DELETED_FILES+=("$path")
    done

    save_report
    print_report
    send_change_notifications
}

save_report() {
    local json
    json=$(generate_json_report)
    echo "$json" > "$REPORT_FILE"
}

generate_json_report() {
    local modified_json new_json deleted_json perms_json ts paths_json
    ts=$(date -Iseconds)

    if [[ ${#TARGET_PATHS[@]} -eq 0 ]]; then
        paths_json='["/etc"]'
    else
        local -a path_parts=()
        for path in "${TARGET_PATHS[@]}"; do
            path_parts+=("\"$(json_escape "$path")\"")
        done
        paths_json="[$(IFS=','; echo "${path_parts[*]}")]"
    fi

    modified_json=$(for path in "${!MODIFIED_FILES[@]}"; do
        local meta="${MODIFIED_FILES[$path]}"
        IFS='|' read -r hash size mtime <<< "$meta"
        printf '    {"path":"%s","hash":"%s","size":%s,"mtime":%s}
' "$(json_escape "$path")" "$hash" "$size" "$mtime"
    done)

    new_json=$(for path in "${NEW_FILES[@]:-}"; do
        printf '    {"path":"%s"}
' "$(json_escape "$path")"
    done)

    deleted_json=$(for path in "${DELETED_FILES[@]:-}"; do
        printf '    {"path":"%s"}
' "$(json_escape "$path")"
    done)

    perms_json=$(for path in "${!PERMISSION_CHANGES[@]}"; do
        printf '    {"path":"%s","change":"%s"}
' "$(json_escape "$path")" "${PERMISSION_CHANGES[$path]}"
    done)

    cat <<JSON
{
  "timestamp": "$ts",
  "baseline": "$BASELINE_FILE",
  "paths": $paths_json,
  "stats": {
    "total": $BASELINE_COUNT,
    "modified": ${#MODIFIED_FILES[@]},
    "new": ${#NEW_FILES[@]},
    "deleted": ${#DELETED_FILES[@]},
    "permission_changes": ${#PERMISSION_CHANGES[@]}
  },
  "modified": [
${modified_json:-}
  ],
  "new": [
${new_json:-}
  ],
  "deleted": [
${deleted_json:-}
  ],
  "permission_changes": [
${perms_json:-}
  ]
}
JSON
}

print_report() {
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        generate_json_report
        return
    fi

    print_header "INTEGRITY REPORT" 70
    echo "Baseline: $BASELINE_FILE"
    echo "Paths:   ${TARGET_PATHS[*]:-/etc}"
    echo "Total tracked: $BASELINE_COUNT"
    echo "Modified: ${#MODIFIED_FILES[@]}"
    echo "New:      ${#NEW_FILES[@]}"
    echo "Deleted:  ${#DELETED_FILES[@]}"
    echo "Perms:    ${#PERMISSION_CHANGES[@]}"
    print_separator

    if [[ ${#MODIFIED_FILES[@]} -gt 0 ]]; then
        print_warning "Modified files"
        for path in "${!MODIFIED_FILES[@]}"; do
            echo "  • $path"
        done
    fi
    if [[ ${#NEW_FILES[@]} -gt 0 ]]; then
        print_info "New files"
        for path in "${NEW_FILES[@]}"; do
            echo "  • $path"
        done
    fi
    if [[ ${#DELETED_FILES[@]} -gt 0 ]]; then
        print_error "Deleted files"
        for path in "${DELETED_FILES[@]}"; do
            echo "  • $path"
        done
    fi
    if [[ ${#PERMISSION_CHANGES[@]} -gt 0 ]]; then
        print_warning "Permission changes"
        for path in "${!PERMISSION_CHANGES[@]}"; do
            echo "  • $path (${PERMISSION_CHANGES[$path]})"
        done
    fi
}

send_change_notifications() {
    [[ "$SEND_NOTIFICATIONS" == true ]] || return
    local total_changes=$(( ${#MODIFIED_FILES[@]} + ${#NEW_FILES[@]} + ${#DELETED_FILES[@]} + ${#PERMISSION_CHANGES[@]} ))
    (( total_changes == 0 )) && return

    local message="Integrity changes detected\nModified: ${#MODIFIED_FILES[@]}\nNew: ${#NEW_FILES[@]}\nDeleted: ${#DELETED_FILES[@]}"
    notify_warning "Integrity Monitor" "$message"
}

watch_loop() {
    load_baseline
    while true; do
        scan_paths
        sleep "$INTERVAL"
    done
}

show_last_report() {
    [[ -f "$REPORT_FILE" ]] || error_exit "No previous report found" 2
    cat "$REPORT_FILE"
}

main() {
    parse_options "$@"
    set_hash_cmd
    [[ ${#TARGET_PATHS[@]} -gt 0 ]] || TARGET_PATHS=("/etc")

    case "$COMMAND" in
        help)
            usage
            ;;
        init)
            create_baseline
            ;;
        scan)
            scan_paths
            ;;
        watch)
            watch_loop
            ;;
        report)
            show_last_report
            ;;
    esac
}

main "$@"
