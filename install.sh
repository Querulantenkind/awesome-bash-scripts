#!/bin/bash

################################################################################
# Script Name: install.sh
# Description: Universal installer for Awesome Bash Scripts. Detects OS,
#              installs dependencies, sets up PATH, creates symlinks, and
#              configures the environment for all scripts.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./install.sh [options]
#
# Options:
#   -h, --help          Show help message
#   -u, --user          Install for current user only (default)
#   -s, --system        Install system-wide (requires sudo)
#   -d, --dir DIR       Custom installation directory
#   -l, --link          Create symlinks only (no copy)
#   --no-deps           Skip dependency installation
#   --uninstall         Uninstall awesome-bash-scripts
#
# Examples:
#   ./install.sh                    # User install with dependencies
#   sudo ./install.sh --system      # System-wide install
#   ./install.sh --dir ~/scripts    # Custom location
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependencies
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
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Installation configuration
INSTALL_TYPE="user"
INSTALL_DIR=""
LINK_ONLY=false
INSTALL_DEPS=true
UNINSTALL=false

# Default directories
USER_INSTALL_DIR="$HOME/.local/share/awesome-bash-scripts"
USER_BIN_DIR="$HOME/.local/bin"
SYSTEM_INSTALL_DIR="/opt/awesome-bash-scripts"
SYSTEM_BIN_DIR="/usr/local/bin"

# Required dependencies
REQUIRED_DEPS=(
    "bc:bc:bc:bc:Basic calculator"
    "jq:jq:jq:jq:JSON processor"
    "curl:curl:curl:curl:URL transfer tool"
    "rsync:rsync:rsync:rsync:File sync tool"
    "git:git:git:git:Version control"
)

# Optional dependencies
OPTIONAL_DEPS=(
    "notify-send:libnotify-bin:libnotify:libnotify:Desktop notifications"
    "mail:mailutils:mailx:mailutils:Email support"
    "shellcheck:shellcheck:shellcheck:shellcheck:Script linting"
)

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

show_usage() {
    cat << EOF
${WHITE}Awesome Bash Scripts Installer${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help          Show this help message
    -u, --user          Install for current user only (default)
    -s, --system        Install system-wide (requires sudo)
    -d, --dir DIR       Custom installation directory
    -l, --link          Create symlinks only (don't copy files)
    --no-deps           Skip dependency installation
    --uninstall         Uninstall awesome-bash-scripts

${CYAN}Examples:${NC}
    # User installation (recommended)
    $SCRIPT_NAME

    # System-wide installation
    sudo $SCRIPT_NAME --system

    # Custom directory
    $SCRIPT_NAME --dir ~/my-scripts

    # Create symlinks only
    $SCRIPT_NAME --link

    # Uninstall
    $SCRIPT_NAME --uninstall

${CYAN}Installation Locations:${NC}
    User Install:
        Scripts: $USER_INSTALL_DIR
        Binaries: $USER_BIN_DIR

    System Install:
        Scripts: $SYSTEM_INSTALL_DIR
        Binaries: $SYSTEM_BIN_DIR

EOF
}

################################################################################
# Detection Functions
################################################################################

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

check_sudo() {
    if [[ "$INSTALL_TYPE" == "system" ]] && [[ $EUID -ne 0 ]]; then
        error_exit "System installation requires root privileges. Please run with sudo." 1
    fi
}

################################################################################
# Dependency Management
################################################################################

install_dependencies() {
    local pkg_manager=$(detect_package_manager)
    local os=$(detect_os)
    
    info "Detected OS: $os"
    info "Package manager: $pkg_manager"
    
    # Update package list
    case "$pkg_manager" in
        apt)
            sudo apt-get update -qq
            ;;
        dnf|yum)
            sudo $pkg_manager makecache -q
            ;;
        pacman)
            sudo pacman -Sy --noconfirm
            ;;
    esac
    
    # Install required dependencies
    echo ""
    info "Installing required dependencies..."
    
    for dep_info in "${REQUIRED_DEPS[@]}"; do
        IFS=':' read -r cmd apt_pkg dnf_pkg pacman_pkg desc <<< "$dep_info"
        
        if ! command -v "$cmd" &> /dev/null; then
            echo -n "Installing $desc ($cmd)... "
            
            case "$pkg_manager" in
                apt)
                    sudo apt-get install -y -qq "$apt_pkg" &> /dev/null && echo "✓" || echo "✗"
                    ;;
                dnf|yum)
                    sudo $pkg_manager install -y -q "$dnf_pkg" &> /dev/null && echo "✓" || echo "✗"
                    ;;
                pacman)
                    sudo pacman -S --noconfirm --quiet "$pacman_pkg" &> /dev/null && echo "✓" || echo "✗"
                    ;;
                *)
                    warning "Please install $cmd manually"
                    ;;
            esac
        else
            success "$desc ($cmd) already installed"
        fi
    done
    
    # Install optional dependencies
    echo ""
    info "Checking optional dependencies..."
    
    for dep_info in "${OPTIONAL_DEPS[@]}"; do
        IFS=':' read -r cmd apt_pkg dnf_pkg pacman_pkg desc <<< "$dep_info"
        
        if ! command -v "$cmd" &> /dev/null; then
            warning "$desc ($cmd) not installed - some features may be limited"
        else
            success "$desc ($cmd) available"
        fi
    done
}

################################################################################
# Installation Functions
################################################################################

create_directories() {
    local install_dir="$1"
    local bin_dir="$2"
    
    info "Creating directories..."
    
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        sudo mkdir -p "$install_dir" "$bin_dir"
        sudo mkdir -p "$install_dir"/{scripts,lib,docs,config,tests}
    else
        mkdir -p "$install_dir" "$bin_dir"
        mkdir -p "$install_dir"/{scripts,lib,docs,config,tests}
    fi
    
    success "Directories created"
}

copy_files() {
    local install_dir="$1"
    
    info "Copying files..."
    
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        sudo cp -r "$SCRIPT_DIR"/scripts/* "$install_dir/scripts/" 2>/dev/null || true
        sudo cp -r "$SCRIPT_DIR"/lib/* "$install_dir/lib/" 2>/dev/null || true
        sudo cp -r "$SCRIPT_DIR"/docs/* "$install_dir/docs/" 2>/dev/null || true
        sudo cp -r "$SCRIPT_DIR"/templates "$install_dir/" 2>/dev/null || true
        sudo cp -r "$SCRIPT_DIR"/examples "$install_dir/" 2>/dev/null || true
        sudo cp "$SCRIPT_DIR"/*.md "$install_dir/" 2>/dev/null || true
    else
        cp -r "$SCRIPT_DIR"/scripts/* "$install_dir/scripts/" 2>/dev/null || true
        cp -r "$SCRIPT_DIR"/lib/* "$install_dir/lib/" 2>/dev/null || true
        cp -r "$SCRIPT_DIR"/docs/* "$install_dir/docs/" 2>/dev/null || true
        cp -r "$SCRIPT_DIR"/templates "$install_dir/" 2>/dev/null || true
        cp -r "$SCRIPT_DIR"/examples "$install_dir/" 2>/dev/null || true
        cp "$SCRIPT_DIR"/*.md "$install_dir/" 2>/dev/null || true
    fi
    
    success "Files copied"
}

create_symlinks() {
    local install_dir="$1"
    local bin_dir="$2"
    
    info "Creating symlinks..."
    
    # Find all executable scripts
    find "$install_dir/scripts" -name "*.sh" -type f | while read -r script; do
        local script_name=$(basename "$script" .sh)
        local link_name="$bin_dir/abs-$script_name"
        
        if [[ "$INSTALL_TYPE" == "system" ]]; then
            sudo ln -sf "$script" "$link_name"
        else
            ln -sf "$script" "$link_name"
        fi
    done
    
    # Create main command
    local main_cmd="$bin_dir/awesome-bash"
    
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        sudo ln -sf "$install_dir/scripts/awesome-bash-menu.sh" "$main_cmd" 2>/dev/null || true
    else
        ln -sf "$install_dir/scripts/awesome-bash-menu.sh" "$main_cmd" 2>/dev/null || true
    fi
    
    success "Symlinks created"
}

update_path() {
    local bin_dir="$1"
    
    if [[ "$INSTALL_TYPE" == "user" ]]; then
        local shell_rc=""
        
        if [[ -f "$HOME/.bashrc" ]]; then
            shell_rc="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            shell_rc="$HOME/.zshrc"
        fi
        
        if [[ -n "$shell_rc" ]]; then
            if ! grep -q "$bin_dir" "$shell_rc"; then
                echo "" >> "$shell_rc"
                echo "# Awesome Bash Scripts" >> "$shell_rc"
                echo "export PATH=\"\$PATH:$bin_dir\"" >> "$shell_rc"
                info "PATH updated in $shell_rc"
            else
                info "PATH already includes $bin_dir"
            fi
        fi
    fi
}

install_completion() {
    local install_dir="$1"
    
    info "Setting up command completion..."
    
    # Bash completion
    local bash_completion_dir
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        bash_completion_dir="/etc/bash_completion.d"
    else
        bash_completion_dir="$HOME/.local/share/bash-completion/completions"
        mkdir -p "$bash_completion_dir"
    fi
    
    if [[ -f "$SCRIPT_DIR/completions/abs-completion.bash" ]]; then
        if [[ "$INSTALL_TYPE" == "system" ]]; then
            sudo cp "$SCRIPT_DIR/completions/abs-completion.bash" "$bash_completion_dir/abs"
        else
            cp "$SCRIPT_DIR/completions/abs-completion.bash" "$bash_completion_dir/abs"
        fi
        info "Bash completion installed to $bash_completion_dir"
    fi
    
    # Zsh completion
    local zsh_completion_dir
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        zsh_completion_dir="/usr/local/share/zsh/site-functions"
    else
        zsh_completion_dir="$HOME/.local/share/zsh/site-functions"
        mkdir -p "$zsh_completion_dir"
    fi
    
    if [[ -f "$SCRIPT_DIR/completions/_abs" ]]; then
        if [[ "$INSTALL_TYPE" == "system" ]]; then
            sudo cp "$SCRIPT_DIR/completions/_abs" "$zsh_completion_dir/_abs"
        else
            cp "$SCRIPT_DIR/completions/_abs" "$zsh_completion_dir/_abs"
        fi
        info "Zsh completion installed to $zsh_completion_dir"
    fi
    
    # Add to shell rc if user install
    if [[ "$INSTALL_TYPE" == "user" ]]; then
        # Bash
        if [[ -f "$HOME/.bashrc" ]]; then
            if ! grep -q "abs-completion.bash" "$HOME/.bashrc"; then
                echo "" >> "$HOME/.bashrc"
                echo "# Awesome Bash Scripts completion" >> "$HOME/.bashrc"
                echo "[[ -f $bash_completion_dir/abs ]] && source $bash_completion_dir/abs" >> "$HOME/.bashrc"
            fi
        fi
        
        # Zsh
        if [[ -f "$HOME/.zshrc" ]]; then
            if ! grep -q "zsh/site-functions" "$HOME/.zshrc"; then
                echo "" >> "$HOME/.zshrc"
                echo "# Awesome Bash Scripts completion" >> "$HOME/.zshrc"
                echo "fpath=($zsh_completion_dir \$fpath)" >> "$HOME/.zshrc"
            fi
        fi
    fi
    
    success "Completion setup done"
}

################################################################################
# Uninstall Function
################################################################################

uninstall() {
    warning "Uninstalling Awesome Bash Scripts..."
    
    # Determine installation directory
    if [[ -d "$SYSTEM_INSTALL_DIR" ]]; then
        INSTALL_DIR="$SYSTEM_INSTALL_DIR"
        BIN_DIR="$SYSTEM_BIN_DIR"
        INSTALL_TYPE="system"
    elif [[ -d "$USER_INSTALL_DIR" ]]; then
        INSTALL_DIR="$USER_INSTALL_DIR"
        BIN_DIR="$USER_BIN_DIR"
        INSTALL_TYPE="user"
    else
        error_exit "No installation found" 1
    fi
    
    # Remove symlinks
    info "Removing symlinks..."
    find "$BIN_DIR" -name "abs-*" -type l -delete 2>/dev/null || true
    rm -f "$BIN_DIR/awesome-bash" 2>/dev/null || true
    
    # Remove installation directory
    info "Removing installation directory..."
    if [[ "$INSTALL_TYPE" == "system" ]]; then
        sudo rm -rf "$INSTALL_DIR"
    else
        rm -rf "$INSTALL_DIR"
    fi
    
    # Clean PATH (user only)
    if [[ "$INSTALL_TYPE" == "user" ]]; then
        info "Note: You may want to remove the PATH export from your shell rc file"
    fi
    
    success "Awesome Bash Scripts uninstalled"
}

################################################################################
# Main Installation
################################################################################

main() {
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}     Awesome Bash Scripts Installer v1.0.0${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Set installation directory
    if [[ -z "$INSTALL_DIR" ]]; then
        if [[ "$INSTALL_TYPE" == "system" ]]; then
            INSTALL_DIR="$SYSTEM_INSTALL_DIR"
            BIN_DIR="$SYSTEM_BIN_DIR"
        else
            INSTALL_DIR="$USER_INSTALL_DIR"
            BIN_DIR="$USER_BIN_DIR"
        fi
    else
        BIN_DIR="$INSTALL_DIR/bin"
    fi
    
    info "Installation type: $INSTALL_TYPE"
    info "Installation directory: $INSTALL_DIR"
    info "Binary directory: $BIN_DIR"
    echo ""
    
    # Check sudo if needed
    check_sudo
    
    # Install dependencies
    if [[ "$INSTALL_DEPS" == true ]]; then
        install_dependencies
    else
        warning "Skipping dependency installation"
    fi
    
    echo ""
    
    # Create directories
    create_directories "$INSTALL_DIR" "$BIN_DIR"
    
    # Copy or link files
    if [[ "$LINK_ONLY" == true ]]; then
        info "Creating symlinks to source files..."
        INSTALL_DIR="$SCRIPT_DIR"
    else
        copy_files "$INSTALL_DIR"
    fi
    
    # Create symlinks
    create_symlinks "$INSTALL_DIR" "$BIN_DIR"
    
    # Update PATH
    update_path "$BIN_DIR"
    
    # Install completion
    install_completion "$INSTALL_DIR"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     Installation Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [[ "$INSTALL_TYPE" == "user" ]]; then
        info "To use the scripts, either:"
        echo "  1. Restart your shell"
        echo "  2. Run: source ~/.bashrc"
        echo ""
    fi
    
    success "All scripts are now available with the 'abs-' prefix"
    echo "  Example: abs-system-monitor"
    echo ""
    info "Run 'abs-system-info --help' to test the installation"
    echo ""
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
        -u|--user)
            INSTALL_TYPE="user"
            shift
            ;;
        -s|--system)
            INSTALL_TYPE="system"
            shift
            ;;
        -d|--dir)
            [[ -z "${2:-}" ]] && error_exit "--dir requires a directory path" 2
            INSTALL_DIR="$2"
            shift 2
            ;;
        -l|--link)
            LINK_ONLY=true
            shift
            ;;
        --no-deps)
            INSTALL_DEPS=false
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

################################################################################
# Main Execution
################################################################################

if [[ "$UNINSTALL" == true ]]; then
    uninstall
else
    main
fi
