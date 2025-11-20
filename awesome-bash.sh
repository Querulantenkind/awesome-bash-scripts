#!/bin/bash

################################################################################
# Script Name: awesome-bash.sh
# Description: Interactive menu system for Awesome Bash Scripts collection.
#              Provides a user-friendly TUI for browsing and executing scripts.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./awesome-bash.sh [options] [script-name]
#
# Options:
#   -h, --help             Show help message
#   -l, --list             List all available scripts
#   -c, --category NAME    Show scripts in category
#   -s, --search TERM      Search scripts by name/description
#   -v, --version          Show version
#   --no-interactive       Run without interactive mode
#
# Examples:
#   ./awesome-bash.sh                    # Interactive menu
#   ./awesome-bash.sh --list            # List all scripts
#   ./awesome-bash.sh --category backup # Show backup scripts
#   ./awesome-bash.sh system-monitor    # Run specific script
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/colors.sh"

################################################################################
# Configuration
################################################################################

readonly VERSION="1.0.0"
readonly SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Menu state
CURRENT_CATEGORY=""
INTERACTIVE=true

################################################################################
# Script Discovery
################################################################################

# Discover all available scripts
discover_scripts() {
    declare -gA SCRIPTS
    declare -gA SCRIPT_CATEGORIES
    declare -gA SCRIPT_DESCRIPTIONS
    
    # Scan scripts directory
    for category_dir in "$SCRIPTS_DIR"/*; do
        if [[ -d "$category_dir" ]]; then
            local category=$(basename "$category_dir")
            
            for script in "$category_dir"/*.sh; do
                if [[ -f "$script" ]] && [[ -x "$script" ]]; then
                    local script_name=$(basename "$script" .sh)
                    
                    # Extract description from script
                    local description=$(grep -m 1 "^# Description:" "$script" | cut -d: -f2- | xargs)
                    [[ -z "$description" ]] && description="No description available"
                    
                    SCRIPTS["$script_name"]="$script"
                    SCRIPT_CATEGORIES["$script_name"]="$category"
                    SCRIPT_DESCRIPTIONS["$script_name"]="$description"
                fi
            done
        fi
    done
}

# Get scripts by category
get_scripts_by_category() {
    local category="$1"
    
    for script_name in "${!SCRIPTS[@]}"; do
        if [[ "${SCRIPT_CATEGORIES[$script_name]}" == "$category" ]]; then
            echo "$script_name"
        fi
    done | sort
}

# Get all categories
get_categories() {
    for category in "${SCRIPT_CATEGORIES[@]}"; do
        echo "$category"
    done | sort -u
}

# Search scripts
search_scripts() {
    local term="$1"
    local -a results=()
    
    for script_name in "${!SCRIPTS[@]}"; do
        if [[ "$script_name" =~ $term ]] || [[ "${SCRIPT_DESCRIPTIONS[$script_name]}" =~ $term ]]; then
            results+=("$script_name")
        fi
    done
    
    printf '%s\n' "${results[@]}" | sort
}

################################################################################
# Display Functions
################################################################################

# Display welcome screen
display_welcome() {
    clear
    cat << EOF
${BOLD_CYAN}
╔═══════════════════════════════════════════════════════════════════════╗
║                                                                       ║
║               ${BOLD_WHITE}AWESOME BASH SCRIPTS${BOLD_CYAN}                               ║
║                                                                       ║
║           ${WHITE}A Collection of Professional Bash Utilities${BOLD_CYAN}           ║
║                                                                       ║
║                       ${GRAY}Version $VERSION${BOLD_CYAN}                               ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
${NC}

${CYAN}Total Scripts:${NC} ${BOLD}${#SCRIPTS[@]}${NC}
${CYAN}Categories:${NC} ${BOLD}$(get_categories | wc -l)${NC}

EOF
}

# Display category menu
display_category_menu() {
    clear
    print_header "SCRIPT CATEGORIES" 70
    echo
    
    local -a categories=($(get_categories))
    local i=1
    
    for category in "${categories[@]}"; do
        local count=$(get_scripts_by_category "$category" | wc -l)
        printf "  ${CYAN}%2d)${NC} ${BOLD}%-20s${NC} ${GRAY}(%d scripts)${NC}\n" \
            "$i" "${category^}" "$count"
        ((i++))
    done
    
    echo
    printf "  ${CYAN} s)${NC} ${BOLD}Search${NC} scripts\n"
    printf "  ${CYAN} a)${NC} ${BOLD}Show all${NC} scripts\n"
    printf "  ${CYAN} c)${NC} ${BOLD}Configuration${NC} manager\n"
    printf "  ${CYAN} h)${NC} ${BOLD}Help${NC} and documentation\n"
    printf "  ${CYAN} q)${NC} ${BOLD}Quit${NC}\n"
    echo
}

# Display scripts in category
display_scripts_menu() {
    local category="$1"
    
    clear
    print_header "${category^^} SCRIPTS" 70
    echo
    
    local -a scripts=($(get_scripts_by_category "$category"))
    local i=1
    
    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "  ${YELLOW}No scripts in this category${NC}"
        echo
        read -p "Press Enter to continue..."
        return
    fi
    
    for script_name in "${scripts[@]}"; do
        local description="${SCRIPT_DESCRIPTIONS[$script_name]}"
        # Truncate description if too long
        if [[ ${#description} -gt 50 ]]; then
            description="${description:0:47}..."
        fi
        
        printf "  ${CYAN}%2d)${NC} ${BOLD}%-25s${NC} ${GRAY}%s${NC}\n" \
            "$i" "$script_name" "$description"
        ((i++))
    done
    
    echo
    printf "  ${CYAN} i)${NC} Show ${BOLD}info${NC} for a script\n"
    printf "  ${CYAN} b)${NC} ${BOLD}Back${NC} to categories\n"
    printf "  ${CYAN} q)${NC} ${BOLD}Quit${NC}\n"
    echo
}

# Display script info
display_script_info() {
    local script_name="$1"
    local script_path="${SCRIPTS[$script_name]}"
    
    clear
    print_header "${script_name^^}" 70
    echo
    
    # Extract information from script
    echo -e "${BOLD}Category:${NC} ${SCRIPT_CATEGORIES[$script_name]}"
    echo -e "${BOLD}Description:${NC} ${SCRIPT_DESCRIPTIONS[$script_name]}"
    echo -e "${BOLD}Location:${NC} $script_path"
    echo
    
    # Extract usage from script
    local in_usage=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ Usage: ]]; then
            in_usage=true
            echo -e "${BOLD}Usage:${NC}"
            echo "  ${line#\# Usage: }"
        elif [[ "$in_usage" == true ]] && [[ "$line" =~ ^#\ \  ]]; then
            echo "${line#\# }"
        elif [[ "$in_usage" == true ]] && [[ ! "$line" =~ ^# ]]; then
            break
        fi
    done < "$script_path"
    
    echo
    echo -e "${BOLD}Quick Actions:${NC}"
    echo "  1) Run script"
    echo "  2) Show full help"
    echo "  3) Edit script"
    echo "  4) Back"
    echo
}

# Display search results
display_search_results() {
    local term="$1"
    
    clear
    print_header "SEARCH RESULTS: \"$term\"" 70
    echo
    
    local -a results=($(search_scripts "$term"))
    
    if [[ ${#results[@]} -eq 0 ]]; then
        echo "  ${YELLOW}No scripts found matching \"$term\"${NC}"
        echo
        read -p "Press Enter to continue..."
        return
    fi
    
    local i=1
    for script_name in "${results[@]}"; do
        local category="${SCRIPT_CATEGORIES[$script_name]}"
        local description="${SCRIPT_DESCRIPTIONS[$script_name]}"
        
        if [[ ${#description} -gt 40 ]]; then
            description="${description:0:37}..."
        fi
        
        printf "  ${CYAN}%2d)${NC} ${BOLD}%-25s${NC} ${GRAY}[%s]${NC} %s\n" \
            "$i" "$script_name" "$category" "$description"
        ((i++))
    done
    
    echo
    printf "  ${CYAN} b)${NC} ${BOLD}Back${NC} to main menu\n"
    printf "  ${CYAN} s)${NC} ${BOLD}New search${NC}\n"
    echo
    
    # Return results for selection
    echo "${results[@]}"
}

################################################################################
# Script Execution
################################################################################

# Run script with arguments
run_script() {
    local script_name="$1"
    shift
    local args=("$@")
    
    local script_path="${SCRIPTS[$script_name]}"
    
    if [[ ! -f "$script_path" ]]; then
        error "Script not found: $script_name"
        return 1
    fi
    
    clear
    print_header "RUNNING: $script_name" 70
    echo
    
    # Run the script
    if [[ ${#args[@]} -gt 0 ]]; then
        "$script_path" "${args[@]}"
    else
        "$script_path"
    fi
    
    local exit_code=$?
    
    echo
    print_separator
    
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}Script completed successfully${NC}"
    else
        echo -e "${RED}Script failed with exit code: $exit_code${NC}"
    fi
    
    echo
    read -p "Press Enter to continue..."
}

# Run script with interactive argument prompt
run_script_interactive() {
    local script_name="$1"
    
    clear
    print_header "RUN: $script_name" 70
    echo
    
    echo "Enter arguments for the script (or press Enter for none):"
    read -p "> " args
    
    if [[ -n "$args" ]]; then
        run_script "$script_name" $args
    else
        run_script "$script_name"
    fi
}

################################################################################
# Menu Handlers
################################################################################

# Handle category menu
handle_category_menu() {
    local choice
    read -p "Enter choice: " choice
    
    case "$choice" in
        [0-9]*)
            local -a categories=($(get_categories))
            local idx=$((choice - 1))
            
            if [[ $idx -ge 0 ]] && [[ $idx -lt ${#categories[@]} ]]; then
                handle_scripts_menu "${categories[$idx]}"
            else
                error "Invalid selection"
                sleep 1
            fi
            ;;
        s|S)
            handle_search
            ;;
        a|A)
            handle_all_scripts
            ;;
        c|C)
            run_script "config-manager" "interactive"
            ;;
        h|H)
            show_help
            ;;
        q|Q)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            error "Invalid choice"
            sleep 1
            ;;
    esac
}

# Handle scripts menu
handle_scripts_menu() {
    local category="$1"
    
    while true; do
        display_scripts_menu "$category"
        
        local choice
        read -p "Enter choice: " choice
        
        case "$choice" in
            [0-9]*)
                local -a scripts=($(get_scripts_by_category "$category"))
                local idx=$((choice - 1))
                
                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#scripts[@]} ]]; then
                    handle_script_action "${scripts[$idx]}"
                else
                    error "Invalid selection"
                    sleep 1
                fi
                ;;
            i|I)
                read -p "Enter script number: " num
                local -a scripts=($(get_scripts_by_category "$category"))
                local idx=$((num - 1))
                
                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#scripts[@]} ]]; then
                    handle_script_info "${scripts[$idx]}"
                else
                    error "Invalid selection"
                    sleep 1
                fi
                ;;
            b|B)
                return
                ;;
            q|Q)
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

# Handle script info and actions
handle_script_info() {
    local script_name="$1"
    
    while true; do
        display_script_info "$script_name"
        
        local choice
        read -p "Enter choice: " choice
        
        case "$choice" in
            1)
                run_script_interactive "$script_name"
                ;;
            2)
                clear
                "${SCRIPTS[$script_name]}" --help
                echo
                read -p "Press Enter to continue..."
                ;;
            3)
                ${EDITOR:-vi} "${SCRIPTS[$script_name]}"
                ;;
            4)
                return
                ;;
            *)
                error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Handle script action
handle_script_action() {
    local script_name="$1"
    run_script_interactive "$script_name"
}

# Handle search
handle_search() {
    while true; do
        clear
        print_header "SEARCH SCRIPTS" 70
        echo
        
        read -p "Enter search term (or 'b' to go back): " term
        
        [[ "$term" == "b" ]] || [[ "$term" == "B" ]] && return
        [[ -z "$term" ]] && continue
        
        local results=$(display_search_results "$term")
        
        [[ -z "$results" ]] && continue
        
        read -p "Enter choice: " choice
        
        case "$choice" in
            [0-9]*)
                local -a result_array=($results)
                local idx=$((choice - 1))
                
                if [[ $idx -ge 0 ]] && [[ $idx -lt ${#result_array[@]} ]]; then
                    handle_script_action "${result_array[$idx]}"
                else
                    error "Invalid selection"
                    sleep 1
                fi
                ;;
            s|S)
                continue
                ;;
            b|B)
                return
                ;;
        esac
    done
}

# Show all scripts
handle_all_scripts() {
    clear
    print_header "ALL SCRIPTS" 70
    echo
    
    for category in $(get_categories); do
        echo -e "${BOLD_CYAN}${category^}:${NC}"
        
        for script_name in $(get_scripts_by_category "$category"); do
            printf "  ${CYAN}•${NC} %-25s ${GRAY}%s${NC}\n" \
                "$script_name" "${SCRIPT_DESCRIPTIONS[$script_name]:0:40}"
        done
        
        echo
    done
    
    read -p "Press Enter to continue..."
}

# Show help
show_help() {
    clear
    print_header "HELP & DOCUMENTATION" 70
    
    cat << EOF

${BOLD}Navigation:${NC}
  - Use numbers to select items
  - Use letters for special commands
  - Press 'q' to quit at any time
  - Press 'b' to go back

${BOLD}Script Execution:${NC}
  - Select a script to run it interactively
  - You'll be prompted for any arguments
  - Press 'i' to view script information

${BOLD}Configuration:${NC}
  - Use the Configuration Manager to customize settings
  - Configurations are saved per script and globally

${BOLD}Additional Commands:${NC}
  - List all scripts: ./awesome-bash.sh --list
  - Run specific script: ./awesome-bash.sh <script-name>
  - Search scripts: ./awesome-bash.sh --search <term>

${BOLD}Documentation:${NC}
  - README: $SCRIPT_DIR/README.md
  - Best Practices: $SCRIPT_DIR/docs/best-practices.md
  - Contributing: $SCRIPT_DIR/CONTRIBUTING.md

EOF
    
    read -p "Press Enter to continue..."
}

################################################################################
# Main Execution
################################################################################

# Show usage
show_usage() {
    cat << EOF
${WHITE}Awesome Bash Scripts - Interactive Menu${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] [SCRIPT_NAME]

${CYAN}Options:${NC}
    -h, --help             Show this help message
    -l, --list             List all available scripts
    -c, --category NAME    Show scripts in category
    -s, --search TERM      Search scripts
    -v, --version          Show version
    --no-interactive       Run without interactive mode

${CYAN}Examples:${NC}
    # Interactive menu
    $(basename "$0")
    
    # List all scripts
    $(basename "$0") --list
    
    # Show scripts in category
    $(basename "$0") --category backup
    
    # Search for scripts
    $(basename "$0") --search monitor
    
    # Run specific script
    $(basename "$0") system-monitor

${CYAN}Interactive Mode:${NC}
    The default mode provides a user-friendly menu to:
    - Browse scripts by category
    - Search for scripts
    - View script information
    - Execute scripts with arguments
    - Manage configurations

EOF
}

# Main function
main() {
    # Discover all scripts
    discover_scripts
    
    # Interactive mode
    if [[ "$INTERACTIVE" == true ]]; then
        display_welcome
        sleep 1
        
        while true; do
            display_category_menu
            handle_category_menu
        done
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--version)
            echo "Awesome Bash Scripts v$VERSION"
            exit 0
            ;;
        -l|--list)
            discover_scripts
            for category in $(get_categories); do
                echo "$category:"
                for script in $(get_scripts_by_category "$category"); do
                    echo "  - $script"
                done
                echo
            done
            exit 0
            ;;
        -c|--category)
            [[ -z "${2:-}" ]] && error_exit "Category required" 2
            discover_scripts
            for script in $(get_scripts_by_category "$2"); do
                echo "$script"
            done
            exit 0
            ;;
        -s|--search)
            [[ -z "${2:-}" ]] && error_exit "Search term required" 2
            discover_scripts
            search_scripts "$2"
            exit 0
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            # Run specific script
            discover_scripts
            if [[ -n "${SCRIPTS[$1]:-}" ]]; then
                shift
                run_script "$1" "$@"
                exit $?
            else
                error_exit "Script not found: $1" 1
            fi
            ;;
    esac
    shift
done

# Run main
main
