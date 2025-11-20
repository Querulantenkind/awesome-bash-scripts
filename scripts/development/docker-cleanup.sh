#!/bin/bash

################################################################################
# Script Name: docker-cleanup.sh
# Description: Docker system cleanup and optimization tool
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./docker-cleanup.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -a, --all               Remove all unused containers, images, and volumes
#   -c, --containers        Remove stopped containers
#   -i, --images            Remove unused images
#   -V, --volumes           Remove unused volumes
#   -n, --networks          Remove unused networks
#   --dangling              Remove dangling images only
#   --prune-system          Run docker system prune
#   --older-than DAYS       Remove images/containers older than N days
#   --dry-run               Show what would be removed
#   -f, --force             Force removal without confirmation
#   -j, --json              Output in JSON format
#   --no-color              Disable colored output
#
# Examples:
#   ./docker-cleanup.sh --all --dry-run
#   ./docker-cleanup.sh --containers --images
#   ./docker-cleanup.sh --older-than 30
#   ./docker-cleanup.sh --prune-system --force
#
# Dependencies:
#   - docker
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Docker not installed or not running
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
LOG_FILE=""
JSON_OUTPUT=false
DRY_RUN=false
FORCE=false
USE_COLOR=true

CLEANUP_ALL=false
CLEANUP_CONTAINERS=false
CLEANUP_IMAGES=false
CLEANUP_VOLUMES=false
CLEANUP_NETWORKS=false
CLEANUP_DANGLING=false
PRUNE_SYSTEM=false
OLDER_THAN_DAYS=0

# Statistics
CONTAINERS_REMOVED=0
IMAGES_REMOVED=0
VOLUMES_REMOVED=0
NETWORKS_REMOVED=0
SPACE_FREED=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit "${2:-1}"
}

success() {
    [[ "$USE_COLOR" == true ]] && echo -e "${GREEN}✓ $1${NC}" || echo "✓ $1"
}

warning() {
    [[ "$USE_COLOR" == true ]] && echo -e "${YELLOW}⚠ $1${NC}" || echo "⚠ $1"
}

info() {
    [[ "$USE_COLOR" == true ]] && echo -e "${CYAN}ℹ $1${NC}" || echo "ℹ $1"
}

verbose() {
    [[ "$VERBOSE" == true ]] && echo -e "[VERBOSE] $1" >&2
}

log_message() {
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

show_usage() {
    cat << EOF
${WHITE}Docker Cleanup - Docker System Cleanup and Optimization${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -a, --all               Remove all unused resources
    -c, --containers        Remove stopped containers
    -i, --images            Remove unused images
    -V, --volumes           Remove unused volumes
    -n, --networks          Remove unused networks
    --dangling              Remove dangling images only
    --prune-system          Run docker system prune
    --older-than DAYS       Remove resources older than N days
    --dry-run               Show what would be removed
    -f, --force             Force removal without confirmation
    -j, --json              Output in JSON format
    --no-color              Disable colored output

${CYAN}Examples:${NC}
    # Dry run to see what would be removed
    $SCRIPT_NAME --all --dry-run

    # Remove stopped containers and unused images
    $SCRIPT_NAME --containers --images

    # Remove resources older than 30 days
    $SCRIPT_NAME --older-than 30 --force

    # Complete system cleanup
    $SCRIPT_NAME --prune-system --force

    # Remove only dangling images
    $SCRIPT_NAME --dangling

EOF
}

check_dependencies() {
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed" 3
    fi

    if ! docker info &>/dev/null; then
        error_exit "Docker daemon is not running" 3
    fi
}

confirm_action() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Operation cancelled"
        exit 0
    fi
}

################################################################################
# Docker Cleanup Functions
################################################################################

get_disk_usage_before() {
    docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | tail -n +2
}

cleanup_containers() {
    info "Cleaning up stopped containers..."

    local containers
    if [[ $OLDER_THAN_DAYS -gt 0 ]]; then
        local cutoff_date=$(date -d "$OLDER_THAN_DAYS days ago" +%s 2>/dev/null || date -v -${OLDER_THAN_DAYS}d +%s)
        containers=$(docker ps -a --format "{{.ID}}|{{.CreatedAt}}" | while IFS='|' read -r id created; do
            local created_ts=$(date -d "$created" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$created" +%s 2>/dev/null || echo 0)
            [[ $created_ts -lt $cutoff_date ]] && echo "$id"
        done)
    else
        containers=$(docker ps -a -q -f status=exited -f status=created)
    fi

    if [[ -z "$containers" ]]; then
        info "No containers to remove"
        return 0
    fi

    local count=$(echo "$containers" | wc -l)

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove $count container(s)"
        echo "$containers" | while read -r id; do
            [[ -n "$id" ]] && echo "  - $(docker inspect --format='{{.Name}} ({{.State.Status}})' "$id" 2>/dev/null || echo "$id")"
        done
    else
        echo "$containers" | while read -r id; do
            [[ -n "$id" ]] && docker rm "$id" &>/dev/null && ((CONTAINERS_REMOVED++))
        done
        success "Removed $CONTAINERS_REMOVED container(s)"
    fi

    log_message "Cleaned up $CONTAINERS_REMOVED containers"
}

cleanup_images() {
    info "Cleaning up unused images..."

    local images
    if [[ "$CLEANUP_DANGLING" == true ]]; then
        images=$(docker images -q -f dangling=true)
    elif [[ $OLDER_THAN_DAYS -gt 0 ]]; then
        # Docker doesn't provide easy age filtering, so we'll use all unused
        images=$(docker images -q -f dangling=false | while read -r img; do
            docker inspect --format='{{.Created}}' "$img" | xargs date -d +%s 2>/dev/null | {
                read -r created_ts
                [[ $created_ts -lt $(date -d "$OLDER_THAN_DAYS days ago" +%s) ]] && echo "$img"
            }
        done 2>/dev/null)
    else
        images=$(docker images -q -f dangling=false)
    fi

    if [[ -z "$images" ]]; then
        info "No images to remove"
        return 0
    fi

    local count=$(echo "$images" | wc -l)

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove $count image(s)"
        echo "$images" | while read -r id; do
            [[ -n "$id" ]] && echo "  - $(docker inspect --format='{{.RepoTags}} {{.Size}}' "$id" 2>/dev/null || echo "$id")"
        done
    else
        echo "$images" | while read -r id; do
            [[ -n "$id" ]] && docker rmi -f "$id" &>/dev/null && ((IMAGES_REMOVED++))
        done
        success "Removed $IMAGES_REMOVED image(s)"
    fi

    log_message "Cleaned up $IMAGES_REMOVED images"
}

cleanup_volumes() {
    info "Cleaning up unused volumes..."

    local volumes=$(docker volume ls -q -f dangling=true)

    if [[ -z "$volumes" ]]; then
        info "No volumes to remove"
        return 0
    fi

    local count=$(echo "$volumes" | wc -l)

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove $count volume(s)"
        echo "$volumes" | while read -r vol; do
            [[ -n "$vol" ]] && echo "  - $vol"
        done
    else
        echo "$volumes" | while read -r vol; do
            [[ -n "$vol" ]] && docker volume rm "$vol" &>/dev/null && ((VOLUMES_REMOVED++))
        done
        success "Removed $VOLUMES_REMOVED volume(s)"
    fi

    log_message "Cleaned up $VOLUMES_REMOVED volumes"
}

cleanup_networks() {
    info "Cleaning up unused networks..."

    # Get networks not used by any containers (excluding default networks)
    local networks=$(docker network ls -q | while read -r net; do
        local name=$(docker network inspect --format='{{.Name}}' "$net")
        if [[ "$name" != "bridge" ]] && [[ "$name" != "host" ]] && [[ "$name" != "none" ]]; then
            local containers=$(docker network inspect --format='{{len .Containers}}' "$net")
            [[ "$containers" == "0" ]] && echo "$net"
        fi
    done)

    if [[ -z "$networks" ]]; then
        info "No networks to remove"
        return 0
    fi

    local count=$(echo "$networks" | wc -l)

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would remove $count network(s)"
        echo "$networks" | while read -r net; do
            [[ -n "$net" ]] && echo "  - $(docker network inspect --format='{{.Name}}' "$net" 2>/dev/null || echo "$net")"
        done
    else
        echo "$networks" | while read -r net; do
            [[ -n "$net" ]] && docker network rm "$net" &>/dev/null && ((NETWORKS_REMOVED++))
        done
        success "Removed $NETWORKS_REMOVED network(s)"
    fi

    log_message "Cleaned up $NETWORKS_REMOVED networks"
}

prune_system() {
    info "Running docker system prune..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would run: docker system prune -a -f"
        docker system df
    else
        confirm_action
        local output=$(docker system prune -a -f 2>&1)
        success "System prune completed"
        echo "$output" | grep -i "freed" && SPACE_FREED=$(echo "$output" | grep -oP '\d+\.\d+[KMGT]?B' | tail -1)
    fi

    log_message "Completed system prune"
}

show_statistics() {
    echo ""
    echo "=========================================="
    info "Cleanup Statistics"
    echo "=========================================="
    echo "Containers removed: $CONTAINERS_REMOVED"
    echo "Images removed:     $IMAGES_REMOVED"
    echo "Volumes removed:    $VOLUMES_REMOVED"
    echo "Networks removed:   $NETWORKS_REMOVED"
    [[ -n "$SPACE_FREED" ]] && echo "Space freed:        $SPACE_FREED"
    echo "=========================================="

    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "containers_removed": $CONTAINERS_REMOVED,
  "images_removed": $IMAGES_REMOVED,
  "volumes_removed": $VOLUMES_REMOVED,
  "networks_removed": $NETWORKS_REMOVED,
  "space_freed": "$SPACE_FREED",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi
}

################################################################################
# Main Function
################################################################################

main() {
    check_dependencies

    info "Docker Cleanup Tool"
    echo ""

    # Show current disk usage
    info "Current Docker disk usage:"
    docker system df
    echo ""

    # Determine what to clean
    if [[ "$CLEANUP_ALL" == true ]]; then
        CLEANUP_CONTAINERS=true
        CLEANUP_IMAGES=true
        CLEANUP_VOLUMES=true
        CLEANUP_NETWORKS=true
    fi

    # Confirm before proceeding
    if [[ "$CLEANUP_CONTAINERS" == true ]] || [[ "$CLEANUP_IMAGES" == true ]] || \
       [[ "$CLEANUP_VOLUMES" == true ]] || [[ "$CLEANUP_NETWORKS" == true ]] || \
       [[ "$PRUNE_SYSTEM" == true ]]; then
        confirm_action
    fi

    # Perform cleanup
    [[ "$CLEANUP_CONTAINERS" == true ]] && cleanup_containers
    [[ "$CLEANUP_IMAGES" == true ]] && cleanup_images
    [[ "$CLEANUP_VOLUMES" == true ]] && cleanup_volumes
    [[ "$CLEANUP_NETWORKS" == true ]] && cleanup_networks
    [[ "$PRUNE_SYSTEM" == true ]] && prune_system

    # Show results
    show_statistics

    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        info "Updated Docker disk usage:"
        docker system df
    fi

    success "Cleanup completed!"
}

################################################################################
# Argument Parsing
################################################################################

if [[ $# -eq 0 ]]; then
    show_usage
    exit 0
fi

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
        -a|--all)
            CLEANUP_ALL=true
            shift
            ;;
        -c|--containers)
            CLEANUP_CONTAINERS=true
            shift
            ;;
        -i|--images)
            CLEANUP_IMAGES=true
            shift
            ;;
        -V|--volumes)
            CLEANUP_VOLUMES=true
            shift
            ;;
        -n|--networks)
            CLEANUP_NETWORKS=true
            shift
            ;;
        --dangling)
            CLEANUP_DANGLING=true
            CLEANUP_IMAGES=true
            shift
            ;;
        --prune-system)
            PRUNE_SYSTEM=true
            shift
            ;;
        --older-than)
            OLDER_THAN_DAYS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
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

exit 0
