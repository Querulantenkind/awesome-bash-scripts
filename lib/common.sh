#!/bin/bash

################################################################################
# Common Library - Shared functions for all Awesome Bash Scripts
# Version: 1.0.0
# 
# This library provides common functionality used across all scripts including:
# - Enhanced logging with levels
# - Input validation functions  
# - Error handling utilities
# - System check functions
# - Formatting helpers
# - File operations
################################################################################

# Prevent multiple sourcing
[[ -n "$_ABS_COMMON_LOADED" ]] && return 0
readonly _ABS_COMMON_LOADED=1

################################################################################
# Global Configuration
################################################################################

# Set base directories
readonly ABS_BASE_DIR="${ABS_BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly ABS_LIB_DIR="${ABS_BASE_DIR}/lib"
readonly ABS_CONFIG_DIR="${ABS_BASE_DIR}/config"
readonly ABS_LOG_DIR="${ABS_LOG_DIR:-/tmp/awesome-bash-scripts}"

# Create log directory if it doesn't exist
[[ ! -d "$ABS_LOG_DIR" ]] && mkdir -p "$ABS_LOG_DIR"

################################################################################
# Logging Functions
################################################################################

# Log levels
readonly LOG_TRACE=0
readonly LOG_DEBUG=1
readonly LOG_INFO=2
readonly LOG_WARN=3
readonly LOG_ERROR=4
readonly LOG_FATAL=5

# Current log level (can be overridden)
LOG_LEVEL="${LOG_LEVEL:-$LOG_INFO}"

# Log to file and/or stdout
log() {
    local level="$1"
    local level_name="$2"
    shift 2
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if we should log this level
    [[ $level -lt $LOG_LEVEL ]] && return 0
    
    # Format message
    local log_message="[$timestamp] [$level_name] $message"
    
    # Log to file if specified
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$log_message" >> "$LOG_FILE"
    fi
    
    # Log to stdout with colors if not quiet
    if [[ "${QUIET:-false}" != "true" ]]; then
        case $level in
            $LOG_ERROR|$LOG_FATAL)
                echo -e "${RED}$log_message${NC}" >&2
                ;;
            $LOG_WARN)
                echo -e "${YELLOW}$log_message${NC}" >&2
                ;;
            $LOG_INFO)
                echo -e "${CYAN}$log_message${NC}"
                ;;
            $LOG_DEBUG|$LOG_TRACE)
                echo -e "${BLUE}$log_message${NC}"
                ;;
        esac
    fi
    
    # Exit on fatal
    [[ $level -eq $LOG_FATAL ]] && exit 1
}

# Convenience logging functions
log_trace() { log $LOG_TRACE "TRACE" "$@"; }
log_debug() { log $LOG_DEBUG "DEBUG" "$@"; }
log_info()  { log $LOG_INFO  "INFO"  "$@"; }
log_warn()  { log $LOG_WARN  "WARN"  "$@"; }
log_error() { log $LOG_ERROR "ERROR" "$@"; }
log_fatal() { log $LOG_FATAL "FATAL" "$@"; }

################################################################################
# Validation Functions
################################################################################

# Validate IP address
validate_ip() {
    local ip="$1"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $valid_ip_regex ]]; then
        # Check each octet
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    fi
    return 1
}

# Validate email
validate_email() {
    local email="$1"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ $email =~ $email_regex ]]
}

# Validate URL
validate_url() {
    local url="$1"
    local url_regex='^(https?|ftp)://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
    [[ $url =~ $url_regex ]]
}

# Validate file path (no special characters that could be dangerous)
validate_path() {
    local path="$1"
    # Allow only safe characters
    [[ "$path" =~ ^[a-zA-Z0-9._/~-]+$ ]]
}

# Validate integer
validate_integer() {
    local num="$1"
    [[ "$num" =~ ^-?[0-9]+$ ]]
}

# Validate positive integer
validate_positive_integer() {
    local num="$1"
    [[ "$num" =~ ^[0-9]+$ ]] && (( num > 0 ))
}

################################################################################
# System Check Functions
################################################################################

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Require root privileges
require_root() {
    if ! is_root; then
        log_fatal "This operation requires root privileges. Please run with sudo."
    fi
}

# Check if command exists
command_exists() {
    local cmd="$1"
    command -v "$cmd" &> /dev/null
}

# Require command to exist
require_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command_exists "$cmd"; then
        log_fatal "Required command '$cmd' not found. Please install $package."
    fi
}

# Check if running in a container
is_container() {
    [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null
}

# Get available memory in MB
get_available_memory() {
    local available=$(free -m | awk '/^Mem:/ {print $7}')
    echo "${available:-0}"
}

# Get CPU count
get_cpu_count() {
    nproc 2>/dev/null || echo 1
}

# Get disk usage percentage for path
get_disk_usage() {
    local path="${1:-/}"
    df "$path" | awk 'NR==2 {print $5}' | tr -d '%'
}

################################################################################
# String Manipulation Functions
################################################################################

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace
    echo -n "$var"
}

# Convert to lowercase
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert to uppercase
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Check if string contains substring
contains() {
    local string="$1"
    local substring="$2"
    [[ "$string" == *"$substring"* ]]
}

# Check if string starts with substring
starts_with() {
    local string="$1"
    local prefix="$2"
    [[ "$string" == "$prefix"* ]]
}

# Check if string ends with substring
ends_with() {
    local string="$1"
    local suffix="$2"
    [[ "$string" == *"$suffix" ]]
}

################################################################################
# File Operation Functions
################################################################################

# Safe file backup
backup_file() {
    local file="$1"
    local backup_suffix="${2:-.bak}"
    
    if [[ -f "$file" ]]; then
        local backup_file="${file}${backup_suffix}.$(date +%Y%m%d_%H%M%S)"
        cp -p "$file" "$backup_file"
        log_debug "Backed up $file to $backup_file"
        echo "$backup_file"
    fi
}

# Create temporary file
create_temp_file() {
    local prefix="${1:-abs}"
    local temp_file=$(mktemp "/tmp/${prefix}.XXXXXX")
    echo "$temp_file"
}

# Create temporary directory
create_temp_dir() {
    local prefix="${1:-abs}"
    local temp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXX")
    echo "$temp_dir"
}

# Safe file write with atomic operation
safe_write_file() {
    local file="$1"
    local content="$2"
    local temp_file=$(create_temp_file)
    
    echo "$content" > "$temp_file"
    mv -f "$temp_file" "$file"
}

# Check if file is writable (considering sudo)
is_writable() {
    local file="$1"
    
    if is_root; then
        return 0
    elif [[ -w "$file" ]]; then
        return 0
    elif [[ -w "$(dirname "$file")" ]]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Formatting Functions
################################################################################

# Convert bytes to human readable
human_readable_size() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit=0
    local size=$bytes
    
    while (( size >= 1024 && unit < ${#units[@]} - 1 )); do
        size=$(( size / 1024 ))
        (( unit++ ))
    done
    
    if (( unit == 0 )); then
        echo "${size}${units[$unit]}"
    else
        # Calculate with decimal
        local decimal=$(( (bytes * 10 / (1024 ** unit)) % 10 ))
        echo "${size}.${decimal}${units[$unit]}"
    fi
}

# Format duration from seconds
format_duration() {
    local seconds="$1"
    local days=$(( seconds / 86400 ))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$(( seconds % 60 ))
    
    local result=""
    [[ $days -gt 0 ]] && result="${days}d "
    [[ $hours -gt 0 ]] && result="${result}${hours}h "
    [[ $minutes -gt 0 ]] && result="${result}${minutes}m "
    result="${result}${secs}s"
    
    echo "$result"
}

# Generate progress bar
progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"
    
    local percent=$(( current * 100 / total ))
    local filled=$(( width * current / total ))
    local empty=$(( width - filled ))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %d%%" "$percent"
}

################################################################################
# Error Handling Functions
################################################################################

# Set error trap
set_error_trap() {
    trap 'error_handler $? $LINENO' ERR
}

# Error handler
error_handler() {
    local exit_code=$1
    local line_no=$2
    log_error "Script failed with exit code $exit_code at line $line_no"
}

# Cleanup handler
set_cleanup_trap() {
    local cleanup_function="$1"
    trap "$cleanup_function" EXIT INT TERM
}

################################################################################
# User Interaction Functions
################################################################################

# Ask yes/no question
ask_yes_no() {
    local question="$1"
    local default="${2:-no}"
    
    local prompt
    if [[ "$default" == "yes" ]]; then
        prompt="$question [Y/n]: "
    else
        prompt="$question [y/N]: "
    fi
    
    read -p "$prompt" -r response
    
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

# Select from menu
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    
    echo "$prompt"
    select opt in "${options[@]}"; do
        if [[ -n "$opt" ]]; then
            echo "$opt"
            return 0
        fi
    done
}

# Read password securely
read_password() {
    local prompt="${1:-Password: }"
    local password
    
    read -s -p "$prompt" password
    echo >&2  # New line after password
    echo "$password"
}

################################################################################
# Network Functions
################################################################################

# Check if host is reachable
is_reachable() {
    local host="$1"
    local timeout="${2:-5}"
    
    if command_exists ping; then
        ping -c 1 -W "$timeout" "$host" &> /dev/null
    elif command_exists curl; then
        curl --connect-timeout "$timeout" -s "$host" &> /dev/null
    else
        return 1
    fi
}

# Get public IP
get_public_ip() {
    local timeout="${1:-5}"
    
    for service in "ifconfig.me" "ipecho.net/plain" "icanhazip.com"; do
        local ip=$(curl -s --max-time "$timeout" "$service" 2>/dev/null)
        if validate_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    done
    
    return 1
}

################################################################################
# Export all functions
################################################################################

# This ensures functions are available to subshells
export -f log log_trace log_debug log_info log_warn log_error log_fatal
export -f validate_ip validate_port validate_email validate_url validate_path
export -f validate_integer validate_positive_integer
export -f is_root require_root command_exists require_command
export -f is_container get_available_memory get_cpu_count get_disk_usage
export -f trim to_lower to_upper contains starts_with ends_with
export -f backup_file create_temp_file create_temp_dir safe_write_file is_writable
export -f human_readable_size format_duration progress_bar
export -f set_error_trap error_handler set_cleanup_trap
export -f ask_yes_no select_option read_password
export -f is_reachable get_public_ip
