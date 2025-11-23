#!/bin/bash

################################################################################
# Script Name: migration-assistant.sh
# Description: Data migration assistant for moving data between systems, databases,
#              and formats with validation, rollback, and progress tracking.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.1
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

SOURCE=""
DESTINATION=""
MIGRATION_TYPE=""
BATCH_SIZE=1000
DRY_RUN=false
VALIDATE=true
CREATE_BACKUP=true
RESUME=false
STATE_FILE=".migration_state"
VERBOSE=false

declare -i TOTAL_RECORDS=0
declare -i MIGRATED_RECORDS=0
declare -i FAILED_RECORDS=0

################################################################################
# State Management
################################################################################

save_state() {
    local record_num="$1"
    echo "$record_num" > "$STATE_FILE"
}

load_state() {
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "0"
}

clear_state() {
    rm -f "$STATE_FILE"
}

################################################################################
# Backup Functions
################################################################################

create_backup() {
    local dest="$1"
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    
    info "Creating backup: $backup_name"
    
    case "$MIGRATION_TYPE" in
        file)
            if [[ -f "$dest" ]]; then
                cp "$dest" "${dest}.${backup_name}"
                success "Backup created: ${dest}.${backup_name}"
            fi
            ;;
        database)
            # Database backup (placeholder)
            info "Database backup: $backup_name"
            ;;
    esac
}

################################################################################
# Migration Functions
################################################################################

migrate_file_to_file() {
    local src="$1"
    local dest="$2"
    
    print_header "FILE TO FILE MIGRATION" 70
    echo
    
    [[ ! -f "$src" ]] && error_exit "Source file not found: $src" 1
    
    TOTAL_RECORDS=$(wc -l < "$src")
    info "Total records to migrate: $TOTAL_RECORDS"
    
    local start_line=1
    if [[ "$RESUME" == true ]]; then
        start_line=$(load_state)
        info "Resuming from record: $start_line"
    fi
    
    # Create backup if enabled
    [[ "$CREATE_BACKUP" == true ]] && [[ -f "$dest" ]] && create_backup "$dest"
    
    # Initialize destination
    [[ $start_line -eq 1 ]] && > "$dest"
    
    echo
    info "Migrating in batches of $BATCH_SIZE..."
    
    local line_num=0
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip already migrated records
        [[ $line_num -lt $start_line ]] && continue
        
        # Validate if enabled
        if [[ "$VALIDATE" == true ]]; then
            if [[ -z "$line" ]]; then
                ((FAILED_RECORDS++))
                [[ "$VERBOSE" == true ]] && warning "Empty line at $line_num"
                continue
            fi
        fi
        
        # Migrate record
        if [[ "$DRY_RUN" == false ]]; then
            echo "$line" >> "$dest"
        fi
        
        ((MIGRATED_RECORDS++))
        
        # Progress update
        if (( MIGRATED_RECORDS % BATCH_SIZE == 0 )); then
            local progress=$(awk "BEGIN {printf \"%.1f\", ($MIGRATED_RECORDS/$TOTAL_RECORDS)*100}")
            info "Progress: $MIGRATED_RECORDS/$TOTAL_RECORDS ($progress%)"
            save_state "$line_num"
        fi
    done < "$src"
    
    clear_state
}

migrate_csv_to_json() {
    local src="$1"
    local dest="$2"
    
    print_header "CSV TO JSON MIGRATION" 70
    echo
    
    require_command jq jq
    
    [[ ! -f "$src" ]] && error_exit "Source file not found: $src" 1
    
    info "Converting CSV to JSON..."
    
    # Use data-converter if available
    local converter="${SCRIPT_DIR}/data-converter.sh"
    if [[ -x "$converter" ]]; then
        "$converter" -i "$src" -o "$dest" -f csv -t json
    else
        # Fallback conversion
        local header=$(head -1 "$src")
        IFS=',' read -ra headers <<< "$header"
        
        echo "[" > "$dest"
        local first=true
        
        tail -n +2 "$src" | while IFS= read -r line; do
            [[ "$first" == false ]] && echo "," >> "$dest"
            first=false
            
            IFS=',' read -ra values <<< "$line"
            
            echo -n "  {" >> "$dest"
            for ((i=0; i<${#headers[@]}; i++)); do
                [[ $i -gt 0 ]] && echo -n "," >> "$dest"
                echo -n "\"${headers[$i]}\":\"${values[$i]:-}\"" >> "$dest"
            done
            echo -n "}" >> "$dest"
            
            ((MIGRATED_RECORDS++))
        done
        
        echo >> "$dest"
        echo "]" >> "$dest"
    fi
    
    TOTAL_RECORDS=$MIGRATED_RECORDS
}

migrate_directory() {
    local src_dir="$1"
    local dest_dir="$2"
    
    print_header "DIRECTORY MIGRATION" 70
    echo
    
    [[ ! -d "$src_dir" ]] && error_exit "Source directory not found: $src_dir" 1
    
    mkdir -p "$dest_dir"
    
    info "Migrating files from $src_dir to $dest_dir"
    
    local file_count=0
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local dest_file="$dest_dir/$filename"
        
        info "Migrating: $filename"
        
        if [[ "$DRY_RUN" == false ]]; then
            cp "$file" "$dest_file"
        fi
        
        ((file_count++))
        ((MIGRATED_RECORDS++))
    done < <(find "$src_dir" -maxdepth 1 -type f -print0)
    
    TOTAL_RECORDS=$file_count
}

################################################################################
# Validation Functions
################################################################################

validate_migration() {
    echo
    print_separator
    echo -e "${BOLD_CYAN}Validation:${NC}"
    
    # Compare record counts
    if [[ -f "$SOURCE" ]] && [[ -f "$DESTINATION" ]]; then
        local src_count=$(wc -l < "$SOURCE")
        local dest_count=$(wc -l < "$DESTINATION")
        
        printf "  Source records:      %d\n" "$src_count"
        printf "  Destination records: %d\n" "$dest_count"
        
        if [[ $src_count -eq $dest_count ]]; then
            success "Record counts match"
        else
            warning "Record count mismatch"
        fi
    fi
    
    # Data integrity check (sample)
    if command_exists md5sum && [[ -f "$SOURCE" ]] && [[ -f "$DESTINATION" ]]; then
        local src_md5=$(head -100 "$SOURCE" | md5sum | cut -d' ' -f1)
        local dest_md5=$(head -100 "$DESTINATION" | md5sum | cut -d' ' -f1)
        
        if [[ "$src_md5" == "$dest_md5" ]]; then
            success "Sample data integrity verified"
        else
            warning "Data integrity check failed (first 100 lines differ)"
        fi
    fi
}

################################################################################
# Main Migration Router
################################################################################

run_migration() {
    local start_time=$(date +%s)
    
    # Determine migration type
    if [[ -z "$MIGRATION_TYPE" ]]; then
        if [[ -f "$SOURCE" ]]; then
            MIGRATION_TYPE="file"
        elif [[ -d "$SOURCE" ]]; then
            MIGRATION_TYPE="directory"
        fi
    fi
    
    case "$MIGRATION_TYPE" in
        file)
            migrate_file_to_file "$SOURCE" "$DESTINATION"
            ;;
        csv-to-json)
            migrate_csv_to_json "$SOURCE" "$DESTINATION"
            ;;
        directory)
            migrate_directory "$SOURCE" "$DESTINATION"
            ;;
        *)
            error_exit "Unknown migration type: $MIGRATION_TYPE" 1
            ;;
    esac
    
    # Validation
    if [[ "$VALIDATE" == true ]] && [[ "$DRY_RUN" == false ]]; then
        validate_migration
    fi
    
    # Summary
    echo
    print_separator
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY RUN - No data was actually migrated"
    else
        success "Migration completed in ${duration}s"
    fi
    
    echo
    echo "Summary:"
    printf "  Total records:    %d\n" "$TOTAL_RECORDS"
    printf "  Migrated:         %d\n" "$MIGRATED_RECORDS"
    printf "  Failed:           %d\n" "$FAILED_RECORDS"
    
    if [[ $MIGRATED_RECORDS -eq $TOTAL_RECORDS ]] && [[ $FAILED_RECORDS -eq 0 ]]; then
        echo -e "\n${GREEN}✓ All records migrated successfully${NC}"
    else
        echo -e "\n${YELLOW}⚠ Migration completed with issues${NC}"
    fi
}

################################################################################
# Usage
################################################################################

show_usage() {
    cat << EOF
${WHITE}Migration Assistant - Data Migration Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help message
    -s, --source PATH       Source path
    -d, --destination PATH  Destination path
    -t, --type TYPE         Migration type: file, directory, csv-to-json
    --batch-size N          Records per batch (default: 1000)
    --dry-run               Simulate migration without writing
    --no-validate           Skip validation
    --no-backup             Skip backup creation
    --resume                Resume interrupted migration
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Migrate file
    $(basename "$0") -s old_data.csv -d new_data.csv
    
    # Migrate with validation
    $(basename "$0") -s data.json -d backup.json --validate
    
    # Convert format during migration
    $(basename "$0") -s data.csv -d data.json -t csv-to-json
    
    # Migrate directory
    $(basename "$0") -s /old/data/ -d /new/data/ -t directory
    
    # Dry run
    $(basename "$0") -s source.db -d dest.db --dry-run
    
    # Resume interrupted migration
    $(basename "$0") -s large_file.csv -d dest.csv --resume

${CYAN}Features:${NC}
    • Batch processing
    • Progress tracking
    • Resume capability
    • Automatic backup
    • Data validation
    • Dry-run mode
    • Error handling

EOF
}

################################################################################
# Main
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -s|--source) SOURCE="$2"; shift 2 ;;
        -d|--destination) DESTINATION="$2"; shift 2 ;;
        -t|--type) MIGRATION_TYPE="$2"; shift 2 ;;
        --batch-size) BATCH_SIZE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --no-validate) VALIDATE=false; shift ;;
        --no-backup) CREATE_BACKUP=false; shift ;;
        --resume) RESUME=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$SOURCE" ]] && error_exit "Source required (-s)" 2
[[ -z "$DESTINATION" ]] && error_exit "Destination required (-d)" 2

run_migration

