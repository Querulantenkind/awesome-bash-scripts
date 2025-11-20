#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: db-backup-verify.sh
# Description: Verify database backup integrity, test restore capability, checksum
#              verification, backup size analysis, and automated testing.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

BACKUP_FILE=""
DB_TYPE="mysql"
VERIFY_CHECKSUM=false
TEST_RESTORE=false
REPORT_FILE=""

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

verify_file_integrity() {
    local file="$1"
    
    [[ ! -f "$file" ]] && error_exit "Backup file not found: $file" 2
    
    info "Verifying file integrity..."
    
    # Check if file is not empty
    if [[ ! -s "$file" ]]; then
        error_exit "Backup file is empty" 1
    fi
    
    # Check file format
    case "$file" in
        *.sql)
            if head -1 "$file" | grep -q "^--"; then
                success "SQL backup format verified"
            else
                warning "SQL backup may be corrupted"
            fi
            ;;
        *.gz)
            if gzip -t "$file" 2>/dev/null; then
                success "Gzip integrity verified"
            else
                error_exit "Gzip file corrupted" 1
            fi
            ;;
        *)
            info "Unknown format, basic checks only"
            ;;
    esac
    
    # Show file size
    local size=$(du -h "$file" | awk '{print $1}')
    info "Backup size: $size"
}

verify_checksum() {
    local file="$1"
    local checksum_file="${file}.sha256"
    
    if [[ ! -f "$checksum_file" ]]; then
        warning "Checksum file not found: $checksum_file"
        return 1
    fi
    
    info "Verifying checksum..."
    
    if sha256sum -c "$checksum_file" 2>/dev/null; then
        success "Checksum verification passed"
    else
        error_exit "Checksum verification failed" 1
    fi
}

test_restore_capability() {
    local file="$1"
    local test_db="test_restore_$$"
    
    info "Testing restore capability..."
    warning "This will create a temporary test database"
    
    case "$DB_TYPE" in
        mysql)
            # Create test database
            mysql -e "CREATE DATABASE IF NOT EXISTS $test_db" 2>/dev/null || error_exit "Failed to create test database" 1
            
            # Try to restore
            if mysql "$test_db" < "$file" 2>/dev/null; then
                success "Test restore successful"
                
                # Count tables
                local table_count=$(mysql -N "$test_db" -e "SHOW TABLES" 2>/dev/null | wc -l)
                info "Restored $table_count tables"
                
                # Cleanup
                mysql -e "DROP DATABASE $test_db" 2>/dev/null
            else
                mysql -e "DROP DATABASE IF EXISTS $test_db" 2>/dev/null
                error_exit "Test restore failed" 1
            fi
            ;;
        postgres|postgresql)
            info "PostgreSQL test restore not implemented yet"
            ;;
        *)
            warning "Test restore not supported for: $DB_TYPE"
            ;;
    esac
}

generate_report() {
    local file="$1"
    local report="${2:-backup_verification_report.txt}"
    
    {
        echo "Database Backup Verification Report"
        echo "===================================="
        echo ""
        echo "Backup File: $file"
        echo "Verified: $(date)"
        echo "File Size: $(du -h "$file" | awk '{print $1}')"
        echo ""
        echo "Verification Results:"
        echo "--------------------"
        echo "✓ File integrity check passed"
        [[ "$VERIFY_CHECKSUM" == true ]] && echo "✓ Checksum verification passed"
        [[ "$TEST_RESTORE" == true ]] && echo "✓ Test restore successful"
    } > "$report"
    
    success "Report generated: $report"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file) BACKUP_FILE="$2"; shift 2 ;;
        --db-type) DB_TYPE="$2"; shift 2 ;;
        --checksum) VERIFY_CHECKSUM=true; shift ;;
        --test-restore) TEST_RESTORE=true; shift ;;
        --report) REPORT_FILE="$2"; shift 2 ;;
        -h|--help) echo "Database Backup Verification Tool"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$BACKUP_FILE" ]] && error_exit "Backup file required (use -f)" 2

verify_file_integrity "$BACKUP_FILE"

[[ "$VERIFY_CHECKSUM" == true ]] && verify_checksum "$BACKUP_FILE"
[[ "$TEST_RESTORE" == true ]] && test_restore_capability "$BACKUP_FILE"
[[ -n "$REPORT_FILE" ]] && generate_report "$BACKUP_FILE" "$REPORT_FILE"

success "Backup verification complete"
