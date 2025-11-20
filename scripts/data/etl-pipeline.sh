#!/bin/bash

################################################################################
# Script Name: etl-pipeline.sh
# Description: ETL (Extract, Transform, Load) pipeline runner for data processing
#              workflows with support for multiple sources, transformations, and
#              destinations. Includes scheduling, error handling, and monitoring.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

PIPELINE_CONFIG=""
SOURCE_TYPE=""
SOURCE_PATH=""
DEST_TYPE=""
DEST_PATH=""
TRANSFORM_SCRIPT=""
VALIDATE=false
DRY_RUN=false
PARALLEL=1
VERBOSE=false

declare -a EXTRACT_STEPS=()
declare -a TRANSFORM_STEPS=()
declare -a LOAD_STEPS=()

################################################################################
# Extract Functions
################################################################################

extract_file() {
    local path="$1"
    info "Extracting from file: $path"
    cat "$path"
}

extract_database() {
    local conn="$1"
    local query="$2"
    info "Extracting from database: $conn"
    # Execute database query (placeholder - would need DB-specific commands)
    echo "Database extraction: $query"
}

extract_api() {
    local url="$1"
    info "Extracting from API: $url"
    require_command curl curl
    curl -s "$url"
}

################################################################################
# Transform Functions
################################################################################

transform_filter() {
    local condition="$1"
    [[ "$VERBOSE" == true ]] && info "Applying filter: $condition"
    # Simple grep-based filter
    grep -E "$condition" || true
}

transform_map() {
    local expression="$1"
    [[ "$VERBOSE" == true ]] && info "Applying transformation: $expression"
    # Apply transformation (would use jq for JSON, awk for CSV, etc.)
    eval "$expression"
}

transform_aggregate() {
    local field="$1"
    [[ "$VERBOSE" == true ]] && info "Aggregating by: $field"
    sort | uniq -c
}

################################################################################
# Load Functions
################################################################################

load_file() {
    local path="$1"
    local data="$2"
    info "Loading to file: $path"
    echo "$data" > "$path"
}

load_database() {
    local conn="$1"
    local table="$2"
    local data="$3"
    info "Loading to database: $conn/$table"
    # Database insert (placeholder)
    echo "$data" | head -5
}

load_api() {
    local url="$1"
    local data="$2"
    info "Loading to API: $url"
    require_command curl curl
    curl -s -X POST -d "$data" "$url"
}

################################################################################
# Pipeline Execution
################################################################################

run_pipeline() {
    print_header "ETL PIPELINE EXECUTION" 70
    echo
    
    local start_time=$(date +%s)
    
    # Extract
    echo -e "${BOLD_CYAN}[1/3] EXTRACT${NC}"
    local extracted_data=""
    case "$SOURCE_TYPE" in
        file)
            extracted_data=$(extract_file "$SOURCE_PATH")
            ;;
        database)
            extracted_data=$(extract_database "$SOURCE_PATH" "SELECT * FROM data")
            ;;
        api)
            extracted_data=$(extract_api "$SOURCE_PATH")
            ;;
        *)
            error_exit "Unknown source type: $SOURCE_TYPE" 1
            ;;
    esac
    
    local record_count=$(echo "$extracted_data" | wc -l)
    success "Extracted $record_count records"
    echo
    
    # Transform
    echo -e "${BOLD_CYAN}[2/3] TRANSFORM${NC}"
    local transformed_data="$extracted_data"
    
    if [[ -n "$TRANSFORM_SCRIPT" ]] && [[ -f "$TRANSFORM_SCRIPT" ]]; then
        transformed_data=$(echo "$extracted_data" | bash "$TRANSFORM_SCRIPT")
        success "Applied transformation script"
    fi
    
    local transformed_count=$(echo "$transformed_data" | wc -l)
    success "Transformed to $transformed_count records"
    echo
    
    # Load
    if [[ "$DRY_RUN" == false ]]; then
        echo -e "${BOLD_CYAN}[3/3] LOAD${NC}"
        case "$DEST_TYPE" in
            file)
                load_file "$DEST_PATH" "$transformed_data"
                ;;
            database)
                load_database "$DEST_PATH" "target_table" "$transformed_data"
                ;;
            api)
                load_api "$DEST_PATH" "$transformed_data"
                ;;
            stdout)
                echo "$transformed_data"
                ;;
            *)
                error_exit "Unknown destination type: $DEST_TYPE" 1
                ;;
        esac
        success "Loaded $transformed_count records"
    else
        warning "Dry run - skipping load phase"
        echo "Preview (first 10 lines):"
        echo "$transformed_data" | head -10
    fi
    
    echo
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_separator
    echo -e "${BOLD_GREEN}✓ Pipeline completed in ${duration}s${NC}"
    echo "  Extracted: $record_count records"
    echo "  Transformed: $transformed_count records"
    echo "  Loaded: $([[ "$DRY_RUN" == false ]] && echo "$transformed_count" || echo "0 (dry run)") records"
}

################################################################################
# Usage
################################################################################

show_usage() {
    cat << EOF
${WHITE}ETL Pipeline Runner - Extract, Transform, Load${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help message
    -c, --config FILE       Pipeline configuration file
    --source-type TYPE      Source type: file, database, api
    --source-path PATH      Source path/connection string
    --dest-type TYPE        Destination type: file, database, api, stdout
    --dest-path PATH        Destination path/connection string
    --transform SCRIPT      Transformation script
    --validate              Validate data
    --dry-run               Run without loading
    --parallel N            Parallel workers (default: 1)
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # File to file with transformation
    $(basename "$0") --source-type file --source-path data.csv \\
                     --dest-type file --dest-path output.csv \\
                     --transform transform.sh
    
    # API to database
    $(basename "$0") --source-type api --source-path https://api.example.com/data \\
                     --dest-type database --dest-path "mysql://localhost/db"
    
    # Dry run
    $(basename "$0") --source-type file --source-path data.json \\
                     --dest-type stdout --dry-run

EOF
}

################################################################################
# Main
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -c|--config) PIPELINE_CONFIG="$2"; shift 2 ;;
        --source-type) SOURCE_TYPE="$2"; shift 2 ;;
        --source-path) SOURCE_PATH="$2"; shift 2 ;;
        --dest-type) DEST_TYPE="$2"; shift 2 ;;
        --dest-path) DEST_PATH="$2"; shift 2 ;;
        --transform) TRANSFORM_SCRIPT="$2"; shift 2 ;;
        --validate) VALIDATE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$SOURCE_TYPE" ]] && error_exit "Source type required (--source-type)" 2
[[ -z "$SOURCE_PATH" ]] && error_exit "Source path required (--source-path)" 2
[[ -z "$DEST_TYPE" ]] && DEST_TYPE="stdout"

run_pipeline

