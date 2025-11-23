#!/bin/bash

################################################################################
# Script Name: config-manager.sh
# Description: Configuration management tool for Awesome Bash Scripts.
#              Provides an interactive interface to view, edit, and manage
#              global and script-specific configurations.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./config-manager.sh [options] [command]
#
# Commands:
#   get KEY                 Get configuration value
#   set KEY VALUE          Set configuration value
#   delete KEY             Delete configuration value
#   list                   List all configurations
#   search PATTERN         Search configurations
#   edit                   Edit config file in $EDITOR
#   reset                  Reset to defaults
#   import FILE            Import configuration
#   export FILE            Export configuration
#   profile save NAME      Save current config as profile
#   profile load NAME      Load configuration profile
#   profile list           List available profiles
#   interactive            Interactive configuration mode
#
# Options:
#   -h, --help             Show help message
#   -s, --script NAME      Manage script-specific config
#   -v, --verbose          Verbose output
#   -q, --quiet            Quiet mode
#
# Examples:
#   ./config-manager.sh list
#   ./config-manager.sh get ABS_LOG_LEVEL
#   ./config-manager.sh set ABS_VERBOSE true
#   ./config-manager.sh -s backup-manager list
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
source "${SCRIPT_DIR}/../../lib/config.sh"

################################################################################
# Configuration
################################################################################

COMMAND=""
SCRIPT_NAME=""
VERBOSE=false
QUIET=false

################################################################################
# Display Functions
################################################################################

# Display configuration in a nice format
display_config() {
    local pattern="${1:-}"
    
    print_header "AWESOME BASH SCRIPTS CONFIGURATION" 70
    
    # Group configurations by prefix
    declare -A groups
    
    for key in $(config_list_keys); do
        if [[ -n "$pattern" ]] && [[ ! "$key" =~ $pattern ]]; then
            continue
        fi
        
        local prefix=$(echo "$key" | cut -d'_' -f1-2)
        groups["$prefix"]+="$key "
    done
    
    # Display each group
    for group in $(echo "${!groups[@]}" | tr ' ' '\n' | sort); do
        echo
        echo -e "${BOLD_CYAN}${group}:${NC}"
        print_separator "-" 70
        
        for key in ${groups[$group]}; do
            local value="${ABS_CONFIG[$key]}"
            
            # Colorize value based on type
            local colored_value
            if [[ "$value" == "true" ]]; then
                colored_value="${GREEN}$value${NC}"
            elif [[ "$value" == "false" ]]; then
                colored_value="${RED}$value${NC}"
            elif [[ "$value" =~ ^[0-9]+$ ]]; then
                colored_value="${CYAN}$value${NC}"
            elif [[ -z "$value" ]]; then
                colored_value="${GRAY}(empty)${NC}"
            else
                colored_value="$value"
            fi
            
            printf "  %-35s = %s\n" "$key" "$colored_value"
        done
    done
    
    echo
    print_separator "=" 70
}

# Display configuration summary
display_summary() {
    echo
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo "  Config Directory: $ABS_CONFIG_DIR"
    echo "  Main Config: $ABS_MAIN_CONFIG"
    echo "  Total Settings: $(config_list_keys | wc -l)"
    echo "  Profiles: $(config_list_profiles | wc -l)"
}

################################################################################
# Interactive Configuration
################################################################################

# Interactive configuration menu
interactive_config() {
    while true; do
        clear
        print_header "CONFIGURATION MANAGER" 70
        
        cat <<EOF

${BOLD}Select an option:${NC}

  ${CYAN}1)${NC} View all configurations
  ${CYAN}2)${NC} Search configurations
  ${CYAN}3)${NC} Set configuration value
  ${CYAN}4)${NC} Delete configuration value
  ${CYAN}5)${NC} Edit config file
  ${CYAN}6)${NC} Manage profiles
  ${CYAN}7)${NC} Reset to defaults
  ${CYAN}8)${NC} Import/Export
  ${CYAN}9)${NC} View summary
  ${CYAN}0)${NC} Exit

EOF
        
        read -p "Enter choice: " choice
        
        case "$choice" in
            1)
                clear
                display_config
                read -p "Press Enter to continue..."
                ;;
            2)
                read -p "Enter search pattern: " pattern
                clear
                display_config "$pattern"
                read -p "Press Enter to continue..."
                ;;
            3)
                read -p "Enter key: " key
                read -p "Enter value: " value
                config_set "$key" "$value"
                config_save
                success "Configuration updated"
                sleep 1
                ;;
            4)
                read -p "Enter key to delete: " key
                if ask_yes_no "Delete $key?"; then
                    config_delete "$key"
                    config_save
                    success "Configuration deleted"
                fi
                sleep 1
                ;;
            5)
                ${EDITOR:-vi} "$ABS_MAIN_CONFIG"
                config_load
                success "Configuration reloaded"
                sleep 1
                ;;
            6)
                profile_menu
                ;;
            7)
                if ask_yes_no "Reset all configurations to defaults?"; then
                    config_reset
                    success "Configuration reset"
                fi
                sleep 2
                ;;
            8)
                import_export_menu
                ;;
            9)
                clear
                display_config
                display_summary
                read -p "Press Enter to continue..."
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Profile management menu
profile_menu() {
    while true; do
        clear
        print_header "PROFILE MANAGEMENT" 70
        
        # List existing profiles
        local profiles=($(config_list_profiles))
        
        echo
        echo -e "${BOLD}Available Profiles:${NC}"
        if [[ ${#profiles[@]} -eq 0 ]]; then
            echo "  (none)"
        else
            for i in "${!profiles[@]}"; do
                echo "  $((i+1))) ${profiles[$i]}"
            done
        fi
        
        echo
        cat <<EOF
${BOLD}Options:${NC}

  ${CYAN}s)${NC} Save current config as profile
  ${CYAN}l)${NC} Load profile
  ${CYAN}d)${NC} Delete profile
  ${CYAN}b)${NC} Back

EOF
        
        read -p "Enter choice: " choice
        
        case "$choice" in
            s)
                read -p "Enter profile name: " name
                config_save_profile "$name"
                success "Profile saved: $name"
                sleep 1
                ;;
            l)
                if [[ ${#profiles[@]} -gt 0 ]]; then
                    read -p "Enter profile number or name: " selection
                    
                    if [[ "$selection" =~ ^[0-9]+$ ]]; then
                        local idx=$((selection - 1))
                        if [[ $idx -ge 0 ]] && [[ $idx -lt ${#profiles[@]} ]]; then
                            config_load_profile "${profiles[$idx]}"
                        else
                            error "Invalid selection"
                            sleep 1
                        fi
                    else
                        config_load_profile "$selection"
                    fi
                else
                    error "No profiles available"
                    sleep 1
                fi
                ;;
            d)
                if [[ ${#profiles[@]} -gt 0 ]]; then
                    read -p "Enter profile name to delete: " name
                    if ask_yes_no "Delete profile $name?"; then
                        rm -f "$ABS_CONFIG_DIR/profiles/${name}.conf"
                        success "Profile deleted"
                    fi
                else
                    error "No profiles available"
                fi
                sleep 1
                ;;
            b)
                return
                ;;
            *)
                error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Import/Export menu
import_export_menu() {
    clear
    print_header "IMPORT/EXPORT" 70
    
    cat <<EOF

${BOLD}Options:${NC}

  ${CYAN}1)${NC} Import configuration from file
  ${CYAN}2)${NC} Export configuration to file
  ${CYAN}3)${NC} Back

EOF
    
    read -p "Enter choice: " choice
    
    case "$choice" in
        1)
            read -p "Enter file to import: " file
            if [[ -f "$file" ]]; then
                config_import "$file"
            else
                error "File not found: $file"
            fi
            sleep 2
            ;;
        2)
            read -p "Enter file to export to: " file
            config_export "$file"
            sleep 2
            ;;
        3)
            return
            ;;
        *)
            error "Invalid choice"
            sleep 1
            ;;
    esac
}

################################################################################
# Command Handlers
################################################################################

# Handle get command
cmd_get() {
    local key="$1"
    
    if config_exists "$key"; then
        local value=$(config_get "$key")
        if [[ "$QUIET" != true ]]; then
            echo "$key=$value"
        else
            echo "$value"
        fi
    else
        error_exit "Configuration not found: $key" 1
    fi
}

# Handle set command
cmd_set() {
    local key="$1"
    local value="$2"
    
    config_set "$key" "$value"
    config_save
    
    [[ "$QUIET" != true ]] && success "Set $key=$value"
}

# Handle delete command
cmd_delete() {
    local key="$1"
    
    if ! config_exists "$key"; then
        error_exit "Configuration not found: $key" 1
    fi
    
    config_delete "$key"
    config_save
    
    [[ "$QUIET" != true ]] && success "Deleted $key"
}

# Handle list command
cmd_list() {
    if [[ "$QUIET" == true ]]; then
        config_list
    else
        display_config
        display_summary
    fi
}

# Handle search command
cmd_search() {
    local pattern="$1"
    
    if [[ "$QUIET" == true ]]; then
        config_search "$pattern"
    else
        display_config "$pattern"
    fi
}

# Handle edit command
cmd_edit() {
    local editor="${EDITOR:-vi}"
    
    if ! command_exists "$editor"; then
        editor="vi"
    fi
    
    $editor "$ABS_MAIN_CONFIG"
    config_load
    
    [[ "$QUIET" != true ]] && success "Configuration reloaded"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Awesome Bash Scripts - Configuration Manager${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] [COMMAND] [ARGS]

${CYAN}Commands:${NC}
    get KEY                 Get configuration value
    set KEY VALUE          Set configuration value
    delete KEY             Delete configuration value
    list                   List all configurations
    search PATTERN         Search configurations
    edit                   Edit config file in \$EDITOR
    reset                  Reset to defaults
    import FILE            Import configuration
    export FILE            Export configuration
    profile save NAME      Save current config as profile
    profile load NAME      Load configuration profile
    profile list           List available profiles
    interactive            Interactive configuration mode

${CYAN}Options:${NC}
    -h, --help             Show this help message
    -s, --script NAME      Manage script-specific config
    -v, --verbose          Verbose output
    -q, --quiet            Quiet mode

${CYAN}Examples:${NC}
    # View all configurations
    $(basename "$0") list
    
    # Get specific value
    $(basename "$0") get ABS_LOG_LEVEL
    
    # Set configuration
    $(basename "$0") set ABS_VERBOSE true
    
    # Search configurations
    $(basename "$0") search BACKUP
    
    # Edit interactively
    $(basename "$0") interactive
    
    # Manage script-specific config
    $(basename "$0") -s backup-manager list
    
    # Work with profiles
    $(basename "$0") profile save production
    $(basename "$0") profile load production

${CYAN}Configuration Files:${NC}
    Global:  $ABS_MAIN_CONFIG
    Scripts: $ABS_SCRIPT_CONFIG_DIR/

${CYAN}Environment Variables:${NC}
    All configuration values are exported as environment variables
    and can be used by scripts directly.

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
        -s|--script)
            [[ -z "${2:-}" ]] && error_exit "Script name required" 2
            SCRIPT_NAME="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        get|set|delete|list|search|edit|reset|import|export|profile|interactive)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Load script-specific config if specified
if [[ -n "$SCRIPT_NAME" ]]; then
    config_load_script "$SCRIPT_NAME"
fi

# Execute command
case "$COMMAND" in
    get)
        [[ $# -lt 1 ]] && error_exit "KEY required" 2
        cmd_get "$1"
        ;;
    set)
        [[ $# -lt 2 ]] && error_exit "KEY and VALUE required" 2
        cmd_set "$1" "$2"
        ;;
    delete)
        [[ $# -lt 1 ]] && error_exit "KEY required" 2
        cmd_delete "$1"
        ;;
    list)
        cmd_list
        ;;
    search)
        [[ $# -lt 1 ]] && error_exit "PATTERN required" 2
        cmd_search "$1"
        ;;
    edit)
        cmd_edit
        ;;
    reset)
        if [[ -n "$SCRIPT_NAME" ]]; then
            config_reset_script "$SCRIPT_NAME"
        else
            config_reset
        fi
        ;;
    import)
        [[ $# -lt 1 ]] && error_exit "FILE required" 2
        config_import "$1"
        ;;
    export)
        [[ $# -lt 1 ]] && error_exit "FILE required" 2
        config_export "$1"
        ;;
    profile)
        subcmd="${1:-list}"
        case "$subcmd" in
            save)
                [[ $# -lt 2 ]] && error_exit "NAME required" 2
                config_save_profile "$2"
                ;;
            load)
                [[ $# -lt 2 ]] && error_exit "NAME required" 2
                config_load_profile "$2"
                ;;
            list)
                config_list_profiles
                ;;
            *)
                error_exit "Unknown profile subcommand: $subcmd" 2
                ;;
        esac
        ;;
    interactive)
        interactive_config
        ;;
    "")
        # No command, show interactive mode
        interactive_config
        ;;
    *)
        error_exit "Unknown command: $COMMAND" 2
        ;;
esac
