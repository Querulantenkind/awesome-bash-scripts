#!/bin/bash

################################################################################
# Script Name: user-manager.sh
# Description: Comprehensive user account management and auditing tool with
#              support for creating, modifying, and deleting user accounts,
#              password management, group operations, and detailed user activity
#              auditing. Includes lock/unlock, expiry management, and export.
# Author: Luca
# Created: 2025-11-20
# Modified: 2025-11-20
# Version: 1.0.0
#
# Usage: ./user-manager.sh [options] [command] [arguments]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -j, --json              Output in JSON format
#   -o, --output FILE       Save output to file
#   -l, --log FILE          Log operations to file
#   --no-color              Disable colored output
#
# Commands:
#   list                    List all users with details
#   create USERNAME         Create a new user
#   delete USERNAME         Delete a user
#   modify USERNAME         Modify user attributes
#   passwd USERNAME         Change user password
#   lock USERNAME           Lock user account
#   unlock USERNAME         Unlock user account
#   expire USERNAME DAYS    Set password expiry
#   groups USERNAME         Manage user groups
#   audit [USERNAME]        Show user activity audit
#   export [FORMAT]         Export user list (csv, json, txt)
#
# Examples:
#   # List all users
#   ./user-manager.sh list
#
#   # Create a new user
#   ./user-manager.sh create john
#
#   # Lock a user account
#   ./user-manager.sh lock john
#
#   # Set password expiry to 90 days
#   ./user-manager.sh expire john 90
#
#   # Export user list as JSON
#   ./user-manager.sh export json -o users.json
#
#   # Audit specific user
#   ./user-manager.sh audit john --verbose
#
# Dependencies:
#   - useradd, usermod, userdel (shadow-utils)
#   - passwd, chage (password management)
#   - getent (user database)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Permission denied (requires root)
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
COMMAND=""
USERNAME=""
ARGUMENT=""

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
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

warning() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}⚠ $1${NC}"
    else
        echo "⚠ $1"
    fi
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
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
    if [[ "$JSON_OUTPUT" == false ]] && [[ "$USE_COLOR" == true ]]; then
        echo ""
        echo -e "${WHITE}━━━ $1 ━━━${NC}"
    fi
}

show_usage() {
    cat << EOF
${WHITE}User Manager - Comprehensive User Account Management Tool${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS] COMMAND [ARGUMENTS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -j, --json              Output in JSON format
    -o, --output FILE       Save output to file
    -l, --log FILE          Log operations to file
    --no-color              Disable colored output

${CYAN}Commands:${NC}
    list                    List all users with details
    create USERNAME         Create a new user
    delete USERNAME         Delete a user account
    modify USERNAME         Modify user attributes
    passwd USERNAME         Change user password
    lock USERNAME           Lock user account
    unlock USERNAME         Unlock user account
    expire USERNAME DAYS    Set password expiry (days)
    groups USERNAME         Show/manage user groups
    audit [USERNAME]        Show user activity audit
    export FORMAT           Export user list (csv|json|txt)

${CYAN}Examples:${NC}
    # List all users
    $SCRIPT_NAME list

    # Create a new user with home directory
    $SCRIPT_NAME create john -v

    # Lock a user account
    $SCRIPT_NAME lock john

    # Set password expiry to 90 days
    $SCRIPT_NAME expire john 90

    # Export user list as JSON
    $SCRIPT_NAME export json -o users.json

    # Audit specific user activity
    $SCRIPT_NAME audit john --verbose

    # Unlock user and reset password
    $SCRIPT_NAME unlock john

${CYAN}Features:${NC}
    • Complete user lifecycle management
    • Password policy enforcement
    • Account locking/unlocking
    • Group membership management
    • User activity auditing
    • Multiple export formats
    • Detailed logging
    • JSON output support

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This command requires root privileges. Please run with sudo." 3
    fi
}

check_dependencies() {
    local missing_deps=()

    for cmd in useradd usermod userdel passwd chage getent; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 1
    fi
}

################################################################################
# User Management Functions
################################################################################

list_users() {
    section_header "USER LIST"

    verbose "Gathering user information..."

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo '  "users": ['

        local first=true
        getent passwd | while IFS=: read -r user pass uid gid gecos home shell; do
            # Skip system users (UID < 1000) unless verbose
            if [[ $uid -lt 1000 ]] && [[ "$VERBOSE" == false ]]; then
                continue
            fi

            [[ "$first" == false ]] && echo ","
            first=false

            local locked="false"
            passwd -S "$user" 2>/dev/null | grep -q " L " && locked="true"

            cat << USEREOF
    {
      "username": "$user",
      "uid": $uid,
      "gid": $gid,
      "home": "$home",
      "shell": "$shell",
      "gecos": "$gecos",
      "locked": $locked
    }
USEREOF
        done
        echo ""
        echo "  ]"
        echo "}"
    else
        printf "${CYAN}%-15s %-8s %-8s %-25s %-25s %-10s${NC}\n" "Username" "UID" "GID" "Home" "Shell" "Status"

        getent passwd | while IFS=: read -r user pass uid gid gecos home shell; do
            # Skip system users (UID < 1000) unless verbose
            if [[ $uid -lt 1000 ]] && [[ "$VERBOSE" == false ]]; then
                continue
            fi

            local status="${GREEN}active${NC}"
            if passwd -S "$user" 2>/dev/null | grep -q " L "; then
                status="${RED}locked${NC}"
            fi

            printf "%-15s %-8s %-8s %-25s %-25s " "$user" "$uid" "$gid" "$home" "$shell"
            echo -e "$status"
        done
    fi
}

create_user() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for create command" 2
    fi

    # Check if user already exists
    if id "$username" &>/dev/null; then
        error_exit "User '$username' already exists" 1
    fi

    verbose "Creating user: $username"

    # Interactive user creation
    echo -e "${CYAN}Creating new user: $username${NC}"

    read -p "Full name [optional]: " fullname
    read -p "Create home directory? [Y/n]: " create_home
    read -p "Default shell [/bin/bash]: " user_shell
    user_shell=${user_shell:-/bin/bash}

    local cmd_args=()
    cmd_args+=("-s" "$user_shell")

    [[ -n "$fullname" ]] && cmd_args+=("-c" "$fullname")

    if [[ "$create_home" != "n" ]] && [[ "$create_home" != "N" ]]; then
        cmd_args+=("-m")
    fi

    if useradd "${cmd_args[@]}" "$username"; then
        success "User '$username' created successfully"

        read -p "Set password now? [Y/n]: " set_pass
        if [[ "$set_pass" != "n" ]] && [[ "$set_pass" != "N" ]]; then
            passwd "$username"
        fi
    else
        error_exit "Failed to create user '$username'" 1
    fi
}

delete_user() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for delete command" 2
    fi

    # Check if user exists
    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    warning "About to delete user: $username"
    read -p "Remove home directory? [y/N]: " remove_home
    read -p "Are you sure? [y/N]: " confirm

    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        info "User deletion cancelled"
        return 0
    fi

    local cmd_args=()
    if [[ "$remove_home" == "y" ]] || [[ "$remove_home" == "Y" ]]; then
        cmd_args+=("-r")
    fi

    verbose "Deleting user: $username"

    if userdel "${cmd_args[@]}" "$username"; then
        success "User '$username' deleted successfully"
    else
        error_exit "Failed to delete user '$username'" 1
    fi
}

lock_user() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for lock command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    verbose "Locking user account: $username"

    if passwd -l "$username" &>/dev/null; then
        success "User '$username' locked successfully"
    else
        error_exit "Failed to lock user '$username'" 1
    fi
}

unlock_user() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for unlock command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    verbose "Unlocking user account: $username"

    if passwd -u "$username" &>/dev/null; then
        success "User '$username' unlocked successfully"
    else
        error_exit "Failed to unlock user '$username'" 1
    fi
}

change_password() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for passwd command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    verbose "Changing password for: $username"

    if passwd "$username"; then
        success "Password changed for user '$username'"
    else
        error_exit "Failed to change password for '$username'" 1
    fi
}

set_expiry() {
    check_root

    local username="$1"
    local days="$2"

    if [[ -z "$username" ]] || [[ -z "$days" ]]; then
        error_exit "Username and days required for expire command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        error_exit "Days must be a positive number" 2
    fi

    verbose "Setting password expiry for $username to $days days"

    if chage -M "$days" "$username"; then
        success "Password expiry set to $days days for user '$username'"
    else
        error_exit "Failed to set password expiry" 1
    fi
}

manage_groups() {
    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for groups command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    section_header "GROUP MEMBERSHIP: $username"

    local groups_list=$(id -Gn "$username")

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"username\": \"$username\","
        echo "  \"groups\": ["

        local first=true
        for group in $groups_list; do
            [[ "$first" == false ]] && echo ","
            first=false
            echo -n "    \"$group\""
        done
        echo ""
        echo "  ]"
        echo "}"
    else
        echo -e "${CYAN}User:${NC} $username"
        echo -e "${CYAN}Groups:${NC} $groups_list"

        if [[ $EUID -eq 0 ]]; then
            echo ""
            read -p "Add user to a group? [group name or Enter to skip]: " add_group
            if [[ -n "$add_group" ]]; then
                if usermod -aG "$add_group" "$username"; then
                    success "User '$username' added to group '$add_group'"
                else
                    warning "Failed to add user to group"
                fi
            fi
        fi
    fi
}

audit_user() {
    local username="${1:-}"

    section_header "USER ACTIVITY AUDIT"

    if [[ -n "$username" ]]; then
        if ! id "$username" &>/dev/null; then
            error_exit "User '$username' does not exist" 1
        fi

        verbose "Auditing user: $username"

        echo -e "${CYAN}User:${NC} $username"

        # Password info
        if [[ $EUID -eq 0 ]]; then
            local pass_info=$(chage -l "$username" 2>/dev/null)
            echo -e "\n${CYAN}Password Information:${NC}"
            echo "$pass_info"
        fi

        # Last login
        echo -e "\n${CYAN}Last Login:${NC}"
        lastlog -u "$username" 2>/dev/null || echo "No login data available"

        # Login history
        echo -e "\n${CYAN}Recent Login History:${NC}"
        last "$username" | head -10 2>/dev/null || echo "No login history available"

        # Running processes
        echo -e "\n${CYAN}Running Processes:${NC}"
        ps -U "$username" -o pid,cmd 2>/dev/null || echo "No processes running"

    else
        verbose "Auditing all users"

        echo -e "${CYAN}Currently Logged In Users:${NC}"
        who | awk '{print $1}' | sort -u

        echo -e "\n${CYAN}Failed Login Attempts (last 10):${NC}"
        lastb | head -10 2>/dev/null || echo "No failed login data available"

        echo -e "\n${CYAN}Last 10 Logins:${NC}"
        last | head -10 2>/dev/null || echo "No login data available"
    fi
}

export_users() {
    local format="${1:-txt}"

    verbose "Exporting users in $format format"

    case "$format" in
        json)
            JSON_OUTPUT=true
            list_users
            ;;
        csv)
            echo "Username,UID,GID,Home,Shell,Status"
            getent passwd | while IFS=: read -r user pass uid gid gecos home shell; do
                if [[ $uid -lt 1000 ]] && [[ "$VERBOSE" == false ]]; then
                    continue
                fi

                local status="active"
                passwd -S "$user" 2>/dev/null | grep -q " L " && status="locked"

                echo "$user,$uid,$gid,$home,$shell,$status"
            done
            ;;
        txt|*)
            list_users
            ;;
    esac

    success "User export completed"
}

modify_user() {
    check_root

    local username="$1"

    if [[ -z "$username" ]]; then
        error_exit "Username required for modify command" 2
    fi

    if ! id "$username" &>/dev/null; then
        error_exit "User '$username' does not exist" 1
    fi

    section_header "MODIFY USER: $username"

    echo "What would you like to modify?"
    echo "1) Shell"
    echo "2) Home directory"
    echo "3) Full name (GECOS)"
    echo "4) Add to group"
    echo "5) Primary group"
    read -p "Choice [1-5]: " choice

    case "$choice" in
        1)
            read -p "New shell: " new_shell
            if usermod -s "$new_shell" "$username"; then
                success "Shell updated for user '$username'"
            fi
            ;;
        2)
            read -p "New home directory: " new_home
            read -p "Move contents? [y/N]: " move
            if [[ "$move" == "y" ]] || [[ "$move" == "Y" ]]; then
                usermod -m -d "$new_home" "$username"
            else
                usermod -d "$new_home" "$username"
            fi
            success "Home directory updated for user '$username'"
            ;;
        3)
            read -p "New full name: " new_gecos
            if usermod -c "$new_gecos" "$username"; then
                success "Full name updated for user '$username'"
            fi
            ;;
        4)
            read -p "Group name: " group_name
            if usermod -aG "$group_name" "$username"; then
                success "User '$username' added to group '$group_name'"
            fi
            ;;
        5)
            read -p "Primary group: " prim_group
            if usermod -g "$prim_group" "$username"; then
                success "Primary group updated for user '$username'"
            fi
            ;;
        *)
            warning "Invalid choice"
            ;;
    esac
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
        list|create|delete|modify|passwd|lock|unlock|expire|groups|audit|export)
            COMMAND="$1"
            shift
            # Get username if provided
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                USERNAME="$1"
                shift
                # Get additional argument for expire command
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                    ARGUMENT="$1"
                    shift
                fi
            fi
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            # If we haven't set a command yet, this might be it
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"
            elif [[ -z "$USERNAME" ]]; then
                USERNAME="$1"
            elif [[ -z "$ARGUMENT" ]]; then
                ARGUMENT="$1"
            fi
            shift
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

check_dependencies

# If no command specified, show usage
if [[ -z "$COMMAND" ]]; then
    show_usage
    exit 0
fi

# Execute command
output=""

case "$COMMAND" in
    list)
        output=$(list_users)
        ;;
    create)
        output=$(create_user "$USERNAME")
        ;;
    delete)
        output=$(delete_user "$USERNAME")
        ;;
    modify)
        output=$(modify_user "$USERNAME")
        ;;
    passwd)
        output=$(change_password "$USERNAME")
        ;;
    lock)
        output=$(lock_user "$USERNAME")
        ;;
    unlock)
        output=$(unlock_user "$USERNAME")
        ;;
    expire)
        output=$(set_expiry "$USERNAME" "$ARGUMENT")
        ;;
    groups)
        output=$(manage_groups "$USERNAME")
        ;;
    audit)
        output=$(audit_user "$USERNAME")
        ;;
    export)
        output=$(export_users "$USERNAME")
        ;;
    *)
        error_exit "Unknown command: $COMMAND" 2
        ;;
esac

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$output" > "$OUTPUT_FILE"
    success "Output saved to: $OUTPUT_FILE"
else
    echo "$output"
fi

verbose "Operation completed successfully"
