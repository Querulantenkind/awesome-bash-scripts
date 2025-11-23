#!/bin/bash

################################################################################
# Script Name: database-backup.sh
# Description: Automated database backup tool supporting MySQL/MariaDB,
#              PostgreSQL, MongoDB, and SQLite. Features compression,
#              encryption, rotation, and automated scheduling support.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./database-backup.sh [options]
#
# Options:
#   -h, --help              Show this help message
#   -v, --verbose           Enable verbose output
#   -t, --type TYPE         Database type (mysql|postgresql|mongodb|sqlite)
#   -H, --host HOST         Database host (default: localhost)
#   -P, --port PORT         Database port
#   -u, --user USER         Database username
#   -p, --password PASS     Database password
#   -d, --database DB       Database name (or "all" for all databases)
#   -o, --output DIR        Output directory for backups
#   -c, --compress          Enable compression (gzip)
#   -e, --encrypt           Enable GPG encryption
#   -k, --key EMAIL         GPG key email for encryption
#   -r, --rotate NUM        Keep last N backups (default: 7)
#   -l, --log FILE          Log file path
#   --config FILE           Use configuration file
#   --list                  List available backups
#
# Examples:
#   ./database-backup.sh -t mysql -u root -d mydb -o /backup
#   ./database-backup.sh -t postgresql -u postgres -d all -c -o /backup
#   ./database-backup.sh -t mongodb -d mydb -o /backup -e -k user@example.com
#   ./database-backup.sh --config /etc/db-backup.conf
#
# Dependencies:
#   - mysqldump (for MySQL/MariaDB)
#   - pg_dump (for PostgreSQL)
#   - mongodump (for MongoDB)
#   - sqlite3 (for SQLite)
#   - gzip (optional, for compression)
#   - gpg (optional, for encryption)
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependency
#   4 - Backup failed
################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME=$(basename "$0")

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration variables
VERBOSE=false
DB_TYPE=""
DB_HOST="localhost"
DB_PORT=""
DB_USER=""
DB_PASSWORD=""
DB_NAME=""
OUTPUT_DIR=""
ENABLE_COMPRESS=false
ENABLE_ENCRYPT=false
GPG_KEY=""
ROTATION_COUNT=7
LOG_FILE=""
CONFIG_FILE=""
LIST_BACKUPS=false

# Internal variables
BACKUP_DATE=$(date '+%Y-%m-%d_%H-%M-%S')
TEMP_DIR="/tmp/db-backup-$$"

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
        echo -e "[VERBOSE] $1" >&2
    fi
}

log_message() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT INT TERM

show_usage() {
    cat << EOF
${WHITE}Database Backup Tool - Multi-Database Backup Solution${NC}

${CYAN}Usage:${NC}
    $SCRIPT_NAME [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -t, --type TYPE         Database type (mysql|postgresql|mongodb|sqlite)
    -H, --host HOST         Database host (default: localhost)
    -P, --port PORT         Database port
    -u, --user USER         Database username
    -p, --password PASS     Database password (use with caution)
    -d, --database DB       Database name (or "all" for all databases)
    -o, --output DIR        Output directory for backups
    -c, --compress          Enable gzip compression
    -e, --encrypt           Enable GPG encryption
    -k, --key EMAIL         GPG key email for encryption
    -r, --rotate NUM        Keep last N backups (default: 7)
    -l, --log FILE          Log file path
    --config FILE           Use configuration file
    --list                  List available backups

${CYAN}Examples:${NC}
    # MySQL backup
    $SCRIPT_NAME -t mysql -u root -d mydb -o /backup -c

    # PostgreSQL backup (all databases)
    $SCRIPT_NAME -t postgresql -u postgres -d all -o /backup

    # MongoDB backup with encryption
    $SCRIPT_NAME -t mongodb -d mydb -o /backup -e -k user@example.com

    # SQLite backup
    $SCRIPT_NAME -t sqlite -d /path/to/database.db -o /backup

    # Using configuration file
    $SCRIPT_NAME --config /etc/db-backup.conf

${CYAN}Configuration File Format:${NC}
    DB_TYPE=mysql
    DB_HOST=localhost
    DB_USER=root
    DB_PASSWORD=secret
    DB_NAME=all
    OUTPUT_DIR=/backup
    ENABLE_COMPRESS=true
    ROTATION_COUNT=14

${CYAN}Features:${NC}
    • Support for MySQL/MariaDB, PostgreSQL, MongoDB, SQLite
    • Gzip compression
    • GPG encryption
    • Automatic backup rotation
    • All databases backup option
    • Configuration file support
    • Detailed logging
    • Integrity verification

${CYAN}Security Note:${NC}
    Avoid passing passwords on command line. Use:
    • Configuration files with restricted permissions (chmod 600)
    • Environment variables
    • MySQL .my.cnf or PostgreSQL .pgpass files

EOF
}

check_dependencies() {
    case "$DB_TYPE" in
        mysql|mariadb)
            if ! command -v mysqldump &> /dev/null; then
                error_exit "mysqldump not found (required for MySQL backups)" 3
            fi
            ;;
        postgresql)
            if ! command -v pg_dump &> /dev/null; then
                error_exit "pg_dump not found (required for PostgreSQL backups)" 3
            fi
            ;;
        mongodb)
            if ! command -v mongodump &> /dev/null; then
                error_exit "mongodump not found (required for MongoDB backups)" 3
            fi
            ;;
        sqlite)
            if ! command -v sqlite3 &> /dev/null; then
                error_exit "sqlite3 not found (required for SQLite backups)" 3
            fi
            ;;
        *)
            error_exit "Invalid database type: $DB_TYPE" 2
            ;;
    esac
    
    if [[ "$ENABLE_COMPRESS" == true ]] && ! command -v gzip &> /dev/null; then
        error_exit "gzip not found (required for compression)" 3
    fi
    
    if [[ "$ENABLE_ENCRYPT" == true ]] && ! command -v gpg &> /dev/null; then
        error_exit "gpg not found (required for encryption)" 3
    fi
}

load_config_file() {
    local config="$1"
    
    if [[ ! -f "$config" ]]; then
        error_exit "Configuration file not found: $config" 2
    fi
    
    verbose "Loading configuration from: $config"
    
    # Source the config file
    # shellcheck source=/dev/null
    source "$config"
    
    verbose "Configuration loaded successfully"
}

################################################################################
# Database Backup Functions
################################################################################

backup_mysql() {
    local db="$1"
    local output_file="$2"
    
    info "Backing up MySQL database: $db"
    
    local mysql_opts="-h $DB_HOST"
    [[ -n "$DB_PORT" ]] && mysql_opts="$mysql_opts -P $DB_PORT"
    [[ -n "$DB_USER" ]] && mysql_opts="$mysql_opts -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mysql_opts="$mysql_opts -p$DB_PASSWORD"
    
    if [[ "$db" == "all" ]]; then
        mysqldump $mysql_opts --all-databases --single-transaction --quick --lock-tables=false > "$output_file" 2>&1
    else
        mysqldump $mysql_opts --single-transaction --quick --databases "$db" > "$output_file" 2>&1
    fi
    
    if [[ $? -eq 0 ]]; then
        success "MySQL backup completed: $output_file"
        return 0
    else
        error_exit "MySQL backup failed" 4
    fi
}

backup_postgresql() {
    local db="$1"
    local output_file="$2"
    
    info "Backing up PostgreSQL database: $db"
    
    # Set environment variables for PostgreSQL
    export PGHOST="${DB_HOST}"
    [[ -n "$DB_PORT" ]] && export PGPORT="$DB_PORT"
    [[ -n "$DB_USER" ]] && export PGUSER="$DB_USER"
    [[ -n "$DB_PASSWORD" ]] && export PGPASSWORD="$DB_PASSWORD"
    
    if [[ "$db" == "all" ]]; then
        pg_dumpall --clean > "$output_file" 2>&1
    else
        pg_dump --clean --create "$db" > "$output_file" 2>&1
    fi
    
    if [[ $? -eq 0 ]]; then
        success "PostgreSQL backup completed: $output_file"
        return 0
    else
        error_exit "PostgreSQL backup failed" 4
    fi
}

backup_mongodb() {
    local db="$1"
    local output_dir="$2"
    
    info "Backing up MongoDB database: $db"
    
    local mongo_opts="--host=$DB_HOST"
    [[ -n "$DB_PORT" ]] && mongo_opts="$mongo_opts --port=$DB_PORT"
    [[ -n "$DB_USER" ]] && mongo_opts="$mongo_opts --username=$DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mongo_opts="$mongo_opts --password=$DB_PASSWORD"
    
    if [[ "$db" == "all" ]]; then
        mongodump $mongo_opts --out="$output_dir" 2>&1
    else
        mongodump $mongo_opts --db="$db" --out="$output_dir" 2>&1
    fi
    
    if [[ $? -eq 0 ]]; then
        # Create tar archive from mongodump output
        local tar_file="${output_dir}.tar"
        tar -cf "$tar_file" -C "$output_dir" .
        rm -rf "$output_dir"
        mv "$tar_file" "$output_dir"
        
        success "MongoDB backup completed: $output_dir"
        return 0
    else
        error_exit "MongoDB backup failed" 4
    fi
}

backup_sqlite() {
    local db="$1"
    local output_file="$2"
    
    info "Backing up SQLite database: $db"
    
    if [[ ! -f "$db" ]]; then
        error_exit "SQLite database file not found: $db" 4
    fi
    
    # Use .backup command for consistent backup
    sqlite3 "$db" ".backup '$output_file'" 2>&1
    
    if [[ $? -eq 0 ]]; then
        success "SQLite backup completed: $output_file"
        return 0
    else
        error_exit "SQLite backup failed" 4
    fi
}

compress_backup() {
    local file="$1"
    
    info "Compressing backup..."
    
    if gzip -f "$file"; then
        success "Backup compressed: ${file}.gz"
        echo "${file}.gz"
    else
        warning "Compression failed, keeping uncompressed backup"
        echo "$file"
    fi
}

encrypt_backup() {
    local file="$1"
    
    info "Encrypting backup with GPG..."
    
    if [[ -z "$GPG_KEY" ]]; then
        error_exit "GPG key email required for encryption" 2
    fi
    
    if gpg --encrypt --recipient "$GPG_KEY" "$file"; then
        rm -f "$file"
        success "Backup encrypted: ${file}.gpg"
        echo "${file}.gpg"
    else
        error_exit "Encryption failed" 4
    fi
}

create_backup() {
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TEMP_DIR"
    
    local db_name_safe=$(echo "$DB_NAME" | tr '/' '_')
    local backup_filename="${DB_TYPE}_${db_name_safe}_${BACKUP_DATE}.sql"
    local backup_file="${TEMP_DIR}/${backup_filename}"
    
    verbose "Creating backup: $backup_file"
    
    # Perform database-specific backup
    case "$DB_TYPE" in
        mysql|mariadb)
            backup_mysql "$DB_NAME" "$backup_file"
            ;;
        postgresql)
            backup_postgresql "$DB_NAME" "$backup_file"
            ;;
        mongodb)
            backup_mongodb "$DB_NAME" "$backup_file"
            ;;
        sqlite)
            backup_sqlite "$DB_NAME" "$backup_file"
            ;;
    esac
    
    # Compress if requested
    if [[ "$ENABLE_COMPRESS" == true ]]; then
        backup_file=$(compress_backup "$backup_file")
    fi
    
    # Move to output directory
    local final_file="${OUTPUT_DIR}/$(basename "$backup_file")"
    mv "$backup_file" "$final_file"
    backup_file="$final_file"
    
    # Encrypt if requested
    if [[ "$ENABLE_ENCRYPT" == true ]]; then
        backup_file=$(encrypt_backup "$backup_file")
    fi
    
    # Create metadata
    create_metadata "$backup_file"
    
    log_message "Backup created: $backup_file"
    
    # Get file size
    local size=$(du -h "$backup_file" | awk '{print $1}')
    success "Backup completed: $(basename "$backup_file") (${size})"
}

create_metadata() {
    local backup_file="$1"
    local meta_file="${backup_file}.meta"
    
    cat > "$meta_file" << EOF
backup_date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
database_type=$DB_TYPE
database_name=$DB_NAME
database_host=$DB_HOST
hostname=$(hostname)
user=$USER
compressed=$ENABLE_COMPRESS
encrypted=$ENABLE_ENCRYPT
file_size=$(du -b "$backup_file" | awk '{print $1}')
checksum=$(sha256sum "$backup_file" | awk '{print $1}')
EOF
    
    verbose "Metadata created: $meta_file"
}

rotate_backups() {
    if [[ $ROTATION_COUNT -le 0 ]]; then
        return
    fi
    
    info "Rotating backups (keeping last $ROTATION_COUNT)..."
    
    local db_name_safe=$(echo "$DB_NAME" | tr '/' '_')
    local pattern="${OUTPUT_DIR}/${DB_TYPE}_${db_name_safe}_*.sql*"
    local backups=$(ls -t $pattern 2>/dev/null || true)
    local count=0
    
    for backup in $backups; do
        ((count++))
        if [[ $count -gt $ROTATION_COUNT ]]; then
            verbose "Removing old backup: $backup"
            rm -f "$backup" "${backup}.meta" "${backup}.gpg"
            log_message "Removed old backup: $backup"
        fi
    done
    
    success "Backup rotation completed"
}

list_available_backups() {
    info "Available backups in: $OUTPUT_DIR"
    echo ""
    
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        warning "Backup directory does not exist: $OUTPUT_DIR"
        return
    fi
    
    local backups=$(ls -t "$OUTPUT_DIR"/*.sql* 2>/dev/null || true)
    
    if [[ -z "$backups" ]]; then
        warning "No backups found"
        return
    fi
    
    printf "${CYAN}%-40s %-10s %-20s${NC}\n" "Filename" "Size" "Date"
    echo "────────────────────────────────────────────────────────────────────"
    
    for backup in $backups; do
        [[ "$backup" == *.meta ]] && continue
        
        local filename=$(basename "$backup")
        local size=$(du -h "$backup" | awk '{print $1}')
        local date=$(stat -c '%y' "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        printf "%-40s %-10s %-20s\n" "${filename:0:40}" "$size" "$date"
        
        if [[ -f "${backup}.meta" ]]; then
            local db_type=$(grep "database_type=" "${backup}.meta" | cut -d'=' -f2)
            local db_name=$(grep "database_name=" "${backup}.meta" | cut -d'=' -f2)
            echo "  └─ Type: $db_type, Database: $db_name"
        fi
    done
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
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "--type requires a database type" 2
            DB_TYPE="$2"
            shift 2
            ;;
        -H|--host)
            [[ -z "${2:-}" ]] && error_exit "--host requires a hostname" 2
            DB_HOST="$2"
            shift 2
            ;;
        -P|--port)
            [[ -z "${2:-}" ]] && error_exit "--port requires a port number" 2
            DB_PORT="$2"
            shift 2
            ;;
        -u|--user)
            [[ -z "${2:-}" ]] && error_exit "--user requires a username" 2
            DB_USER="$2"
            shift 2
            ;;
        -p|--password)
            [[ -z "${2:-}" ]] && error_exit "--password requires a password" 2
            DB_PASSWORD="$2"
            shift 2
            ;;
        -d|--database)
            [[ -z "${2:-}" ]] && error_exit "--database requires a database name" 2
            DB_NAME="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "--output requires a directory path" 2
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -c|--compress)
            ENABLE_COMPRESS=true
            shift
            ;;
        -e|--encrypt)
            ENABLE_ENCRYPT=true
            shift
            ;;
        -k|--key)
            [[ -z "${2:-}" ]] && error_exit "--key requires a GPG key email" 2
            GPG_KEY="$2"
            shift 2
            ;;
        -r|--rotate)
            [[ -z "${2:-}" ]] && error_exit "--rotate requires a number" 2
            ROTATION_COUNT="$2"
            shift 2
            ;;
        -l|--log)
            [[ -z "${2:-}" ]] && error_exit "--log requires a file path" 2
            LOG_FILE="$2"
            shift 2
            ;;
        --config)
            [[ -z "${2:-}" ]] && error_exit "--config requires a file path" 2
            CONFIG_FILE="$2"
            shift 2
            ;;
        --list)
            LIST_BACKUPS=true
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

# Load configuration file if specified
if [[ -n "$CONFIG_FILE" ]]; then
    load_config_file "$CONFIG_FILE"
fi

# Handle list mode
if [[ "$LIST_BACKUPS" == true ]]; then
    [[ -z "$OUTPUT_DIR" ]] && error_exit "Output directory required (use -o)" 2
    list_available_backups
    exit 0
fi

# Validate required parameters
if [[ -z "$DB_TYPE" ]]; then
    error_exit "Database type required (use -t)" 2
fi

if [[ -z "$DB_NAME" ]]; then
    error_exit "Database name required (use -d)" 2
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    error_exit "Output directory required (use -o)" 2
fi

check_dependencies

verbose "Configuration:"
verbose "  Database Type: $DB_TYPE"
verbose "  Database Name: $DB_NAME"
verbose "  Database Host: $DB_HOST"
verbose "  Output Directory: $OUTPUT_DIR"
verbose "  Compression: $ENABLE_COMPRESS"
verbose "  Encryption: $ENABLE_ENCRYPT"

log_message "Database backup started - Type: $DB_TYPE, Database: $DB_NAME"

# Create backup
create_backup

# Rotate old backups
rotate_backups

success "Database backup operation completed successfully!"
log_message "Database backup completed successfully"

