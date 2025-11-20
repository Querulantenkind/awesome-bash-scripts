#!/bin/bash

################################################################################
# Colors Library - ANSI color codes and formatting
# Version: 1.0.0
#
# This library provides consistent color and formatting codes across all scripts
################################################################################

# Prevent multiple sourcing
[[ -n "$_ABS_COLORS_LOADED" ]] && return 0
readonly _ABS_COLORS_LOADED=1

################################################################################
# Color Control
################################################################################

# Check if colors should be used
if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && [[ "${TERM:-}" != "dumb" ]] && [[ "${NO_COLOR:-}" != "true" ]]; then
    readonly USE_COLORS=true
else
    readonly USE_COLORS=false
fi

################################################################################
# Regular Colors
################################################################################

if [[ "$USE_COLORS" == true ]]; then
    # Regular colors
    readonly BLACK='\033[0;30m'
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[0;37m'
    readonly GRAY='\033[0;90m'
    
    # Light colors
    readonly LIGHT_RED='\033[0;91m'
    readonly LIGHT_GREEN='\033[0;92m'
    readonly LIGHT_YELLOW='\033[0;93m'
    readonly LIGHT_BLUE='\033[0;94m'
    readonly LIGHT_MAGENTA='\033[0;95m'
    readonly LIGHT_CYAN='\033[0;96m'
    readonly LIGHT_WHITE='\033[0;97m'
    
    # Bold colors
    readonly BOLD_BLACK='\033[1;30m'
    readonly BOLD_RED='\033[1;31m'
    readonly BOLD_GREEN='\033[1;32m'
    readonly BOLD_YELLOW='\033[1;33m'
    readonly BOLD_BLUE='\033[1;34m'
    readonly BOLD_MAGENTA='\033[1;35m'
    readonly BOLD_CYAN='\033[1;36m'
    readonly BOLD_WHITE='\033[1;37m'
    
    # Background colors
    readonly BG_BLACK='\033[40m'
    readonly BG_RED='\033[41m'
    readonly BG_GREEN='\033[42m'
    readonly BG_YELLOW='\033[43m'
    readonly BG_BLUE='\033[44m'
    readonly BG_MAGENTA='\033[45m'
    readonly BG_CYAN='\033[46m'
    readonly BG_WHITE='\033[47m'
    
    # Formatting
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly ITALIC='\033[3m'
    readonly UNDERLINE='\033[4m'
    readonly BLINK='\033[5m'
    readonly REVERSE='\033[7m'
    readonly HIDDEN='\033[8m'
    readonly STRIKETHROUGH='\033[9m'
    
    # Reset
    readonly NC='\033[0m'        # No Color / Reset
    readonly RESET='\033[0m'
else
    # No colors - all empty strings
    readonly BLACK=''
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly WHITE=''
    readonly GRAY=''
    
    readonly LIGHT_RED=''
    readonly LIGHT_GREEN=''
    readonly LIGHT_YELLOW=''
    readonly LIGHT_BLUE=''
    readonly LIGHT_MAGENTA=''
    readonly LIGHT_CYAN=''
    readonly LIGHT_WHITE=''
    
    readonly BOLD_BLACK=''
    readonly BOLD_RED=''
    readonly BOLD_GREEN=''
    readonly BOLD_YELLOW=''
    readonly BOLD_BLUE=''
    readonly BOLD_MAGENTA=''
    readonly BOLD_CYAN=''
    readonly BOLD_WHITE=''
    
    readonly BG_BLACK=''
    readonly BG_RED=''
    readonly BG_GREEN=''
    readonly BG_YELLOW=''
    readonly BG_BLUE=''
    readonly BG_MAGENTA=''
    readonly BG_CYAN=''
    readonly BG_WHITE=''
    
    readonly BOLD=''
    readonly DIM=''
    readonly ITALIC=''
    readonly UNDERLINE=''
    readonly BLINK=''
    readonly REVERSE=''
    readonly HIDDEN=''
    readonly STRIKETHROUGH=''
    
    readonly NC=''
    readonly RESET=''
fi

################################################################################
# Semantic Colors (for consistent meaning across scripts)
################################################################################

# Status colors
readonly COLOR_SUCCESS="$GREEN"
readonly COLOR_ERROR="$RED"
readonly COLOR_WARNING="$YELLOW"
readonly COLOR_INFO="$CYAN"
readonly COLOR_DEBUG="$BLUE"
readonly COLOR_TRACE="$GRAY"

# UI element colors
readonly COLOR_HEADER="$BOLD_WHITE"
readonly COLOR_SUBHEADER="$BOLD_CYAN"
readonly COLOR_PROMPT="$BOLD_YELLOW"
readonly COLOR_HIGHLIGHT="$BOLD_GREEN"
readonly COLOR_SECONDARY="$GRAY"

# Special purpose
readonly COLOR_CRITICAL="$BOLD_RED"
readonly COLOR_IMPORTANT="$BOLD_YELLOW"
readonly COLOR_NOTE="$ITALIC$CYAN"

################################################################################
# Unicode Symbols (with fallbacks)
################################################################################

# Check if terminal supports Unicode
if [[ "${LANG:-}" == *"UTF-8"* ]] || [[ "${LC_ALL:-}" == *"UTF-8"* ]]; then
    readonly SUPPORTS_UNICODE=true
else
    readonly SUPPORTS_UNICODE=false
fi

if [[ "$SUPPORTS_UNICODE" == true ]]; then
    # Status symbols
    readonly SYMBOL_SUCCESS="✓"
    readonly SYMBOL_ERROR="✗"
    readonly SYMBOL_WARNING="⚠"
    readonly SYMBOL_INFO="ℹ"
    readonly SYMBOL_QUESTION="?"
    readonly SYMBOL_ARROW_RIGHT="→"
    readonly SYMBOL_ARROW_LEFT="←"
    readonly SYMBOL_ARROW_UP="↑"
    readonly SYMBOL_ARROW_DOWN="↓"
    readonly SYMBOL_BULLET="•"
    readonly SYMBOL_STAR="★"
    readonly SYMBOL_HEART="♥"
    
    # Progress indicators
    readonly SYMBOL_PROGRESS_EMPTY="○"
    readonly SYMBOL_PROGRESS_FILLED="●"
    readonly SYMBOL_PROGRESS_PARTIAL="◐"
    
    # Box drawing
    readonly SYMBOL_BOX_HORIZONTAL="─"
    readonly SYMBOL_BOX_VERTICAL="│"
    readonly SYMBOL_BOX_TOP_LEFT="┌"
    readonly SYMBOL_BOX_TOP_RIGHT="┐"
    readonly SYMBOL_BOX_BOTTOM_LEFT="└"
    readonly SYMBOL_BOX_BOTTOM_RIGHT="┘"
    readonly SYMBOL_BOX_CROSS="┼"
else
    # ASCII fallbacks
    readonly SYMBOL_SUCCESS="[OK]"
    readonly SYMBOL_ERROR="[X]"
    readonly SYMBOL_WARNING="[!]"
    readonly SYMBOL_INFO="[i]"
    readonly SYMBOL_QUESTION="[?]"
    readonly SYMBOL_ARROW_RIGHT="->"
    readonly SYMBOL_ARROW_LEFT="<-"
    readonly SYMBOL_ARROW_UP="^"
    readonly SYMBOL_ARROW_DOWN="v"
    readonly SYMBOL_BULLET="*"
    readonly SYMBOL_STAR="*"
    readonly SYMBOL_HEART="<3"
    
    readonly SYMBOL_PROGRESS_EMPTY="o"
    readonly SYMBOL_PROGRESS_FILLED="O"
    readonly SYMBOL_PROGRESS_PARTIAL="o"
    
    readonly SYMBOL_BOX_HORIZONTAL="-"
    readonly SYMBOL_BOX_VERTICAL="|"
    readonly SYMBOL_BOX_TOP_LEFT="+"
    readonly SYMBOL_BOX_TOP_RIGHT="+"
    readonly SYMBOL_BOX_BOTTOM_LEFT="+"
    readonly SYMBOL_BOX_BOTTOM_RIGHT="+"
    readonly SYMBOL_BOX_CROSS="+"
fi

################################################################################
# Helper Functions
################################################################################

# Print colored text
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print status messages with symbols
print_success() {
    echo -e "${COLOR_SUCCESS}${SYMBOL_SUCCESS} $*${NC}"
}

print_error() {
    echo -e "${COLOR_ERROR}${SYMBOL_ERROR} $*${NC}" >&2
}

print_warning() {
    echo -e "${COLOR_WARNING}${SYMBOL_WARNING} $*${NC}" >&2
}

print_info() {
    echo -e "${COLOR_INFO}${SYMBOL_INFO} $*${NC}"
}

# Print header with box drawing
print_header() {
    local text="$1"
    local width="${2:-60}"
    local padding=$(( (width - ${#text} - 2) / 2 ))
    
    echo -e "${COLOR_HEADER}"
    echo -e "${SYMBOL_BOX_TOP_LEFT}$(printf '%*s' "$width" | tr ' ' "$SYMBOL_BOX_HORIZONTAL")${SYMBOL_BOX_TOP_RIGHT}"
    echo -e "${SYMBOL_BOX_VERTICAL}$(printf '%*s' "$padding")$text$(printf '%*s' $((width - padding - ${#text})))${SYMBOL_BOX_VERTICAL}"
    echo -e "${SYMBOL_BOX_BOTTOM_LEFT}$(printf '%*s' "$width" | tr ' ' "$SYMBOL_BOX_HORIZONTAL")${SYMBOL_BOX_BOTTOM_RIGHT}"
    echo -e "${NC}"
}

# Print separator line
print_separator() {
    local char="${1:-$SYMBOL_BOX_HORIZONTAL}"
    local width="${2:-60}"
    echo -e "${COLOR_SECONDARY}$(printf '%*s' "$width" | tr ' ' "$char")${NC}"
}

# Colorize text based on value
colorize_by_value() {
    local value="$1"
    local threshold_warning="${2:-80}"
    local threshold_critical="${3:-90}"
    
    if [[ "$value" -ge "$threshold_critical" ]]; then
        echo -e "${COLOR_CRITICAL}$value${NC}"
    elif [[ "$value" -ge "$threshold_warning" ]]; then
        echo -e "${COLOR_WARNING}$value${NC}"
    else
        echo -e "${COLOR_SUCCESS}$value${NC}"
    fi
}

# Strip ANSI color codes from text
strip_colors() {
    echo "$@" | sed -E 's/\x1b\[[0-9;]*m//g'
}

# Get the display width of text (excluding ANSI codes)
display_width() {
    local text="$1"
    local stripped=$(strip_colors "$text")
    echo "${#stripped}"
}

################################################################################
# Export functions
################################################################################

export -f print_color print_success print_error print_warning print_info
export -f print_header print_separator colorize_by_value
export -f strip_colors display_width
