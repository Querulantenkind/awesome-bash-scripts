#!/bin/bash

################################################################################
# Script Name: bump-version.sh
# Description: Automates version bumping across the entire Awesome Bash Scripts
#              repository. Updates version strings and modified dates.
# Author: Luca
# Created: 2024-11-23
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./bump-version.sh [options] <new-version>
#
# Options:
#   -h, --help          Show help message
#   -v, --verbose       Enable verbose output
#   --dry-run           Show what would be changed without modifying files
#
# Examples:
#   ./bump-version.sh 1.1.0
#   ./bump-version.sh --dry-run 1.0.1
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
DRY_RUN=false
NEW_VERSION=""

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

info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}" >&2
    fi
}

show_usage() {
    cat << EOF
${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS] <NEW_VERSION>

${CYAN}Options:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    --dry-run           Show what would be changed without modifying files

${CYAN}Examples:${NC}
    $SCRIPT_NAME 1.1.0
    $SCRIPT_NAME --dry-run 2.0.0
EOF
}

################################################################################
# Main Logic
################################################################################

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error_exit "Invalid version format: $version. Must be X.Y.Z (e.g., 1.0.0)" 2
    fi
}

update_file() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"
    local description="$4"

    if [[ ! -f "$file" ]]; then
        verbose "File not found (skipping): $file"
        return
    fi

    verbose "Checking $file for pattern: $pattern"

    if grep -qE "$pattern" "$file"; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${YELLOW}[DRY RUN]${NC} Would update $description in ${file#$PROJECT_ROOT/}"
            grep -E "$pattern" "$file" | head -1 | sed "s/^/  Current: /"
        else
            sed -i -E "s/$pattern/$replacement/g" "$file"
            verbose "Updated $description in ${file#$PROJECT_ROOT/}"
        fi
    else
        verbose "Pattern not found in $file"
    fi
}

perform_update() {
    local version="$1"
    local today=$(date +%Y-%m-%d)
    
    info "Bumping version to $version..."
    
    # 1. Update awesome-bash.sh
    # Updates `readonly VERSION="X.Y.Z"`
    update_file "$PROJECT_ROOT/awesome-bash.sh" \
        'readonly VERSION="[0-9]+\.[0-9]+\.[0-9]+"' \
        "readonly VERSION=\"$version\"" \
        "main version constant"
    
    # Updates Header Version
    update_file "$PROJECT_ROOT/awesome-bash.sh" \
        '^# Version: [0-9]+\.[0-9]+\.[0-9]+' \
        "# Version: $version" \
        "header version"

    # Updates Header Modified Date
    update_file "$PROJECT_ROOT/awesome-bash.sh" \
        '^# Modified: [0-9]{4}-[0-9]{2}-[0-9]{2}' \
        "# Modified: $today" \
        "header modified date"

    # 2. Update install.sh
    update_file "$PROJECT_ROOT/install.sh" \
        '^# Version: [0-9]+\.[0-9]+\.[0-9]+' \
        "# Version: $version" \
        "header version"
        
    update_file "$PROJECT_ROOT/install.sh" \
        '^# Modified: [0-9]{4}-[0-9]{2}-[0-9]{2}' \
        "# Modified: $today" \
        "header modified date"

    update_file "$PROJECT_ROOT/install.sh" \
        'Awesome Bash Scripts Installer v[0-9]+\.[0-9]+\.[0-9]+' \
        "Awesome Bash Scripts Installer v$version" \
        "installer banner version"

    # 3. Update PROJECT-OVERVIEW.md
    update_file "$PROJECT_ROOT/PROJECT-OVERVIEW.md" \
        '\*\*Version\*\*: [0-9]+\.[0-9]+\.[0-9]+' \
        "**Version**: $version" \
        "overview version"
    
    update_file "$PROJECT_ROOT/PROJECT-OVERVIEW.md" \
        '\*\*Last Updated\*\*: [A-Za-z]+ [0-9]+, [0-9]{4}' \
        "**Last Updated**: $(date +'%B %d, %Y')" \
        "overview date"

    # 4. Update completions/abs-completion.bash
    update_file "$PROJECT_ROOT/completions/abs-completion.bash" \
        '^# Version: [0-9]+\.[0-9]+\.[0-9]+' \
        "# Version: $version" \
        "completion version"

    # 5. Update all scripts in scripts/ and lib/ directories
    info "Updating script headers..."
    
    while IFS= read -r script_file; do
        # Update Version header
        update_file "$script_file" \
            '^# Version: [0-9]+\.[0-9]+\.[0-9]+' \
            "# Version: $version" \
            "header version"
            
        # Update Modified header
        update_file "$script_file" \
            '^# Modified: [0-9]{4}-[0-9]{2}-[0-9]{2}' \
            "# Modified: $today" \
            "header modified date"
    done < <(find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/lib" -name "*.sh" -type f)
    
    if [[ "$DRY_RUN" == false ]]; then
        success "Version bumped to $version successfully!"
    else
        success "Dry run completed. No files were modified."
    fi
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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [[ -z "$NEW_VERSION" ]]; then
                NEW_VERSION="$1"
                shift
            else
                error_exit "Unknown argument: $1" 2
            fi
            ;;
    esac
done

if [[ -z "$NEW_VERSION" ]]; then
    error_exit "Version argument required" 2
fi

validate_version "$NEW_VERSION"
perform_update "$NEW_VERSION"

