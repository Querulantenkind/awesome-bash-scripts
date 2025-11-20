#!/bin/bash

################################################################################
# Config Library - Configuration management for Awesome Bash Scripts
# Version: 1.0.0
#
# This library provides centralized configuration management for all scripts
################################################################################

# Prevent multiple sourcing
[[ -n "$_ABS_CONFIG_LOADED" ]] && return 0
readonly _ABS_CONFIG_LOADED=1

# Source common library
source "${ABS_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/common.sh"

################################################################################
# Configuration Paths
################################################################################

# System config directory
readonly ABS_SYSTEM_CONFIG_DIR="/etc/awesome-bash-scripts"

# User config directory
readonly ABS_USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/awesome-bash-scripts"

# Legacy config directory
readonly ABS_LEGACY_CONFIG_DIR="$HOME/.awesome-bash-scripts"

# Determine which config directory to use
get_config_dir() {
    if [[ -d "$ABS_USER_CONFIG_DIR" ]]; then
        echo "$ABS_USER_CONFIG_DIR"
    elif [[ -d "$ABS_LEGACY_CONFIG_DIR" ]]; then
        echo "$ABS_LEGACY_CONFIG_DIR"
    else
        mkdir -p "$ABS_USER_CONFIG_DIR"
        echo "$ABS_USER_CONFIG_DIR"
    fi
}

readonly ABS_CONFIG_DIR="$(get_config_dir)"

# Main config file
readonly ABS_MAIN_CONFIG="$ABS_CONFIG_DIR/config.conf"

# Script-specific config directory
readonly ABS_SCRIPT_CONFIG_DIR="$ABS_CONFIG_DIR/scripts.d"

################################################################################
# Configuration Variables Storage
################################################################################

# Associative array to store all config values
declare -gA ABS_CONFIG

################################################################################
# Config File Operations
################################################################################

# Initialize config directory structure
config_init() {
    # Create directories
    mkdir -p "$ABS_CONFIG_DIR"
    mkdir -p "$ABS_SCRIPT_CONFIG_DIR"
    
    # Create default config if it doesn't exist
    if [[ ! -f "$ABS_MAIN_CONFIG" ]]; then
        create_default_config
    fi
    
    log_debug "Config initialized at $ABS_CONFIG_DIR"
}

# Create default configuration file
create_default_config() {
    cat > "$ABS_MAIN_CONFIG" <<EOF
# Awesome Bash Scripts - Global Configuration
# Created: $(date)

# General Settings
ABS_LOG_LEVEL=INFO
ABS_LOG_DIR=/tmp/awesome-bash-scripts
ABS_TEMP_DIR=/tmp

# Output Settings
ABS_COLOR_OUTPUT=true
ABS_VERBOSE=false
ABS_QUIET=false
ABS_DEFAULT_FORMAT=text

# Notification Settings
ABS_NOTIFY_DESKTOP=true
ABS_NOTIFY_EMAIL=false
ABS_NOTIFY_SYSLOG=true
ABS_NOTIFY_WEBHOOK=false
ABS_NOTIFY_EMAIL_TO=
ABS_NOTIFY_WEBHOOK_URL=

# Performance Settings
ABS_MAX_PARALLEL_JOBS=4
ABS_TIMEOUT=30

# Backup Settings
ABS_BACKUP_DIR=$HOME/backups
ABS_BACKUP_RETENTION_DAYS=30
ABS_BACKUP_COMPRESSION=gzip
ABS_BACKUP_ENCRYPT=false

# Monitoring Settings
ABS_MONITOR_INTERVAL=5
ABS_MONITOR_CPU_THRESHOLD=80
ABS_MONITOR_MEM_THRESHOLD=80
ABS_MONITOR_DISK_THRESHOLD=90

# Network Settings
ABS_NETWORK_TIMEOUT=10
ABS_NETWORK_RETRIES=3

# Security Settings
ABS_REQUIRE_CONFIRMATION=true
ABS_AUDIT_LOG=true
ABS_AUDIT_LOG_FILE=$HOME/.local/share/awesome-bash-scripts/audit.log
EOF
    
    chmod 600 "$ABS_MAIN_CONFIG"
    log_info "Created default config at $ABS_MAIN_CONFIG"
}

# Load configuration from file
config_load() {
    local config_file="${1:-$ABS_MAIN_CONFIG}"
    
    if [[ ! -f "$config_file" ]]; then
        log_debug "Config file not found: $config_file"
        return 1
    fi
    
    # Read config file and populate ABS_CONFIG array
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Trim whitespace
        key=$(trim "$key")
        value=$(trim "$value")
        
        # Remove quotes if present
        value="${value%\"}"
        value="${value#\"}"
        
        # Store in config array
        ABS_CONFIG["$key"]="$value"
        
        # Also export as environment variable
        export "$key=$value"
    done < "$config_file"
    
    log_debug "Loaded config from $config_file"
}

# Save configuration to file
config_save() {
    local config_file="${1:-$ABS_MAIN_CONFIG}"
    
    # Backup existing config
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_file.bak"
    fi
    
    # Write header
    cat > "$config_file" <<EOF
# Awesome Bash Scripts - Global Configuration
# Last updated: $(date)

EOF
    
    # Write all config values
    for key in $(echo "${!ABS_CONFIG[@]}" | tr ' ' '\n' | sort); do
        local value="${ABS_CONFIG[$key]}"
        echo "$key=$value" >> "$config_file"
    done
    
    chmod 600 "$config_file"
    log_info "Config saved to $config_file"
}

################################################################################
# Config Value Management
################################################################################

# Get config value
config_get() {
    local key="$1"
    local default="${2:-}"
    
    # Check if key exists in config array
    if [[ -n "${ABS_CONFIG[$key]:-}" ]]; then
        echo "${ABS_CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# Set config value
config_set() {
    local key="$1"
    local value="$2"
    
    ABS_CONFIG["$key"]="$value"
    export "$key=$value"
    
    log_debug "Set config: $key=$value"
}

# Delete config value
config_delete() {
    local key="$1"
    
    unset "ABS_CONFIG[$key]"
    unset "$key"
    
    log_debug "Deleted config: $key"
}

# Check if config key exists
config_exists() {
    local key="$1"
    [[ -n "${ABS_CONFIG[$key]:-}" ]]
}

# List all config keys
config_list_keys() {
    echo "${!ABS_CONFIG[@]}" | tr ' ' '\n' | sort
}

# List all config values
config_list() {
    for key in $(config_list_keys); do
        echo "$key=${ABS_CONFIG[$key]}"
    done
}

# Search config by pattern
config_search() {
    local pattern="$1"
    
    for key in $(config_list_keys); do
        if [[ "$key" =~ $pattern ]]; then
            echo "$key=${ABS_CONFIG[$key]}"
        fi
    done
}

################################################################################
# Script-Specific Configuration
################################################################################

# Load script-specific config
config_load_script() {
    local script_name="$1"
    local config_file="$ABS_SCRIPT_CONFIG_DIR/${script_name}.conf"
    
    if [[ -f "$config_file" ]]; then
        config_load "$config_file"
        log_debug "Loaded script config: $config_file"
        return 0
    fi
    
    return 1
}

# Save script-specific config
config_save_script() {
    local script_name="$1"
    local config_file="$ABS_SCRIPT_CONFIG_DIR/${script_name}.conf"
    
    mkdir -p "$ABS_SCRIPT_CONFIG_DIR"
    config_save "$config_file"
}

# Create script-specific config template
config_create_script_template() {
    local script_name="$1"
    local config_file="$ABS_SCRIPT_CONFIG_DIR/${script_name}.conf"
    
    if [[ -f "$config_file" ]]; then
        warning "Config already exists: $config_file"
        return 1
    fi
    
    cat > "$config_file" <<EOF
# Configuration for $script_name
# Created: $(date)

# Add your script-specific configuration here
EOF
    
    chmod 600 "$config_file"
    success "Created config template: $config_file"
}

################################################################################
# Configuration Validation
################################################################################

# Validate boolean value
config_validate_bool() {
    local value="$1"
    [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]]
}

# Validate integer value
config_validate_int() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+$ ]]
}

# Validate path
config_validate_path() {
    local value="$1"
    [[ -d "$value" ]] || [[ -f "$value" ]]
}

# Validate URL
config_validate_url() {
    local value="$1"
    [[ "$value" =~ ^https?:// ]]
}

# Validate email
config_validate_email() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

################################################################################
# Configuration Migration
################################################################################

# Migrate config from old location
config_migrate() {
    local old_config="$ABS_LEGACY_CONFIG_DIR/config.conf"
    
    if [[ -f "$old_config" ]] && [[ ! -f "$ABS_MAIN_CONFIG" ]]; then
        log_info "Migrating config from $old_config to $ABS_MAIN_CONFIG"
        
        mkdir -p "$ABS_CONFIG_DIR"
        cp "$old_config" "$ABS_MAIN_CONFIG"
        
        success "Config migrated successfully"
    fi
}

# Import config from another file
config_import() {
    local import_file="$1"
    
    if [[ ! -f "$import_file" ]]; then
        error_exit "Import file not found: $import_file" 1
    fi
    
    log_info "Importing config from $import_file"
    config_load "$import_file"
    config_save
    
    success "Config imported successfully"
}

# Export config to file
config_export() {
    local export_file="$1"
    
    config_save "$export_file"
    success "Config exported to $export_file"
}

################################################################################
# Configuration Reset
################################################################################

# Reset config to defaults
config_reset() {
    warning "Resetting configuration to defaults"
    
    # Backup current config
    if [[ -f "$ABS_MAIN_CONFIG" ]]; then
        local backup="$ABS_MAIN_CONFIG.$(date +%Y%m%d_%H%M%S).bak"
        cp "$ABS_MAIN_CONFIG" "$backup"
        log_info "Backed up current config to $backup"
    fi
    
    # Clear current config
    ABS_CONFIG=()
    
    # Create new default config
    create_default_config
    config_load
    
    success "Configuration reset to defaults"
}

# Reset specific script config
config_reset_script() {
    local script_name="$1"
    local config_file="$ABS_SCRIPT_CONFIG_DIR/${script_name}.conf"
    
    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        success "Reset config for $script_name"
    else
        warning "No config found for $script_name"
    fi
}

################################################################################
# Configuration Profiles
################################################################################

# Save current config as a profile
config_save_profile() {
    local profile_name="$1"
    local profile_file="$ABS_CONFIG_DIR/profiles/${profile_name}.conf"
    
    mkdir -p "$ABS_CONFIG_DIR/profiles"
    config_save "$profile_file"
    
    success "Saved profile: $profile_name"
}

# Load a configuration profile
config_load_profile() {
    local profile_name="$1"
    local profile_file="$ABS_CONFIG_DIR/profiles/${profile_name}.conf"
    
    if [[ ! -f "$profile_file" ]]; then
        error_exit "Profile not found: $profile_name" 1
    fi
    
    config_load "$profile_file"
    config_save
    
    success "Loaded profile: $profile_name"
}

# List all profiles
config_list_profiles() {
    local profiles_dir="$ABS_CONFIG_DIR/profiles"
    
    if [[ -d "$profiles_dir" ]]; then
        for profile in "$profiles_dir"/*.conf; do
            if [[ -f "$profile" ]]; then
                basename "$profile" .conf
            fi
        done
    fi
}

################################################################################
# Auto-initialization
################################################################################

# Initialize configuration on library load
if [[ -z "${ABS_CONFIG_NO_AUTO_INIT:-}" ]]; then
    config_init
    config_migrate
    config_load
fi

################################################################################
# Export functions
################################################################################

export -f config_init config_load config_save
export -f config_get config_set config_delete config_exists
export -f config_list config_list_keys config_search
export -f config_load_script config_save_script
export -f config_reset config_import config_export
export -f config_save_profile config_load_profile config_list_profiles
