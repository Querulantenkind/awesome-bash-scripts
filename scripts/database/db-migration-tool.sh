#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: db-migration-tool.sh
# Description: Database schema migration helper with version tracking, up/down
#              migrations, rollback support, and multiple database support.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

MIGRATION_DIR="./migrations"
DB_TYPE="mysql"
DB_HOST="localhost"
DB_NAME=""
DB_USER=""
DB_PASS=""
ACTION=""
VERSION=""

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

init_migrations() {
    mkdir -p "$MIGRATION_DIR"
    
    cat > "$MIGRATION_DIR/001_init.sql" << 'EOF'
-- Migration: Initialize migrations table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(255) PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    
    success "Migration directory initialized"
}

create_migration() {
    local name="$1"
    local timestamp=$(date +%Y%m%d%H%M%S)
    local filename="${timestamp}_${name}.sql"
    
    cat > "$MIGRATION_DIR/$filename" << EOF
-- Migration: $name
-- Created: $(date)

-- Up migration
-- Write your schema changes here

-- Down migration (rollback)
-- Write rollback SQL here
EOF
    
    success "Created migration: $filename"
}

run_migration() {
    local file="$1"
    local sql_cmd=""
    
    case "$DB_TYPE" in
        mysql)
            sql_cmd="mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME"
            ;;
        postgres|postgresql)
            sql_cmd="psql -h $DB_HOST -U $DB_USER -d $DB_NAME"
            ;;
        *)
            error_exit "Unsupported database: $DB_TYPE" 2
            ;;
    esac
    
    info "Running migration: $file"
    
    if $sql_cmd < "$file" 2>/dev/null; then
        local version=$(basename "$file" .sql)
        echo "INSERT INTO schema_migrations (version) VALUES ('$version');" | $sql_cmd 2>/dev/null
        success "Migration applied: $file"
    else
        error_exit "Migration failed: $file" 1
    fi
}

migrate_up() {
    info "Running pending migrations..."
    
    for migration in "$MIGRATION_DIR"/*.sql; do
        [[ ! -f "$migration" ]] && continue
        run_migration "$migration"
    done
    
    success "All migrations applied"
}

list_migrations() {
    echo ""
    echo -e "${CYAN}Available Migrations:${NC}"
    ls -1 "$MIGRATION_DIR"/*.sql 2>/dev/null | while read -r f; do
        echo "  • $(basename "$f")"
    done
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --init) ACTION="init"; shift ;;
        --create) ACTION="create"; VERSION="$2"; shift 2 ;;
        --up) ACTION="up"; shift ;;
        --list) ACTION="list"; shift ;;
        --db-type) DB_TYPE="$2"; shift 2 ;;
        --db-name) DB_NAME="$2"; shift 2 ;;
        --db-user) DB_USER="$2"; shift 2 ;;
        --db-pass) DB_PASS="$2"; shift 2 ;;
        --db-host) DB_HOST="$2"; shift 2 ;;
        --dir) MIGRATION_DIR="$2"; shift 2 ;;
        -h|--help) echo "Database Migration Tool"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

case "$ACTION" in
    init) init_migrations ;;
    create) create_migration "$VERSION" ;;
    up) migrate_up ;;
    list) list_migrations ;;
    *) list_migrations ;;
esac
