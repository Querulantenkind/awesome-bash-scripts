#!/bin/bash

################################################################################
# Script Name: cloud-backup.sh
# Description: Cloud-ready backup orchestrator with rclone integration, optional
#              encryption, retention policies, verification, and profile support.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./cloud-backup.sh [options]
#
# Options:
#   -h, --help                 Show help message
#   -s, --source PATH          Source directory/file to back up
#   -d, --destination PATH     Local destination directory (cache/staging)
#   -r, --remote NAME:PATH     rclone remote (e.g., b2:bucket/backups)
#   -n, --name NAME            Custom backup name/prefix
#   -p, --profile NAME         Load profile from config/profiles/cloud-backup
#   --retention DAYS           Retention period (default: 30 days)
#   --compression TYPE         tar.gz, tar.xz, tar.zst, none (default: tar.gz)
#   --encrypt MODE             none, gpg, age (default: none)
#   --key VALUE                Passphrase/recipient (depending on mode)
#   --key-file PATH            File containing encryption key/identity
#   --include PATTERN          Include glob (repeatable)
#   --exclude PATTERN          Exclude glob (repeatable)
#   --notes TEXT               Attach notes to backup metadata
#   --bandwidth KBPS           Limit rclone bandwidth
#   --verify                   Verify checksum after upload
#   --list                     List available backups
#   --restore FILE             Restore archive (local or remote)
#   --target PATH              Restore target directory
#   --dry-run                  Show plan without creating backup
#   --json                     Print JSON summary
#   -v, --verbose              Verbose logging
#
# Examples:
#   ./cloud-backup.sh -s /srv/data -r b2:awesome/backups --encrypt gpg --key-file ~/.keys/backup
#   ./cloud-backup.sh -p production --verify
#   ./cloud-backup.sh --list -r onedrive:abs
#   ./cloud-backup.sh --restore data-20241120.tar.gz --target /restore
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument/missing data
#   3 - Dependency missing
#   4 - Backup/restore failed
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"
source "${SCRIPT_DIR}/../../lib/config.sh"
source "${SCRIPT_DIR}/../../lib/notifications.sh"

PROFILE=""
SOURCE_PATH=""
LOCAL_DEST="$(config_get ABS_BACKUP_DIR "$HOME/backups")"
RCLONE_REMOTE=""
CUSTOM_NAME=""
RETENTION_DAYS="$(config_get ABS_BACKUP_RETENTION_DAYS 30)"
COMPRESSION="tar.gz"
ENCRYPTION_MODE="none"
ENCRYPTION_KEY=""
ENCRYPTION_KEY_FILE=""
VERIFY_BACKUP=false
LIST_ONLY=false
RESTORE_FILE=""
RESTORE_TARGET="$PWD"
DRY_RUN=false
OUTPUT_JSON=false
VERBOSE=false
BANDWIDTH_LIMIT=""
NOTES=""

declare -a INCLUDE_PATTERNS=()
declare -a EXCLUDE_PATTERNS=()

BACKUP_METADATA_DIR="${ABS_LOG_DIR}/cloud-backups"
mkdir -p "$BACKUP_METADATA_DIR"
PROFILE_DIR="${ABS_CONFIG_DIR}/profiles/cloud-backup"
mkdir -p "$PROFILE_DIR"

load_notification_config "${ABS_CONFIG_DIR}/notifications.conf"

usage() {
    sed -n '1,120p' "$0"
}

require_dependencies() {
    require_command tar
    require_command sha256sum coreutils
    require_command rclone

    case "$COMPRESSION" in
        tar.gz) require_command gzip ;;
        tar.xz) require_command xz ;;
        tar.zst) require_command zstd ;;
        none) ;;
        *) error_exit "Unsupported compression: $COMPRESSION" 2 ;;
    esac

    case "$ENCRYPTION_MODE" in
        gpg) require_command gpg gpg ;;
        age) require_command age ;;
        none) ;;
        *) error_exit "Unsupported encryption mode: $ENCRYPTION_MODE" 2 ;;
    esac
}

load_profile() {
    local profile="$1"
    local profile_file="${PROFILE_DIR}/${profile}.conf"

    [[ -f "$profile_file" ]] || error_exit "Profile not found: $profile_file" 2

    log_info "Loading profile: $profile"
    # shellcheck disable=SC1090
    source "$profile_file"
}

timestamp() { date +%Y%m%d-%H%M%S; }

format_size() { human_readable_size "$1"; }

print_dry_run_plan() {
    print_header "CLOUD BACKUP DRY RUN" 70
    echo "Source:        $SOURCE_PATH"
    echo "Destination:   ${LOCAL_DEST:-N/A}"
    echo "Remote:        ${RCLONE_REMOTE:-N/A}"
    echo "Name Prefix:   ${CUSTOM_NAME:-$(basename "$SOURCE_PATH")}"
    echo "Compression:   $COMPRESSION"
    echo "Encryption:    $ENCRYPTION_MODE"
    echo "Retention:     ${RETENTION_DAYS} days"
    echo "Verify:        $VERIFY_BACKUP"
    echo "Bandwidth:     ${BANDWIDTH_LIMIT:-unlimited}"
    [[ -n "$NOTES" ]] && echo "Notes:        $NOTES"

    if [[ ${#INCLUDE_PATTERNS[@]} -gt 0 ]]; then
        echo "Includes:"
        for inc in "${INCLUDE_PATTERNS[@]}"; do
            echo "  • $inc"
        done
    fi
    if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
        echo "Excludes:"
        for exc in "${EXCLUDE_PATTERNS[@]}"; do
            echo "  • $exc"
        done
    fi

    echo
    print_info "Dry run only. No backup created."
}

build_archive() {
    local src="$1"
    local dest_dir="$2"
    local base_name="$3"
    local archive_path="${dest_dir}/${base_name}.tar"
    local -a tar_args=(-cpf "$archive_path")

    if [[ ${#INCLUDE_PATTERNS[@]} -gt 0 ]]; then
        tar_args+=("--wildcards" "--no-wildcards-match-slash")
        for include in "${INCLUDE_PATTERNS[@]}"; do
            tar_args+=("--include=$include")
        done
    fi
    for exclude in "${EXCLUDE_PATTERNS[@]}"; do
        tar_args+=("--exclude=$exclude")
    done

    log_info "Creating archive: $archive_path"
    pushd "$src" > /dev/null
    tar "${tar_args[@]}" .
    popd > /dev/null

    case "$COMPRESSION" in
        tar.gz)
            log_info "Compressing with gzip"
            gzip -f "$archive_path"
            archive_path="${archive_path}.gz"
            ;;
        tar.xz)
            log_info "Compressing with xz"
            xz -f "$archive_path"
            archive_path="${archive_path}.xz"
            ;;
        tar.zst)
            log_info "Compressing with zstd"
            zstd -f "$archive_path"
            archive_path="${archive_path}.zst"
            ;;
        none) ;;
    esac

    echo "$archive_path"
}

encrypt_archive() {
    local archive="$1"
    local mode="$2"
    local key="$3"
    local key_file="$4"

    [[ "$mode" == "none" ]] && { echo "$archive"; return; }

    local passphrase="$key"
    [[ -z "$passphrase" && -n "$key_file" ]] && passphrase=$(<"$key_file")
    [[ -z "$passphrase" ]] && error_exit "Encryption key required" 2

    local output="${archive}.${mode}"

    case "$mode" in
        gpg)
            log_info "Encrypting archive with GPG"
            printf '%s' "$passphrase" | gpg --batch --yes --passphrase-fd 0                 --symmetric --cipher-algo AES256 -o "$output" "$archive"
            ;;
        age)
            log_info "Encrypting archive with age"
            age -r "$passphrase" -o "$output" "$archive"
            ;;
    esac

    rm -f "$archive"
    echo "$output"
}

decrypt_archive() {
    local archive="$1"
    local mode="$2"
    local key="$3"
    local key_file="$4"

    [[ "$mode" == "none" ]] && { echo "$archive"; return; }

    local output="${archive%.${mode}}"

    case "$mode" in
        gpg)
            local passphrase="$key"
            [[ -z "$passphrase" && -n "$key_file" ]] && passphrase=$(<"$key_file")
            [[ -z "$passphrase" ]] && error_exit "Decryption key required" 2
            printf '%s' "$passphrase" | gpg --batch --yes --passphrase-fd 0                 -o "$output" "$archive"
            ;;
        age)
            [[ -n "$key_file" ]] || error_exit "Age identity file required (--key-file)" 2
            age --decrypt -i "$key_file" -o "$output" "$archive"
            ;;
        *) error_exit "Unsupported encryption mode: $mode" 2 ;;
    esac

    echo "$output"
}

calculate_checksum() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

metadata_file() { echo "${BACKUP_METADATA_DIR}/$1.json"; }

write_metadata() {
    local name="$1"
    local size="$2"
    local checksum="$3"
    local archive="$4"

    cat > "$(metadata_file "$name")" <<EOF
{
  "name": "$name",
  "source": "$SOURCE_PATH",
  "local_destination": "${LOCAL_DEST:-}",
  "remote": "${RCLONE_REMOTE:-}",
  "compression": "$COMPRESSION",
  "encryption": "$ENCRYPTION_MODE",
  "size_bytes": $size,
  "size_human": "$(format_size "$size")",
  "checksum": "$checksum",
  "notes": "${NOTES:-}",
  "created_at": "$(date -Iseconds)",
  "archive": "$(basename "$archive")"
}
EOF
}

upload_backup() {
    local archive="$1"
    local destination="$2"
    local remote="$3"

    if [[ -n "$destination" ]]; then
        mkdir -p "$destination"
        log_info "Copying archive to $destination"
        cp "$archive" "$destination/"
    fi

    if [[ -n "$remote" ]]; then
        log_info "Uploading archive to remote: $remote"
        local -a cmd=(rclone copy "$archive" "$remote")
        [[ -n "$BANDWIDTH_LIMIT" ]] && cmd+=(--bwlimit "${BANDWIDTH_LIMIT}k")
        [[ "$VERBOSE" == true ]] && cmd+=(--progress)
        "${cmd[@]}"
    fi
}

rotate_backups() {
    local destination="$1"
    local remote="$2"

    [[ "$RETENTION_DAYS" -le 0 ]] && return

    if [[ -n "$destination" && -d "$destination" ]]; then
        log_info "Pruning local backups older than $RETENTION_DAYS days"
        find "$destination" -maxdepth 1 -type f -mtime +"$RETENTION_DAYS"             -name "${CUSTOM_NAME:-*}*" -print -delete || true
    fi

    if [[ -n "$remote" ]]; then
        log_info "Pruning remote backups older than $RETENTION_DAYS days"
        local -a prune_cmd=(rclone delete "$remote" --min-age "${RETENTION_DAYS}d")
        [[ "$VERBOSE" == true ]] && prune_cmd+=(--progress)
        "${prune_cmd[@]}"
    fi
}

list_backups() {
    print_header "CLOUD BACKUP INVENTORY" 70
    printf "%-40s %-12s %-10s %-20s
" "NAME" "SIZE" "LOCATION" "CREATED"
    print_separator

    if [[ -n "$LOCAL_DEST" && -d "$LOCAL_DEST" ]]; then
        find "$LOCAL_DEST" -maxdepth 1 -type f -printf "%f %s %TY-%Tm-%Td %TH:%TM
" |         while read -r name size date time; do
            printf "%-40s %-12s %-10s %-20s
" "$name" "$(format_size "$size")" "local" "$date $time"
        done
    fi

    if [[ -n "$RCLONE_REMOTE" ]]; then
        rclone lsl "$RCLONE_REMOTE" 2>/dev/null | while read -r size date time path; do
            [[ -z "$path" ]] && continue
            printf "%-40s %-12s %-10s %-20s
" "$path" "$(format_size "$size")" "remote" "$date $time"
        done
    fi
}

restore_backup() {
    local file="$1"
    local target="$2"

    [[ -n "$target" ]] || error_exit "Restore target required" 2
    mkdir -p "$target"

    local temp_dir
    temp_dir=$(mktemp -d)
    local archive_path="$temp_dir/$file"

    if [[ -n "$RCLONE_REMOTE" ]]; then
        log_info "Downloading $file from remote"
        rclone copyto "$RCLONE_REMOTE/$file" "$archive_path"
    elif [[ -n "$LOCAL_DEST" && -f "$LOCAL_DEST/$file" ]]; then
        log_info "Copying $file from local destination"
        cp "$LOCAL_DEST/$file" "$archive_path"
    else
        rm -rf "$temp_dir"
        error_exit "Backup not found locally or remote" 4
    fi

    archive_path=$(decrypt_archive "$archive_path" "$ENCRYPTION_MODE" "$ENCRYPTION_KEY" "$ENCRYPTION_KEY_FILE")

    log_info "Extracting archive to $target"
    tar -xf "$archive_path" -C "$target"

    rm -rf "$temp_dir"
    print_success "Restore complete"
}

verify_backup() {
    local file="$1"
    local checksum="$2"
    local calculated
    calculated=$(calculate_checksum "$file")

    if [[ "$calculated" == "$checksum" ]]; then
        print_success "Checksum verification passed"
    else
        error_exit "Checksum mismatch" 4
    fi
}

print_summary_json() {
    local name="$1"
    local size="$2"
    local checksum="$3"
    local duration="$4"

    cat <<EOF
{
  "name": "$name",
  "size_bytes": $size,
  "size_human": "$(format_size "$size")",
  "checksum": "$checksum",
  "duration_seconds": $duration,
  "source": "$SOURCE_PATH",
  "destination": "${LOCAL_DEST:-}",
  "remote": "${RCLONE_REMOTE:-}",
  "compression": "$COMPRESSION",
  "encryption": "$ENCRYPTION_MODE",
  "notes": "${NOTES:-}"
}
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -s|--source) SOURCE_PATH="$2"; shift 2 ;;
            -d|--destination) LOCAL_DEST="$2"; shift 2 ;;
            -r|--remote) RCLONE_REMOTE="$2"; shift 2 ;;
            -n|--name) CUSTOM_NAME="$2"; shift 2 ;;
            -p|--profile) PROFILE="$2"; shift 2 ;;
            --retention) RETENTION_DAYS="$2"; shift 2 ;;
            --compression) COMPRESSION="$2"; shift 2 ;;
            --encrypt) ENCRYPTION_MODE="$2"; shift 2 ;;
            --key) ENCRYPTION_KEY="$2"; shift 2 ;;
            --key-file) ENCRYPTION_KEY_FILE="$2"; shift 2 ;;
            --include) INCLUDE_PATTERNS+=("$2"); shift 2 ;;
            --exclude) EXCLUDE_PATTERNS+=("$2"); shift 2 ;;
            --notes) NOTES="$2"; shift 2 ;;
            --bandwidth) BANDWIDTH_LIMIT="$2"; shift 2 ;;
            --verify) VERIFY_BACKUP=true; shift ;;
            --list) LIST_ONLY=true; shift ;;
            --restore) RESTORE_FILE="$2"; shift 2 ;;
            --target) RESTORE_TARGET="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --json) OUTPUT_JSON=true; shift ;;
            -v|--verbose) VERBOSE=true; LOG_LEVEL=$LOG_DEBUG; shift ;;
            *) error_exit "Unknown option: $1" 2 ;;
        esac
    done
}

main() {
    parse_args "$@"

    [[ -n "$PROFILE" ]] && load_profile "$PROFILE"

    if [[ "$LIST_ONLY" == true ]]; then
        list_backups
        exit 0
    fi

    if [[ -n "$RESTORE_FILE" ]]; then
        restore_backup "$RESTORE_FILE" "$RESTORE_TARGET"
        exit 0
    fi

    [[ -n "$SOURCE_PATH" ]] || error_exit "Source path required (--source)" 2
    [[ -d "$SOURCE_PATH" ]] || error_exit "Source path not found: $SOURCE_PATH" 2
    [[ -n "$LOCAL_DEST" || -n "$RCLONE_REMOTE" ]] || error_exit "Destination or remote required" 2

    require_dependencies

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run_plan
        exit 0
    fi

    local temp_dir start_time end_time duration
    temp_dir=$(mktemp -d)
    start_time=$(date +%s)

    local base_name archive encrypted checksum size
    base_name="${CUSTOM_NAME:-$(basename "$SOURCE_PATH")}-$(timestamp)"
    archive=$(build_archive "$SOURCE_PATH" "$temp_dir" "$base_name")
    encrypted=$(encrypt_archive "$archive" "$ENCRYPTION_MODE" "$ENCRYPTION_KEY" "$ENCRYPTION_KEY_FILE")
    checksum=$(calculate_checksum "$encrypted")
    size=$(stat -c%s "$encrypted")

    upload_backup "$encrypted" "$LOCAL_DEST" "$RCLONE_REMOTE"
    rotate_backups "$LOCAL_DEST" "$RCLONE_REMOTE"

    [[ "$VERIFY_BACKUP" == true ]] && verify_backup "$encrypted" "$checksum"

    write_metadata "$base_name" "$size" "$checksum" "$encrypted"

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    if [[ "$OUTPUT_JSON" == true ]]; then
        print_summary_json "$base_name" "$size" "$checksum" "$duration"
    else
        print_header "BACKUP SUMMARY" 60
        echo "Name:        $base_name"
        echo "Source:      $SOURCE_PATH"
        echo "Local Dest:  ${LOCAL_DEST:-N/A}"
        echo "Remote:      ${RCLONE_REMOTE:-N/A}"
        echo "Compression: $COMPRESSION"
        echo "Encryption:  $ENCRYPTION_MODE"
        echo "Size:        $(format_size "$size")"
        echo "Checksum:    $checksum"
        echo "Notes:       ${NOTES:-None}"
        echo "Duration:    ${duration}s"
        echo
        print_success "Backup completed successfully"
    fi

    notify_success "Cloud backup finished" "Backup $base_name completed"
    rm -rf "$temp_dir"
}

main "$@"
