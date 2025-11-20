#!/bin/bash

################################################################################
# Script Name: cron-manager.sh
# Description: Crontab management interface with syntax validation, backup/restore,
#              schedule testing, and easy job management. Simplifies cron job
#              creation and maintenance with a user-friendly interface.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./cron-manager.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --list              List all cron jobs
#   -a, --add               Add new cron job (interactive)
#   -r, --remove ID         Remove cron job by line number
#   -e, --edit              Edit crontab in editor
#   --validate EXPR         Validate cron expression
#   --test EXPR             Test when cron will next run
#   --backup FILE           Backup crontab to file
#   --restore FILE          Restore crontab from file
#   -u, --user USER         Manage crontab for specific user
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./cron-manager.sh --list
#   ./cron-manager.sh --add
#   ./cron-manager.sh --remove 3
#   ./cron-manager.sh --validate "0 2 * * *"
#   ./cron-manager.sh --backup /backup/crontab.bak
#   ./cron-manager.sh --restore /backup/crontab.bak
#   ./cron-manager.sh --user www-data --list
#
# Dependencies:
#   - crontab
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

VERBOSE=false
LIST_JOBS=false
ADD_JOB=false
REMOVE_ID=""
EDIT_CRONTAB=false
VALIDATE_EXPR=""
TEST_EXPR=""
BACKUP_FILE=""
RESTORE_FILE=""
USER=""
JSON_OUTPUT=false
USE_COLOR=true

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"
}

warning() {
    [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"
}

info() {
    [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"
}

verbose() {
    [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2
}

show_usage() {
    cat << EOF
${WHITE}Cron Manager - Crontab Management Interface${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --list              List all cron jobs
    -a, --add               Add new cron job (interactive)
    -r, --remove ID         Remove cron job by line number
    -e, --edit              Edit crontab in editor
    --validate EXPR         Validate cron expression
    --test EXPR             Test when cron will next run
    --backup FILE           Backup crontab to file
    --restore FILE          Restore crontab from file
    -u, --user USER         Manage crontab for specific user
    -j, --json              Output in JSON format
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # List all cron jobs
    $SCRIPT_NAME --list

    # Add new cron job interactively
    $SCRIPT_NAME --add

    # Remove cron job by line number
    $SCRIPT_NAME --remove 3

    # Validate cron expression
    $SCRIPT_NAME --validate "0 2 * * *"

    # Backup crontab
    $SCRIPT_NAME --backup /backup/crontab.bak

    # Restore crontab
    $SCRIPT_NAME --restore /backup/crontab.bak

    # Manage another user's crontab (requires root)
    $SCRIPT_NAME --user www-data --list

${CYAN}Cron Expression Format:${NC}
    * * * * * command
    │ │ │ │ │
    │ │ │ │ └─── Day of week (0-7, Sunday=0 or 7)
    │ │ │ └───── Month (1-12)
    │ │ └─────── Day of month (1-31)
    │ └───────── Hour (0-23)
    └─────────── Minute (0-59)

${CYAN}Special Expressions:${NC}
    @reboot         Run once at startup
    @yearly         Run once a year (0 0 1 1 *)
    @monthly        Run once a month (0 0 1 * *)
    @weekly         Run once a week (0 0 * * 0)
    @daily          Run once a day (0 0 * * *)
    @hourly         Run once an hour (0 * * * *)

EOF
}

check_dependencies() {
    command -v crontab &> /dev/null || error_exit "crontab command not found" 3
}

get_crontab_cmd() {
    if [[ -n "$USER" ]]; then
        echo "crontab -u $USER"
    else
        echo "crontab"
    fi
}

list_cron_jobs() {
    local cmd=$(get_crontab_cmd)

    verbose "Listing cron jobs..."

    if ! $cmd -l &> /dev/null; then
        warning "No crontab found"
        return 0
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"user\": \"${USER:-$(whoami)}\","
        echo "  \"jobs\": ["

        local first=true
        local line_num=0

        $cmd -l 2>/dev/null | while IFS= read -r line; do
            ((line_num++))

            # Skip comments
            [[ "$line" =~ ^#.*$ ]] && continue
            # Skip empty lines
            [[ -z "$line" ]] && continue

            [[ "$first" != true ]] && echo ","

            local schedule=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
            local command=$(echo "$line" | cut -d' ' -f6-)

            cat << EOF
    {
      "line": $line_num,
      "schedule": "$schedule",
      "command": "$command"
    }
EOF
            first=false
        done

        echo ""
        echo "  ]"
        echo "}"
    else
        echo ""
        echo -e "${WHITE}━━━ CRON JOBS ━━━${NC}"
        echo ""

        printf "${CYAN}%-5s %-20s %-s${NC}\n" "LINE" "SCHEDULE" "COMMAND"
        echo "────────────────────────────────────────────────────────────────────────────"

        local line_num=0

        $cmd -l 2>/dev/null | while IFS= read -r line; do
            ((line_num++))

            # Display comments in gray
            if [[ "$line" =~ ^#.*$ ]]; then
                echo -e "${YELLOW}$line_num:${NC} $line"
                continue
            fi

            # Skip empty lines
            [[ -z "$line" ]] && continue

            local schedule=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
            local command=$(echo "$line" | cut -d' ' -f6-)

            printf "%-5s %-20s %-s\n" "$line_num" "$schedule" "$command"
        done

        echo ""
    fi
}

validate_cron_expression() {
    local expr="$1"

    # Special expressions
    if [[ "$expr" =~ ^@(reboot|yearly|monthly|weekly|daily|hourly)$ ]]; then
        success "Valid special cron expression: $expr"
        return 0
    fi

    # Parse standard expression
    read -r min hour day month dow rest <<< "$expr"

    local errors=()

    # Validate minute (0-59)
    if [[ ! "$min" =~ ^(\*|[0-5]?[0-9]|(\*\/[0-9]+)|([0-5]?[0-9]-[0-5]?[0-9])|([0-5]?[0-9](,[0-5]?[0-9])*))$ ]]; then
        errors+=("Invalid minute field: $min")
    fi

    # Validate hour (0-23)
    if [[ ! "$hour" =~ ^(\*|[01]?[0-9]|2[0-3]|(\*\/[0-9]+)|([01]?[0-9]-2[0-3])|([01]?[0-9](,[01]?[0-9])*))$ ]]; then
        errors+=("Invalid hour field: $hour")
    fi

    # Validate day (1-31)
    if [[ ! "$day" =~ ^(\*|[1-9]|[12][0-9]|3[01]|(\*\/[0-9]+)|([1-9]-3[01])|([1-9](,[1-9])*))$ ]]; then
        errors+=("Invalid day field: $day")
    fi

    # Validate month (1-12)
    if [[ ! "$month" =~ ^(\*|[1-9]|1[0-2]|(\*\/[0-9]+)|([1-9]-1[0-2])|([1-9](,[1-9])*)|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)$ ]]; then
        errors+=("Invalid month field: $month")
    fi

    # Validate day of week (0-7)
    if [[ ! "$dow" =~ ^(\*|[0-7]|(\*\/[0-9]+)|([0-7]-[0-7])|([0-7](,[0-7])*)|sun|mon|tue|wed|thu|fri|sat)$ ]]; then
        errors+=("Invalid day of week field: $dow")
    fi

    if [[ ${#errors[@]} -eq 0 ]]; then
        success "Valid cron expression: $expr"
        return 0
    else
        warning "Invalid cron expression:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
}

test_cron_schedule() {
    local expr="$1"

    info "Testing cron schedule: $expr"

    # This is a simplified test - for production use, consider using a tool like "cronsearch"
    echo ""
    echo "Expression: $expr"

    case "$expr" in
        @reboot)
            echo "Runs: At system startup"
            ;;
        @yearly|@annually)
            echo "Runs: Once a year (January 1, 00:00)"
            ;;
        @monthly)
            echo "Runs: Once a month (1st day, 00:00)"
            ;;
        @weekly)
            echo "Runs: Once a week (Sunday, 00:00)"
            ;;
        @daily|@midnight)
            echo "Runs: Once a day (00:00)"
            ;;
        @hourly)
            echo "Runs: Once an hour (minute 0)"
            ;;
        *)
            read -r min hour day month dow rest <<< "$expr"
            echo "Minute:       $min"
            echo "Hour:         $hour"
            echo "Day:          $day"
            echo "Month:        $month"
            echo "Day of week:  $dow"
            ;;
    esac

    echo ""
}

add_cron_job() {
    local cmd=$(get_crontab_cmd)

    info "Adding new cron job..."
    echo ""

    # Get schedule
    echo "Enter cron schedule (e.g., '0 2 * * *' or '@daily'):"
    read -r schedule

    # Validate schedule
    if ! validate_cron_expression "$schedule"; then
        error_exit "Invalid cron expression" 2
    fi

    # Get command
    echo ""
    echo "Enter command to run:"
    read -r command

    if [[ -z "$command" ]]; then
        error_exit "Command cannot be empty" 2
    fi

    # Preview
    echo ""
    info "New cron job:"
    echo "  Schedule: $schedule"
    echo "  Command: $command"
    echo ""

    read -p "Add this job? (y/n): " -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Cancelled"
        return 0
    fi

    # Add job
    local temp_file=$(mktemp)

    if $cmd -l &> /dev/null; then
        $cmd -l > "$temp_file" 2>/dev/null
    fi

    echo "$schedule $command" >> "$temp_file"

    if $cmd "$temp_file" 2>/dev/null; then
        success "Cron job added successfully"
        rm -f "$temp_file"
    else
        rm -f "$temp_file"
        error_exit "Failed to add cron job" 1
    fi
}

remove_cron_job() {
    local line_id="$1"
    local cmd=$(get_crontab_cmd)

    if ! $cmd -l &> /dev/null; then
        error_exit "No crontab found" 1
    fi

    local temp_file=$(mktemp)
    $cmd -l > "$temp_file" 2>/dev/null

    local total_lines=$(wc -l < "$temp_file")

    if [[ $line_id -lt 1 ]] || [[ $line_id -gt $total_lines ]]; then
        rm -f "$temp_file"
        error_exit "Invalid line number: $line_id (must be 1-$total_lines)" 2
    fi

    local removed_line=$(sed -n "${line_id}p" "$temp_file")

    warning "Removing cron job:"
    echo "  Line $line_id: $removed_line"
    echo ""

    read -p "Remove this job? (y/n): " -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$temp_file"
        info "Cancelled"
        return 0
    fi

    sed -i "${line_id}d" "$temp_file"

    if $cmd "$temp_file" 2>/dev/null; then
        success "Cron job removed successfully"
    else
        error_exit "Failed to remove cron job" 1
    fi

    rm -f "$temp_file"
}

backup_crontab() {
    local file="$1"
    local cmd=$(get_crontab_cmd)

    if ! $cmd -l &> /dev/null; then
        warning "No crontab to backup"
        return 0
    fi

    if $cmd -l > "$file" 2>/dev/null; then
        success "Crontab backed up to: $file"
    else
        error_exit "Failed to backup crontab" 1
    fi
}

restore_crontab() {
    local file="$1"
    local cmd=$(get_crontab_cmd)

    if [[ ! -f "$file" ]]; then
        error_exit "Backup file not found: $file" 2
    fi

    warning "This will replace current crontab"
    echo ""

    read -p "Continue? (y/n): " -r confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Cancelled"
        return 0
    fi

    if $cmd "$file" 2>/dev/null; then
        success "Crontab restored from: $file"
    else
        error_exit "Failed to restore crontab" 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -l|--list) LIST_JOBS=true; shift ;;
        -a|--add) ADD_JOB=true; shift ;;
        -r|--remove) REMOVE_ID="$2"; shift 2 ;;
        -e|--edit) EDIT_CRONTAB=true; shift ;;
        --validate) VALIDATE_EXPR="$2"; shift 2 ;;
        --test) TEST_EXPR="$2"; shift 2 ;;
        --backup) BACKUP_FILE="$2"; shift 2 ;;
        --restore) RESTORE_FILE="$2"; shift 2 ;;
        -u|--user) USER="$2"; shift 2 ;;
        -j|--json) JSON_OUTPUT=true; USE_COLOR=false; shift ;;
        --no-color) USE_COLOR=false; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

check_dependencies

if [[ "$LIST_JOBS" == true ]]; then
    list_cron_jobs
elif [[ "$ADD_JOB" == true ]]; then
    add_cron_job
elif [[ -n "$REMOVE_ID" ]]; then
    remove_cron_job "$REMOVE_ID"
elif [[ "$EDIT_CRONTAB" == true ]]; then
    $(get_crontab_cmd) -e
elif [[ -n "$VALIDATE_EXPR" ]]; then
    validate_cron_expression "$VALIDATE_EXPR"
elif [[ -n "$TEST_EXPR" ]]; then
    test_cron_schedule "$TEST_EXPR"
elif [[ -n "$BACKUP_FILE" ]]; then
    backup_crontab "$BACKUP_FILE"
elif [[ -n "$RESTORE_FILE" ]]; then
    restore_crontab "$RESTORE_FILE"
else
    list_cron_jobs
fi
