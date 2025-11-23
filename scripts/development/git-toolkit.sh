#!/bin/bash

################################################################################
# Script Name: git-toolkit.sh
# Description: Advanced git operations and statistics tool. Provides useful
#              git shortcuts, repository analysis, and workflow automation.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./git-toolkit.sh [command] [options]
#
# Commands:
#   stats              Repository statistics
#   cleanup            Cleanup branches and optimize repo
#   sync               Sync with remote and rebase
#   backup             Backup repository
#   search             Search commit history
#   undo               Undo last operations
#   interactive        Interactive mode
#
# Options:
#   -h, --help         Show help message
#   -v, --verbose      Verbose output
#   -d, --directory    Repository directory
#
# Examples:
#   ./git-toolkit.sh stats
#   ./git-toolkit.sh cleanup --dry-run
#   ./git-toolkit.sh search "bug fix"
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Not a git repository
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

REPO_DIR="."
COMMAND=""
DRY_RUN=false
VERBOSE=false

################################################################################
# Git Validation
################################################################################

# Check if we're in a git repository
is_git_repo() {
    git rev-parse --git-dir > /dev/null 2>&1
}

# Require git repository
require_git_repo() {
    if ! is_git_repo; then
        error_exit "Not a git repository" 3
    fi
}

################################################################################
# Repository Statistics
################################################################################

cmd_stats() {
    require_git_repo
    
    print_header "GIT REPOSITORY STATISTICS" 70
    
    # Basic info
    local repo_name=$(basename "$(git rev-parse --show-toplevel)")
    local branch=$(git branch --show-current)
    local remote=$(git remote get-url origin 2>/dev/null || echo "No remote")
    
    echo
    echo -e "${BOLD}Repository:${NC} $repo_name"
    echo -e "${BOLD}Current Branch:${NC} $branch"
    echo -e "${BOLD}Remote:${NC} $remote"
    echo
    
    # Commit statistics
    echo -e "${BOLD_CYAN}Commit Statistics:${NC}"
    local total_commits=$(git rev-list --all --count)
    local commits_this_week=$(git log --since="1 week ago" --oneline | wc -l)
    local commits_this_month=$(git log --since="1 month ago" --oneline | wc -l)
    local first_commit=$(git log --reverse --format="%ar" | head -n 1)
    local last_commit=$(git log -1 --format="%ar")
    
    echo "  Total commits: $total_commits"
    echo "  This week: $commits_this_week"
    echo "  This month: $commits_this_month"
    echo "  First commit: $first_commit"
    echo "  Last commit: $last_commit"
    echo
    
    # Contributors
    echo -e "${BOLD_CYAN}Top Contributors:${NC}"
    git log --format='%aN' | sort | uniq -c | sort -rn | head -n 5 | \
        awk '{printf "  %-4s commits by %s\n", $1, substr($0, index($0,$2))}'
    echo
    
    # File statistics
    echo -e "${BOLD_CYAN}File Statistics:${NC}"
    local total_files=$(git ls-files | wc -l)
    local tracked_size=$(git ls-files | xargs -I {} stat -c%s "{}" 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo 0)
    
    echo "  Tracked files: $total_files"
    echo "  Total size: $(human_readable_size $tracked_size)"
    echo
    
    # Branch information
    echo -e "${BOLD_CYAN}Branches:${NC}"
    local local_branches=$(git branch | wc -l)
    local remote_branches=$(git branch -r | wc -l)
    
    echo "  Local branches: $local_branches"
    echo "  Remote branches: $remote_branches"
    echo
    
    # Recent activity
    echo -e "${BOLD_CYAN}Recent Commits:${NC}"
    git log --oneline --graph --decorate -n 10 | sed 's/^/  /'
    echo
    
    # Language statistics
    if command_exists cloc; then
        echo -e "${BOLD_CYAN}Code Statistics:${NC}"
        cloc --quiet --csv . | tail -n +2 | \
            awk -F, '{printf "  %-15s %8s lines\n", $2, $5}' | head -n 5
    fi
}

################################################################################
# Cleanup Operations
################################################################################

cmd_cleanup() {
    require_git_repo
    
    print_header "GIT CLEANUP" 70
    echo
    
    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY RUN MODE - No changes will be made"
        echo
    fi
    
    # Clean merged branches
    echo -e "${BOLD}Cleaning merged branches...${NC}"
    local merged_branches=$(git branch --merged | grep -v "\*" | grep -v "main\|master\|develop" || echo "")
    
    if [[ -n "$merged_branches" ]]; then
        echo "$merged_branches" | while read branch; do
            if [[ "$DRY_RUN" == true ]]; then
                echo "  Would delete: $branch"
            else
                if ask_yes_no "Delete branch $branch?"; then
                    git branch -d "$branch"
                    success "Deleted $branch"
                fi
            fi
        done
    else
        info "No merged branches to clean"
    fi
    echo
    
    # Clean untracked files
    echo -e "${BOLD}Untracked files:${NC}"
    local untracked=$(git ls-files --others --exclude-standard)
    
    if [[ -n "$untracked" ]]; then
        echo "$untracked" | head -n 20 | sed 's/^/  /'
        [[ $(echo "$untracked" | wc -l) -gt 20 ]] && echo "  ..."
        echo
        
        if [[ "$DRY_RUN" != true ]] && ask_yes_no "Remove untracked files?"; then
            git clean -fd
            success "Cleaned untracked files"
        fi
    else
        info "No untracked files"
    fi
    echo
    
    # Optimize repository
    echo -e "${BOLD}Optimizing repository...${NC}"
    if [[ "$DRY_RUN" != true ]]; then
        git gc --aggressive --prune=now
        success "Repository optimized"
    else
        echo "  Would run: git gc --aggressive --prune=now"
    fi
}

################################################################################
# Sync Operations
################################################################################

cmd_sync() {
    require_git_repo
    
    print_header "GIT SYNC" 70
    echo
    
    local branch=$(git branch --show-current)
    
    # Fetch from remote
    info "Fetching from remote..."
    git fetch --all --prune
    success "Fetched from remote"
    echo
    
    # Check for local changes
    if ! git diff-index --quiet HEAD --; then
        warning "You have uncommitted changes"
        
        if ask_yes_no "Stash changes before syncing?"; then
            git stash push -m "Auto-stash before sync $(date +%Y%m%d_%H%M%S)"
            success "Changes stashed"
        else
            error_exit "Cannot sync with uncommitted changes" 1
        fi
    fi
    
    # Sync with remote
    info "Syncing with origin/$branch..."
    
    if git rebase "origin/$branch"; then
        success "Successfully synced with remote"
    else
        error "Rebase failed. Aborting rebase..."
        git rebase --abort
        error_exit "Sync failed" 1
    fi
    
    # Pop stash if we stashed
    if git stash list | grep -q "Auto-stash before sync"; then
        info "Applying stashed changes..."
        if git stash pop; then
            success "Stashed changes applied"
        else
            warning "Could not apply stashed changes automatically"
        fi
    fi
}

################################################################################
# Backup Operations
################################################################################

cmd_backup() {
    require_git_repo
    
    local repo_name=$(basename "$(git rev-parse --show-toplevel)")
    local backup_dir="${HOME}/git-backups"
    local backup_file="$backup_dir/${repo_name}-$(date +%Y%m%d_%H%M%S).bundle"
    
    mkdir -p "$backup_dir"
    
    print_header "GIT BACKUP" 70
    echo
    
    info "Creating backup of $repo_name..."
    info "Backup location: $backup_file"
    echo
    
    # Create bundle
    git bundle create "$backup_file" --all
    
    local size=$(stat -c%s "$backup_file")
    echo
    success "Backup created: $(human_readable_size $size)"
    echo "  Location: $backup_file"
    
    # List recent backups
    echo
    echo -e "${BOLD}Recent backups:${NC}"
    ls -lht "$backup_dir"/*.bundle 2>/dev/null | head -n 5 | \
        awk '{printf "  %s %s  %s\n", $6, $7, $9}' || echo "  (none)"
}

################################################################################
# Search Operations
################################################################################

cmd_search() {
    require_git_repo
    
    local query="${1:-}"
    
    if [[ -z "$query" ]]; then
        read -p "Enter search term: " query
    fi
    
    print_header "GIT SEARCH: \"$query\"" 70
    echo
    
    # Search in commit messages
    echo -e "${BOLD_CYAN}Commits:${NC}"
    git log --all --oneline --grep="$query" -i --color | head -n 20 | sed 's/^/  /'
    echo
    
    # Search in file content
    echo -e "${BOLD_CYAN}File Content:${NC}"
    git log -S "$query" --oneline --color | head -n 10 | sed 's/^/  /'
    echo
    
    # Search in current files
    echo -e "${BOLD_CYAN}Current Files:${NC}"
    git grep -n "$query" -- 2>/dev/null | head -n 20 | sed 's/^/  /' || echo "  (no matches)"
}

################################################################################
# Undo Operations
################################################################################

cmd_undo() {
    require_git_repo
    
    print_header "GIT UNDO" 70
    echo
    
    cat << EOF
${BOLD}Select undo operation:${NC}

  1) Undo last commit (keep changes)
  2) Undo last commit (discard changes)
  3) Undo last N commits
  4) Undo all uncommitted changes
  5) Restore deleted file
  6) Show reflog
  0) Cancel

EOF
    
    read -p "Enter choice: " choice
    
    case "$choice" in
        1)
            git reset --soft HEAD~1
            success "Last commit undone (changes kept)"
            ;;
        2)
            if ask_yes_no "This will DISCARD all changes. Continue?"; then
                git reset --hard HEAD~1
                success "Last commit undone (changes discarded)"
            fi
            ;;
        3)
            read -p "Number of commits to undo: " count
            if ask_yes_no "Undo last $count commits?"; then
                git reset --soft HEAD~"$count"
                success "Last $count commits undone"
            fi
            ;;
        4)
            if ask_yes_no "This will DISCARD all uncommitted changes. Continue?"; then
                git reset --hard HEAD
                git clean -fd
                success "All uncommitted changes discarded"
            fi
            ;;
        5)
            read -p "Enter file path: " filepath
            git checkout HEAD -- "$filepath"
            success "File restored: $filepath"
            ;;
        6)
            git reflog --color | head -n 20
            ;;
        0)
            info "Cancelled"
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
}

################################################################################
# Interactive Mode
################################################################################

cmd_interactive() {
    require_git_repo
    
    while true; do
        clear
        print_header "GIT TOOLKIT - INTERACTIVE MODE" 70
        
        local repo_name=$(basename "$(git rev-parse --show-toplevel)")
        local branch=$(git branch --show-current)
        local status=$(git status --short | wc -l)
        
        echo
        echo -e "${BOLD}Repository:${NC} $repo_name"
        echo -e "${BOLD}Branch:${NC} $branch"
        echo -e "${BOLD}Modified files:${NC} $status"
        echo
        
        cat << EOF
${BOLD}Select operation:${NC}

  ${CYAN}1)${NC} Repository statistics
  ${CYAN}2)${NC} Cleanup repository
  ${CYAN}3)${NC} Sync with remote
  ${CYAN}4)${NC} Backup repository
  ${CYAN}5)${NC} Search history
  ${CYAN}6)${NC} Undo operations
  ${CYAN}7)${NC} View status
  ${CYAN}8)${NC} View log
  ${CYAN}0)${NC} Exit

EOF
        
        read -p "Enter choice: " choice
        
        case "$choice" in
            1) cmd_stats; read -p "Press Enter to continue..." ;;
            2) cmd_cleanup; read -p "Press Enter to continue..." ;;
            3) cmd_sync; read -p "Press Enter to continue..." ;;
            4) cmd_backup; read -p "Press Enter to continue..." ;;
            5) cmd_search; read -p "Press Enter to continue..." ;;
            6) cmd_undo; read -p "Press Enter to continue..." ;;
            7) clear; git status; read -p "Press Enter to continue..." ;;
            8) clear; git log --oneline --graph --decorate -n 20; read -p "Press Enter to continue..." ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) error "Invalid choice"; sleep 1 ;;
        esac
    done
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Git Toolkit - Advanced Git Operations${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [COMMAND] [OPTIONS]

${CYAN}Commands:${NC}
    stats              Show repository statistics
    cleanup            Cleanup branches and optimize repo
    sync               Sync with remote and rebase
    backup             Create repository backup
    search TERM        Search commit history
    undo               Undo operations menu
    interactive        Interactive mode (default)

${CYAN}Options:${NC}
    -h, --help         Show this help message
    -v, --verbose      Verbose output
    -d, --directory    Repository directory
    --dry-run          Dry run (for cleanup)

${CYAN}Examples:${NC}
    # Show statistics
    $(basename "$0") stats
    
    # Cleanup repository
    $(basename "$0") cleanup --dry-run
    
    # Sync with remote
    $(basename "$0") sync
    
    # Search commits
    $(basename "$0") search "bug fix"
    
    # Interactive mode
    $(basename "$0") interactive

${CYAN}Features:${NC}
    - Repository statistics and analysis
    - Automatic branch cleanup
    - Safe sync with remote
    - Repository backups
    - Commit history search
    - Easy undo operations

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
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--directory)
            [[ -z "${2:-}" ]] && error_exit "Directory required" 2
            REPO_DIR="$2"
            cd "$REPO_DIR"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        stats|cleanup|sync|backup|search|undo|interactive)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Change to repository directory
cd "$REPO_DIR"

# Execute command
case "$COMMAND" in
    stats)
        cmd_stats
        ;;
    cleanup)
        cmd_cleanup
        ;;
    sync)
        cmd_sync
        ;;
    backup)
        cmd_backup
        ;;
    search)
        cmd_search "$@"
        ;;
    undo)
        cmd_undo
        ;;
    interactive|"")
        cmd_interactive
        ;;
    *)
        error_exit "Unknown command: $COMMAND" 2
        ;;
esac
