#!/bin/bash

################################################################################
# Script Name: cloud-backup.sh
# Description: Cloud backup solution supporting S3, B2, Google Cloud Storage, and Azure
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./cloud-backup.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -l, --log FILE          Log output to file
#   -p, --provider NAME     Cloud provider (s3, b2, gcs, azure)
#   -s, --source PATH       Source directory/file to backup
#   -d, --destination PATH  Destination path in cloud storage
#   -b, --bucket NAME       Bucket/container name
#   -e, --encrypt           Encrypt backup before upload
#   -c, --compress          Compress backup before upload
#   --compression TYPE      Compression type (gzip, bzip2, xz) [default: gzip]
#   --exclude PATTERN       Exclude pattern (can be used multiple times)
#   --retention DAYS        Delete backups older than N days
#   --dry-run               Show what would be done without doing it
#   --verify                Verify backup after upload
#   --incremental           Incremental backup (requires previous backup)
#   -j, --json              Output in JSON format
#
# Examples:
#   # Basic S3 backup
#   ./cloud-backup.sh --provider s3 --bucket my-backups --source /data --destination backups/data
#
#   # Encrypted and compressed backup to B2
#   ./cloud-backup.sh -p b2 -b my-bucket -s /home -d backups/home --encrypt --compress
#
#   # Incremental backup with retention
#   ./cloud-backup.sh -p gcs -b my-backups -s /var/www --incremental --retention 30
#
#   # Dry run to test configuration
#   ./cloud-backup.sh -p azure -b backups -s /data -d data-backup --dry-run
#
# Dependencies:
#   - aws-cli (for S3)
#   - b2 (for Backblaze B2)
#   - gsutil (for Google Cloud Storage)
#   - az (for Azure)
#   - gpg (for encryption)
#   - tar, gzip/bzip2/xz (for compression)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Backup verification failed
################################################################################

set -euo pipefail

# Script directory and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Configuration variables
VERBOSE=false
LOG_FILE=""
JSON_OUTPUT=false
DRY_RUN=false
ENCRYPT=false
COMPRESS=false
COMPRESSION_TYPE="gzip"
VERIFY=false
INCREMENTAL=false
RETENTION_DAYS=0

# Backup configuration
PROVIDER=""
SOURCE=""
DESTINATION=""
BUCKET=""
EXCLUDE_PATTERNS=()

# Temporary directory for staging
TEMP_DIR="/tmp/cloud-backup-$$"
BACKUP_FILE=""
BACKUP_SIZE=0

################################################################################
# Utility Functions
################################################################################

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    cleanup
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

verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${MAGENTA}[VERBOSE] $1${NC}" >&2
    fi
}

log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] $message" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
${WHITE}Cloud Backup - Multi-Cloud Backup Solution${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -l, --log FILE          Log output to file
    -p, --provider NAME     Cloud provider (s3, b2, gcs, azure)
    -s, --source PATH       Source directory/file to backup
    -d, --destination PATH  Destination path in cloud storage
    -b, --bucket NAME       Bucket/container name
    -e, --encrypt           Encrypt backup before upload (GPG)
    -c, --compress          Compress backup before upload
    --compression TYPE      Compression type: gzip, bzip2, xz (default: gzip)
    --exclude PATTERN       Exclude pattern (can be used multiple times)
    --retention DAYS        Delete backups older than N days
    --dry-run               Show what would be done without doing it
    --verify                Verify backup after upload
    --incremental           Incremental backup (requires previous backup)
    -j, --json              Output in JSON format

${CYAN}Supported Providers:${NC}
    s3        Amazon S3 (requires aws-cli configured)
    b2        Backblaze B2 (requires b2 CLI configured)
    gcs       Google Cloud Storage (requires gsutil configured)
    azure     Azure Blob Storage (requires az CLI configured)

${CYAN}Examples:${NC}
    # Basic S3 backup
    $SCRIPT_NAME --provider s3 --bucket my-backups \\
                 --source /data --destination backups/data

    # Encrypted and compressed backup
    $SCRIPT_NAME -p b2 -b my-bucket -s /home -d backups/home \\
                 --encrypt --compress

    # Incremental backup with 30-day retention
    $SCRIPT_NAME -p gcs -b my-backups -s /var/www \\
                 --incremental --retention 30

    # Backup with exclusions
    $SCRIPT_NAME -p s3 -b backups -s /data -d data-backup \\
                 --exclude "*.log" --exclude "*.tmp"

${CYAN}Environment Variables:${NC}
    AWS_ACCESS_KEY_ID       AWS access key for S3
    AWS_SECRET_ACCESS_KEY   AWS secret key for S3
    B2_ACCOUNT_ID           B2 account ID
    B2_APPLICATION_KEY      B2 application key
    GOOGLE_APPLICATION_CREDENTIALS  Path to GCS credentials
    AZURE_STORAGE_ACCOUNT   Azure storage account
    AZURE_STORAGE_KEY       Azure storage key

EOF
}

check_dependencies() {
    local missing_deps=()

    # Common dependencies
    for cmd in tar gpg; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # Compression tools
    if [[ "$COMPRESS" == true ]]; then
        case "$COMPRESSION_TYPE" in
            gzip)
                if ! command -v gzip &> /dev/null; then
                    missing_deps+=("gzip")
                fi
                ;;
            bzip2)
                if ! command -v bzip2 &> /dev/null; then
                    missing_deps+=("bzip2")
                fi
                ;;
            xz)
                if ! command -v xz &> /dev/null; then
                    missing_deps+=("xz")
                fi
                ;;
        esac
    fi

    # Provider-specific dependencies
    case "$PROVIDER" in
        s3)
            if ! command -v aws &> /dev/null; then
                missing_deps+=("aws-cli")
            fi
            ;;
        b2)
            if ! command -v b2 &> /dev/null; then
                missing_deps+=("b2")
            fi
            ;;
        gcs)
            if ! command -v gsutil &> /dev/null; then
                missing_deps+=("gsutil (Google Cloud SDK)")
            fi
            ;;
        azure)
            if ! command -v az &> /dev/null; then
                missing_deps+=("azure-cli")
            fi
            ;;
    esac

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" 3
    fi
}

validate_arguments() {
    if [[ -z "$PROVIDER" ]]; then
        error_exit "Provider is required. Use -p or --provider" 2
    fi

    if [[ ! "$PROVIDER" =~ ^(s3|b2|gcs|azure)$ ]]; then
        error_exit "Invalid provider: $PROVIDER. Must be one of: s3, b2, gcs, azure" 2
    fi

    if [[ -z "$SOURCE" ]]; then
        error_exit "Source path is required. Use -s or --source" 2
    fi

    if [[ ! -e "$SOURCE" ]]; then
        error_exit "Source path does not exist: $SOURCE" 2
    fi

    if [[ -z "$BUCKET" ]]; then
        error_exit "Bucket name is required. Use -b or --bucket" 2
    fi

    if [[ -z "$DESTINATION" ]]; then
        DESTINATION=$(basename "$SOURCE")
        warning "No destination specified, using: $DESTINATION"
    fi
}

################################################################################
# Backup Creation Functions
################################################################################

create_backup_archive() {
    info "Creating backup archive..."

    mkdir -p "$TEMP_DIR"

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local basename=$(basename "$SOURCE")
    BACKUP_FILE="$TEMP_DIR/${basename}-${timestamp}.tar"

    # Build tar command
    local tar_cmd="tar -c"

    # Add verbosity
    if [[ "$VERBOSE" == true ]]; then
        tar_cmd="$tar_cmd -v"
    fi

    # Add exclusions
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        tar_cmd="$tar_cmd --exclude='$pattern'"
    done

    # Create tar archive
    verbose "Running: $tar_cmd -f $BACKUP_FILE -C $(dirname "$SOURCE") $(basename "$SOURCE")"

    if [[ "$DRY_RUN" == false ]]; then
        eval "$tar_cmd -f $BACKUP_FILE -C $(dirname "$SOURCE") $(basename "$SOURCE")" || error_exit "Failed to create tar archive" 1
        success "Backup archive created: $BACKUP_FILE"
    else
        info "[DRY-RUN] Would create: $BACKUP_FILE"
    fi
}

compress_backup() {
    if [[ "$COMPRESS" == false ]]; then
        return 0
    fi

    info "Compressing backup with $COMPRESSION_TYPE..."

    local compressed_file=""

    case "$COMPRESSION_TYPE" in
        gzip)
            compressed_file="${BACKUP_FILE}.gz"
            if [[ "$DRY_RUN" == false ]]; then
                gzip -v "$BACKUP_FILE" || error_exit "Failed to compress backup" 1
                BACKUP_FILE="$compressed_file"
                success "Backup compressed with gzip"
            else
                info "[DRY-RUN] Would compress with gzip"
                BACKUP_FILE="$compressed_file"
            fi
            ;;
        bzip2)
            compressed_file="${BACKUP_FILE}.bz2"
            if [[ "$DRY_RUN" == false ]]; then
                bzip2 -v "$BACKUP_FILE" || error_exit "Failed to compress backup" 1
                BACKUP_FILE="$compressed_file"
                success "Backup compressed with bzip2"
            else
                info "[DRY-RUN] Would compress with bzip2"
                BACKUP_FILE="$compressed_file"
            fi
            ;;
        xz)
            compressed_file="${BACKUP_FILE}.xz"
            if [[ "$DRY_RUN" == false ]]; then
                xz -v "$BACKUP_FILE" || error_exit "Failed to compress backup" 1
                BACKUP_FILE="$compressed_file"
                success "Backup compressed with xz"
            else
                info "[DRY-RUN] Would compress with xz"
                BACKUP_FILE="$compressed_file"
            fi
            ;;
    esac
}

encrypt_backup() {
    if [[ "$ENCRYPT" == false ]]; then
        return 0
    fi

    info "Encrypting backup with GPG..."

    local encrypted_file="${BACKUP_FILE}.gpg"

    if [[ "$DRY_RUN" == false ]]; then
        gpg --symmetric --cipher-algo AES256 --batch --yes -o "$encrypted_file" "$BACKUP_FILE" || error_exit "Failed to encrypt backup" 1
        rm -f "$BACKUP_FILE"
        BACKUP_FILE="$encrypted_file"
        success "Backup encrypted"
    else
        info "[DRY-RUN] Would encrypt with GPG"
        BACKUP_FILE="$encrypted_file"
    fi
}

calculate_backup_size() {
    if [[ "$DRY_RUN" == false ]] && [[ -f "$BACKUP_FILE" ]]; then
        BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null || echo 0)
        local human_size=$(numfmt --to=iec-i --suffix=B "$BACKUP_SIZE" 2>/dev/null || echo "${BACKUP_SIZE} bytes")
        info "Backup size: $human_size"
    fi
}

################################################################################
# Cloud Upload Functions
################################################################################

upload_to_s3() {
    local remote_path="s3://${BUCKET}/${DESTINATION}/$(basename "$BACKUP_FILE")"

    info "Uploading to S3: $remote_path"

    if [[ "$DRY_RUN" == false ]]; then
        aws s3 cp "$BACKUP_FILE" "$remote_path" ${VERBOSE:+--debug} || error_exit "Failed to upload to S3" 1
        success "Uploaded to S3: $remote_path"
    else
        info "[DRY-RUN] Would upload to: $remote_path"
    fi
}

upload_to_b2() {
    local remote_path="${DESTINATION}/$(basename "$BACKUP_FILE")"

    info "Uploading to B2: b2://${BUCKET}/${remote_path}"

    if [[ "$DRY_RUN" == false ]]; then
        b2 upload-file "$BUCKET" "$BACKUP_FILE" "$remote_path" || error_exit "Failed to upload to B2" 1
        success "Uploaded to B2: b2://${BUCKET}/${remote_path}"
    else
        info "[DRY-RUN] Would upload to: b2://${BUCKET}/${remote_path}"
    fi
}

upload_to_gcs() {
    local remote_path="gs://${BUCKET}/${DESTINATION}/$(basename "$BACKUP_FILE")"

    info "Uploading to GCS: $remote_path"

    if [[ "$DRY_RUN" == false ]]; then
        gsutil cp "$BACKUP_FILE" "$remote_path" || error_exit "Failed to upload to GCS" 1
        success "Uploaded to GCS: $remote_path"
    else
        info "[DRY-RUN] Would upload to: $remote_path"
    fi
}

upload_to_azure() {
    local remote_path="${DESTINATION}/$(basename "$BACKUP_FILE")"

    info "Uploading to Azure: ${BUCKET}/${remote_path}"

    if [[ "$DRY_RUN" == false ]]; then
        az storage blob upload --account-name "$AZURE_STORAGE_ACCOUNT" \
                              --container-name "$BUCKET" \
                              --name "$remote_path" \
                              --file "$BACKUP_FILE" \
                              --auth-mode key || error_exit "Failed to upload to Azure" 1
        success "Uploaded to Azure: ${BUCKET}/${remote_path}"
    else
        info "[DRY-RUN] Would upload to: ${BUCKET}/${remote_path}"
    fi
}

upload_backup() {
    case "$PROVIDER" in
        s3)
            upload_to_s3
            ;;
        b2)
            upload_to_b2
            ;;
        gcs)
            upload_to_gcs
            ;;
        azure)
            upload_to_azure
            ;;
    esac
}

################################################################################
# Verification and Cleanup Functions
################################################################################

verify_backup() {
    if [[ "$VERIFY" == false ]]; then
        return 0
    fi

    info "Verifying backup..."

    # Verification logic depends on provider
    case "$PROVIDER" in
        s3)
            local remote_path="s3://${BUCKET}/${DESTINATION}/$(basename "$BACKUP_FILE")"
            if aws s3 ls "$remote_path" &>/dev/null; then
                success "Backup verified on S3"
            else
                error_exit "Backup verification failed" 4
            fi
            ;;
        b2)
            # B2 verification would require downloading and comparing
            warning "B2 verification not yet implemented"
            ;;
        gcs)
            local remote_path="gs://${BUCKET}/${DESTINATION}/$(basename "$BACKUP_FILE")"
            if gsutil ls "$remote_path" &>/dev/null; then
                success "Backup verified on GCS"
            else
                error_exit "Backup verification failed" 4
            fi
            ;;
        azure)
            local remote_path="${DESTINATION}/$(basename "$BACKUP_FILE")"
            if az storage blob exists --account-name "$AZURE_STORAGE_ACCOUNT" \
                                     --container-name "$BUCKET" \
                                     --name "$remote_path" \
                                     --auth-mode key | grep -q "true"; then
                success "Backup verified on Azure"
            else
                error_exit "Backup verification failed" 4
            fi
            ;;
    esac
}

apply_retention_policy() {
    if [[ $RETENTION_DAYS -eq 0 ]]; then
        return 0
    fi

    info "Applying retention policy: deleting backups older than $RETENTION_DAYS days..."

    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would delete backups older than $RETENTION_DAYS days"
        return 0
    fi

    # Retention logic depends on provider
    case "$PROVIDER" in
        s3)
            warning "S3 retention policy should be configured via lifecycle rules"
            ;;
        b2)
            warning "B2 retention policy should be configured via lifecycle rules"
            ;;
        gcs)
            warning "GCS retention policy should be configured via lifecycle rules"
            ;;
        azure)
            warning "Azure retention policy should be configured via lifecycle management"
            ;;
    esac
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        verbose "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

################################################################################
# Main Backup Function
################################################################################

main() {
    local start_time=$(date +%s)

    check_dependencies
    validate_arguments

    info "Starting cloud backup to $PROVIDER..."
    info "Source: $SOURCE"
    info "Destination: $BUCKET/$DESTINATION"

    log_message "Backup started - Provider: $PROVIDER, Source: $SOURCE"

    # Create backup
    create_backup_archive
    compress_backup
    encrypt_backup
    calculate_backup_size

    # Upload to cloud
    upload_backup

    # Verify and cleanup
    verify_backup
    apply_retention_policy

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    success "Backup completed successfully in ${duration}s"
    log_message "Backup completed - Duration: ${duration}s, Size: $BACKUP_SIZE bytes"

    # JSON output
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "status": "success",
  "provider": "$PROVIDER",
  "source": "$SOURCE",
  "destination": "$BUCKET/$DESTINATION",
  "backup_file": "$(basename "$BACKUP_FILE")",
  "size_bytes": $BACKUP_SIZE,
  "duration_seconds": $duration,
  "encrypted": $ENCRYPT,
  "compressed": $COMPRESS,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
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
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -p|--provider)
            PROVIDER="$2"
            shift 2
            ;;
        -s|--source)
            SOURCE="$2"
            shift 2
            ;;
        -d|--destination)
            DESTINATION="$2"
            shift 2
            ;;
        -b|--bucket)
            BUCKET="$2"
            shift 2
            ;;
        -e|--encrypt)
            ENCRYPT=true
            shift
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        --compression)
            COMPRESSION_TYPE="$2"
            shift 2
            ;;
        --exclude)
            EXCLUDE_PATTERNS+=("$2")
            shift 2
            ;;
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --incremental)
            INCREMENTAL=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1\nUse -h or --help for usage information." 2
            ;;
    esac
done

################################################################################
# Cleanup trap
################################################################################

trap cleanup EXIT INT TERM

################################################################################
# Main Execution
################################################################################

main

exit 0
