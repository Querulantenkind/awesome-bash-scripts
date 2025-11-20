#!/bin/bash

################################################################################
# Script Name: ssh-hardening.sh
# Description: SSH server hardening and security auditing tool
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./ssh-hardening.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -a, --audit             Audit current SSH configuration
#   -H, --harden            Apply hardening measures
#   -b, --backup            Backup current SSH config before changes
#   -r, --restore FILE      Restore SSH config from backup
#   --check-keys            Check for weak SSH keys
#   --disable-root          Disable root login
#   --disable-password      Disable password authentication
#   --change-port PORT      Change SSH port (default: 22)
#   --max-auth-tries N      Set maximum authentication attempts
#   --dry-run               Show what would be changed without applying
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   # Audit current configuration
#   ./ssh-hardening.sh --audit
#
#   # Apply all hardening measures with backup
#   sudo ./ssh-hardening.sh --harden --backup
#
#   # Disable root login and password auth
#   sudo ./ssh-hardening.sh --disable-root --disable-password
#
#   # Change SSH port
#   sudo ./ssh-hardening.sh --change-port 2222 --dry-run
#
# Dependencies:
#   - openssh-server
#   - systemctl (for service management)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Not running as root (for hardening actions)
#   4 - Security issues found
################################################################################

set -euo pipefail

# Script directory and configuration
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
readonly NC='\033[0m' # No Color

# Configuration variables
VERBOSE=false
LOG_FILE=""
JSON_OUTPUT=false
AUDIT_MODE=false
HARDEN_MODE=false
BACKUP=false
RESTORE_FILE=""
CHECK_KEYS=false
DISABLE_ROOT=false
DISABLE_PASSWORD=false
CHANGE_PORT=0
MAX_AUTH_TRIES=0
DRY_RUN=false
USE_COLOR=true

# SSH configuration
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_BACKUP_DIR="/var/backups/ssh"
ISSUES_FOUND=0
WARNINGS_FOUND=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo "✓ $1"
    fi
}

warning() {
    if [[ "$USE_COLOR" == true ]]; then
        echo -e "${YELLOW}⚠ $1${NC}"
    else
        echo "⚠ $1"
    fi
    ((WARNINGS_FOUND++))
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
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}SSH Hardening - SSH Server Security Auditing and Hardening${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -a, --audit             Audit current SSH configuration
    -H, --harden            Apply recommended hardening measures
    -b, --backup            Backup SSH config before changes
    -r, --restore FILE      Restore SSH config from backup
    --check-keys            Check for weak SSH keys
    --disable-root          Disable root login
    --disable-password      Disable password authentication
    --change-port PORT      Change SSH port
    --max-auth-tries N      Set maximum authentication attempts
    --dry-run               Show what would be changed
    -j, --json              Output in JSON format
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Audit current SSH configuration
    $SCRIPT_NAME --audit

    # Apply all hardening measures (requires root)
    sudo $SCRIPT_NAME --harden --backup

    # Disable root login and password authentication
    sudo $SCRIPT_NAME --disable-root --disable-password

    # Change SSH port (dry run)
    sudo $SCRIPT_NAME --change-port 2222 --dry-run

    # Check for weak SSH keys
    $SCRIPT_NAME --check-keys

${CYAN}Hardening Measures:${NC}
    - Disable root login
    - Disable password authentication (key-based only)
    - Change default SSH port
    - Limit authentication attempts
    - Disable empty passwords
    - Disable X11 forwarding
    - Enable strict mode
    - Set proper permissions
    - Configure idle timeout
    - Limit user access
    - Enable logging

EOF
}

check_dependencies() {
    if [[ ! -f "$SSH_CONFIG" ]]; then
        error_exit "SSH config not found: $SSH_CONFIG\nIs OpenSSH server installed?" 3
    fi

    if ! command -v systemctl &> /dev/null; then
        warning "systemctl not found. Service restart may not work."
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        if [[ "$AUDIT_MODE" == true ]] || [[ "$CHECK_KEYS" == true ]]; then
            warning "Not running as root. Some information may be limited."
        else
            error_exit "This script must be run as root for hardening operations" 3
        fi
    fi
}

################################################################################
# Backup and Restore Functions
################################################################################

backup_ssh_config() {
    if [[ "$BACKUP" == false ]]; then
        return 0
    fi

    info "Backing up SSH configuration..."

    mkdir -p "$SSH_BACKUP_DIR"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${SSH_BACKUP_DIR}/sshd_config.${timestamp}"

    if [[ "$DRY_RUN" == false ]]; then
        cp "$SSH_CONFIG" "$backup_file" || error_exit "Failed to backup SSH config" 1
        success "Backup created: $backup_file"
        log_message "SSH config backed up to: $backup_file"
    else
        info "[DRY-RUN] Would backup to: $backup_file"
    fi
}

restore_ssh_config() {
    if [[ -z "$RESTORE_FILE" ]]; then
        return 0
    fi

    info "Restoring SSH configuration from: $RESTORE_FILE"

    if [[ ! -f "$RESTORE_FILE" ]]; then
        error_exit "Backup file not found: $RESTORE_FILE" 1
    fi

    if [[ "$DRY_RUN" == false ]]; then
        cp "$RESTORE_FILE" "$SSH_CONFIG" || error_exit "Failed to restore SSH config" 1
        success "SSH config restored"
        restart_ssh_service
    else
        info "[DRY-RUN] Would restore from: $RESTORE_FILE"
    fi
}

################################################################################
# Configuration Check Functions
################################################################################

get_ssh_config_value() {
    local key="$1"

    # Get value from sshd_config, handling comments
    grep -E "^[[:space:]]*${key}" "$SSH_CONFIG" 2>/dev/null | tail -1 | awk '{print $2}' || echo ""
}

check_config_setting() {
    local setting="$1"
    local expected="$2"
    local description="$3"

    local current=$(get_ssh_config_value "$setting")

    verbose "Checking $setting: current='$current', expected='$expected'"

    if [[ -z "$current" ]]; then
        warning "$description: Not configured (using default)"
        ((ISSUES_FOUND++))
        return 1
    elif [[ "$current" != "$expected" ]]; then
        warning "$description: Current='$current', Recommended='$expected'"
        ((ISSUES_FOUND++))
        return 1
    else
        success "$description: Configured correctly ($current)"
        return 0
    fi
}

################################################################################
# Audit Functions
################################################################################

audit_ssh_config() {
    info "Auditing SSH configuration..."
    echo ""

    # Check critical security settings
    check_config_setting "PermitRootLogin" "no" "Root login disabled"
    check_config_setting "PasswordAuthentication" "no" "Password authentication disabled"
    check_config_setting "PermitEmptyPasswords" "no" "Empty passwords disabled"
    check_config_setting "X11Forwarding" "no" "X11 forwarding disabled"
    check_config_setting "MaxAuthTries" "3" "Max authentication tries"
    check_config_setting "PubkeyAuthentication" "yes" "Public key authentication enabled"
    check_config_setting "Protocol" "2" "SSH Protocol 2"

    # Check additional security settings
    local port=$(get_ssh_config_value "Port")
    if [[ -z "$port" ]] || [[ "$port" == "22" ]]; then
        warning "SSH port: Using default port 22 (consider changing)"
        ((ISSUES_FOUND++))
    else
        success "SSH port: Changed to $port"
    fi

    # Check permissions
    check_file_permissions "$SSH_CONFIG" "600" "SSH config file permissions"

    # Check for AllowUsers or AllowGroups
    if grep -qE "^[[:space:]]*(AllowUsers|AllowGroups)" "$SSH_CONFIG"; then
        success "User access restrictions: Configured"
    else
        warning "User access restrictions: Not configured (all users allowed)"
        ((ISSUES_FOUND++))
    fi

    echo ""
    if [[ $ISSUES_FOUND -eq 0 ]]; then
        success "SSH configuration is secure!"
    else
        warning "Found $ISSUES_FOUND security issues"
    fi

    log_message "Audit completed: $ISSUES_FOUND issues, $WARNINGS_FOUND warnings"
}

check_file_permissions() {
    local file="$1"
    local expected_perms="$2"
    local description="$3"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    local current_perms=$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file" 2>/dev/null)

    if [[ "$current_perms" != "$expected_perms" ]] && [[ "$current_perms" != "0${expected_perms}" ]]; then
        warning "$description: Current=$current_perms, Expected=$expected_perms"
        ((ISSUES_FOUND++))
        return 1
    else
        success "$description: Correct ($current_perms)"
        return 0
    fi
}

check_weak_keys() {
    info "Checking for weak SSH keys..."

    local weak_keys_found=0

    # Check system host keys
    for key_file in /etc/ssh/ssh_host_*_key; do
        if [[ -f "$key_file" ]]; then
            local key_type=$(basename "$key_file" | sed 's/ssh_host_\(.*\)_key/\1/')
            local key_size=$(ssh-keygen -l -f "$key_file" 2>/dev/null | awk '{print $1}')

            verbose "Checking $key_file: type=$key_type, size=$key_size"

            case "$key_type" in
                rsa)
                    if [[ "$key_size" -lt 2048 ]]; then
                        warning "Weak RSA host key: $key_file (size: $key_size, minimum: 2048)"
                        ((weak_keys_found++))
                    else
                        success "RSA host key: $key_file ($key_size bits)"
                    fi
                    ;;
                dsa)
                    warning "DSA host key found: $key_file (DSA is deprecated)"
                    ((weak_keys_found++))
                    ;;
                ecdsa|ed25519)
                    success "Modern host key: $key_file ($key_type)"
                    ;;
            esac
        fi
    done

    if [[ $weak_keys_found -gt 0 ]]; then
        warning "Found $weak_keys_found weak or deprecated host keys"
        info "Regenerate keys with: sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key"
    else
        success "All host keys are strong"
    fi
}

################################################################################
# Hardening Functions
################################################################################

set_config_value() {
    local key="$1"
    local value="$2"
    local description="$3"

    verbose "Setting $key = $value"

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would set: $key $value"
        return 0
    fi

    # Check if setting already exists
    if grep -qE "^[[:space:]]*${key}" "$SSH_CONFIG"; then
        # Update existing setting
        sed -i.tmp "s/^[[:space:]]*${key}.*/${key} ${value}/" "$SSH_CONFIG"
        success "$description: Updated to $value"
    else
        # Add new setting
        echo "${key} ${value}" >> "$SSH_CONFIG"
        success "$description: Added with value $value"
    fi

    log_message "Set $key = $value"
}

apply_hardening() {
    info "Applying SSH hardening measures..."

    backup_ssh_config

    # Apply hardening settings
    set_config_value "PermitRootLogin" "no" "Root login"
    set_config_value "PasswordAuthentication" "no" "Password authentication"
    set_config_value "PermitEmptyPasswords" "no" "Empty passwords"
    set_config_value "X11Forwarding" "no" "X11 forwarding"
    set_config_value "MaxAuthTries" "3" "Max auth tries"
    set_config_value "PubkeyAuthentication" "yes" "Public key auth"
    set_config_value "Protocol" "2" "SSH protocol"
    set_config_value "LogLevel" "VERBOSE" "Log level"
    set_config_value "StrictModes" "yes" "Strict modes"
    set_config_value "IgnoreRhosts" "yes" "Ignore rhosts"
    set_config_value "HostbasedAuthentication" "no" "Host-based auth"
    set_config_value "PermitUserEnvironment" "no" "User environment"
    set_config_value "ClientAliveInterval" "300" "Client alive interval"
    set_config_value "ClientAliveCountMax" "2" "Client alive count"

    # Set proper permissions
    if [[ "$DRY_RUN" == false ]]; then
        chmod 600 "$SSH_CONFIG"
        success "SSH config permissions set to 600"
    else
        info "[DRY-RUN] Would set permissions to 600"
    fi

    success "Hardening measures applied"

    # Restart SSH service
    restart_ssh_service
}

restart_ssh_service() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would restart SSH service"
        return 0
    fi

    info "Restarting SSH service..."

    if command -v systemctl &> /dev/null; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            success "SSH service restarted"
        else
            error_exit "Failed to restart SSH service" 1
        fi
    else
        warning "Could not restart SSH service automatically"
        info "Please restart SSH manually: sudo service ssh restart"
    fi
}

################################################################################
# Individual Hardening Actions
################################################################################

disable_root_login() {
    info "Disabling root login..."
    backup_ssh_config
    set_config_value "PermitRootLogin" "no" "Root login"
    restart_ssh_service
}

disable_password_auth() {
    warning "Disabling password authentication. Ensure SSH keys are configured!"
    info "Users without SSH keys will not be able to login."

    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Operation cancelled"
        return 0
    fi

    backup_ssh_config
    set_config_value "PasswordAuthentication" "no" "Password authentication"
    set_config_value "PubkeyAuthentication" "yes" "Public key authentication"
    restart_ssh_service
}

change_ssh_port() {
    local new_port="$1"

    if [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
        error_exit "Invalid port number: $new_port (must be 1024-65535)" 2
    fi

    info "Changing SSH port to $new_port..."
    warning "Make sure firewall allows port $new_port before disconnecting!"

    backup_ssh_config
    set_config_value "Port" "$new_port" "SSH port"
    restart_ssh_service

    info "SSH port changed. Reconnect with: ssh -p $new_port user@host"
}

################################################################################
# Main Function
################################################################################

main() {
    check_dependencies
    check_root

    # Handle restore first if requested
    if [[ -n "$RESTORE_FILE" ]]; then
        restore_ssh_config
        exit 0
    fi

    # Run audit
    if [[ "$AUDIT_MODE" == true ]]; then
        audit_ssh_config
    fi

    # Check keys
    if [[ "$CHECK_KEYS" == true ]]; then
        check_weak_keys
    fi

    # Apply full hardening
    if [[ "$HARDEN_MODE" == true ]]; then
        apply_hardening
    fi

    # Individual actions
    if [[ "$DISABLE_ROOT" == true ]]; then
        disable_root_login
    fi

    if [[ "$DISABLE_PASSWORD" == true ]]; then
        disable_password_auth
    fi

    if [[ "$CHANGE_PORT" -gt 0 ]]; then
        change_ssh_port "$CHANGE_PORT"
    fi

    if [[ "$MAX_AUTH_TRIES" -gt 0 ]]; then
        backup_ssh_config
        set_config_value "MaxAuthTries" "$MAX_AUTH_TRIES" "Max auth tries"
        restart_ssh_service
    fi

    # Default action if no options specified
    if [[ "$AUDIT_MODE" == false ]] && [[ "$HARDEN_MODE" == false ]] && \
       [[ "$CHECK_KEYS" == false ]] && [[ "$DISABLE_ROOT" == false ]] && \
       [[ "$DISABLE_PASSWORD" == false ]] && [[ "$CHANGE_PORT" -eq 0 ]]; then
        info "No action specified. Running audit..."
        audit_ssh_config
    fi

    log_message "Script completed"
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
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -a|--audit)
            AUDIT_MODE=true
            shift
            ;;
        -H|--harden)
            HARDEN_MODE=true
            shift
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -r|--restore)
            RESTORE_FILE="$2"
            shift 2
            ;;
        --check-keys)
            CHECK_KEYS=true
            shift
            ;;
        --disable-root)
            DISABLE_ROOT=true
            shift
            ;;
        --disable-password)
            DISABLE_PASSWORD=true
            shift
            ;;
        --change-port)
            CHANGE_PORT="$2"
            shift 2
            ;;
        --max-auth-tries)
            MAX_AUTH_TRIES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        *)
            error_exit "Unknown option: $1\nUse -h or --help for usage information." 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

main

# Exit with appropriate code
if [[ $ISSUES_FOUND -gt 0 ]]; then
    exit 4
else
    exit 0
fi
