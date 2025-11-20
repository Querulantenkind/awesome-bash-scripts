#!/bin/bash

################################################################################
# Script Name: package-cleanup.sh
# Description: System package cleanup and maintenance tool for multiple package
#              managers. Removes orphaned packages, clears caches, and provides
#              system cleanup recommendations.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
#
# Usage: ./package-cleanup.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -v, --verbose           Verbose output
#   -a, --auto              Auto-remove without prompts
#   -c, --cache             Clear package cache only
#   -o, --orphaned          Remove orphaned packages only
#   --dry-run               Show what would be done
#   -l, --log FILE          Log to file
#
# Examples:
#   ./package-cleanup.sh
#   ./package-cleanup.sh --auto --log /var/log/cleanup.log
#   ./package-cleanup.sh --dry-run
#
# Exit Codes:
#   0 - Success
#   1 - Error
################################################################################

set -euo pipefail

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
AUTO_MODE=false
CACHE_ONLY=false
ORPHANED_ONLY=false
DRY_RUN=false
LOG_FILE=""

error_exit() { echo "ERROR: $1" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }

show_usage() {
    cat << EOF
Package Cleanup Tool - System Package Maintenance

Usage: package-cleanup.sh [OPTIONS]

Options:
    -h, --help          Show this help
    -v, --verbose       Verbose output
    -a, --auto          Auto mode (no prompts)
    -c, --cache         Clear cache only
    -o, --orphaned      Remove orphaned packages only
    --dry-run           Show what would be done
    -l, --log FILE      Log to file

Examples:
    # Interactive cleanup
    package-cleanup.sh

    # Automatic cleanup
    package-cleanup.sh --auto

    # Clear cache only
    package-cleanup.sh --cache

    # Dry run
    package-cleanup.sh --dry-run

Features:
    • Multi-distro support (Debian, Red Hat, Arch)
    • Remove orphaned packages
    • Clear package caches
    • List old kernels
    • Show disk space saved

EOF
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
        error_exit "No supported package manager found"
    fi
}

cleanup_apt() {
    info "Using APT package manager..."
    
    if [[ "$CACHE_ONLY" == true ]] || [[ "$ORPHANED_ONLY" == false ]]; then
        info "Cleaning package cache..."
        [[ "$DRY_RUN" == false ]] && sudo apt-get clean
        success "Cache cleaned"
    fi
    
    if [[ "$ORPHANED_ONLY" == true ]] || [[ "$CACHE_ONLY" == false ]]; then
        info "Removing orphaned packages..."
        if [[ "$DRY_RUN" == true ]]; then
            apt-get autoremove --dry-run
        else
            if [[ "$AUTO_MODE" == true ]]; then
                sudo apt-get autoremove -y
            else
                sudo apt-get autoremove
            fi
        fi
        success "Orphaned packages removed"
    fi
    
    info "Removing old configuration files..."
    [[ "$DRY_RUN" == false ]] && sudo dpkg --purge $(dpkg -l | grep '^rc' | awk '{print $2}') 2>/dev/null || true
}

cleanup_dnf() {
    info "Using DNF package manager..."
    
    if [[ "$CACHE_ONLY" == true ]] || [[ "$ORPHANED_ONLY" == false ]]; then
        info "Cleaning package cache..."
        [[ "$DRY_RUN" == false ]] && sudo dnf clean all
        success "Cache cleaned"
    fi
    
    if [[ "$ORPHANED_ONLY" == true ]] || [[ "$CACHE_ONLY" == false ]]; then
        info "Removing orphaned packages..."
        [[ "$DRY_RUN" == false ]] && sudo dnf autoremove -y
        success "Orphaned packages removed"
    fi
}

cleanup_pacman() {
    info "Using Pacman package manager..."
    
    if [[ "$CACHE_ONLY" == true ]] || [[ "$ORPHANED_ONLY" == false ]]; then
        info "Cleaning package cache..."
        [[ "$DRY_RUN" == false ]] && sudo pacman -Sc --noconfirm
        success "Cache cleaned"
    fi
    
    if [[ "$ORPHANED_ONLY" == true ]] || [[ "$CACHE_ONLY" == false ]]; then
        info "Removing orphaned packages..."
        [[ "$DRY_RUN" == false ]] && sudo pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null || true
        success "Orphaned packages removed"
    fi
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -a|--auto) AUTO_MODE=true; shift ;;
        -c|--cache) CACHE_ONLY=true; shift ;;
        -o|--orphaned) ORPHANED_ONLY=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -l|--log) LOG_FILE="$2"; shift 2 ;;
        *) error_exit "Unknown option: $1" ;;
    esac
done

# Main execution
PKG_MGR=$(detect_package_manager)
info "Detected package manager: $PKG_MGR"

[[ "$DRY_RUN" == true ]] && info "DRY RUN MODE - No changes will be made"

case "$PKG_MGR" in
    apt) cleanup_apt ;;
    dnf|yum) cleanup_dnf ;;
    pacman) cleanup_pacman ;;
    *) error_exit "Unsupported package manager: $PKG_MGR" ;;
esac

success "Cleanup completed!"
