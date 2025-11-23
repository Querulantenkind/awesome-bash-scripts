#!/bin/bash

################################################################################
# Script Name: data-validator.sh
# Description: Comprehensive data validation tool with schema validation, data
#              quality checks, constraint enforcement, and detailed reporting.
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

INPUT_FILE=""
SCHEMA_FILE=""
FORMAT=""
RULES=()
STRICT_MODE=false
OUTPUT_FILE=""
SHOW_ERRORS=false
VERBOSE=false

declare -i TOTAL_RECORDS=0
declare -i VALID_RECORDS=0
declare -i INVALID_RECORDS=0
declare -a ERRORS=()

################################################################################
# Validation Rules
################################################################################

validate_not_null() {
    local value="$1"
    [[ -n "$value" ]]
}

validate_numeric() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]
}

validate_integer() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+$ ]]
}

validate_email() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_url() {
    local value="$1"
    [[ "$value" =~ ^https?:// ]]
}

validate_date() {
    local value="$1"
    date -d "$value" &>/dev/null
}

validate_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    (( $(awk "BEGIN {print ($value >= $min && $value <= $max)}") ))
}

validate_length() {
    local value="$1"
    local min="$2"
    local max="$3"
    local len=${#value}
    (( len >= min && len <= max ))
}

validate_pattern() {
    local value="$1"
    local pattern="$2"
    [[ "$value" =~ $pattern ]]
}

validate_unique() {
    local value="$1"
    local -n seen_values=$2
    if [[ -n "${seen_values[$value]:-}" ]]; then
        return 1
    fi
    seen_values[$value]=1
    return 0
}

################################################################################
# JSON Validation
################################################################################

validate_json() {
    local file="$1"
    
    require_command jq jq
    
    print_header "JSON VALIDATION" 70
    echo
    
    # Syntax validation
    if ! jq empty "$file" 2>/dev/null; then
        error "Invalid JSON syntax"
        return 1
    fi
    success "JSON syntax valid"
    
    # Schema validation if provided
    if [[ -n "$SCHEMA_FILE" ]] && command_exists jsonschema; then
        if jsonschema -i "$file" "$SCHEMA_FILE" 2>/dev/null; then
            success "Schema validation passed"
        else
            error "Schema validation failed"
            return 1
        fi
    fi
    
    # Count records
    local is_array=$(jq -r 'if type == "array" then "true" else "false" end' "$file")
    if [[ "$is_array" == "true" ]]; then
        TOTAL_RECORDS=$(jq 'length' "$file")
        info "Total records: $TOTAL_RECORDS"
    fi
    
    # Data quality checks
    echo
    echo -e "${BOLD_CYAN}Data Quality Checks:${NC}"
    
    # Check for nulls
    local null_count=$(jq '[.. | select(. == null)] | length' "$file")
    printf "  Null values: %d\n" "$null_count"
    
    # Check data types
    if [[ "$is_array" == "true" ]]; then
        echo "  Type distribution:"
        jq -r '.[] | type' "$file" | sort | uniq -c | awk '{printf "    %-10s: %d\n", $2, $1}'
    fi
    
    return 0
}

################################################################################
# CSV Validation
################################################################################

validate_csv() {
    local file="$1"
    
    print_header "CSV VALIDATION" 70
    echo
    
    # Check file exists and not empty
    if [[ ! -s "$file" ]]; then
        error "CSV file is empty"
        return 1
    fi
    
    # Read header
    local header=$(head -1 "$file")
    local num_columns=$(echo "$header" | awk -F',' '{print NF}')
    info "Columns: $num_columns"
    echo "Header: $header"
    echo
    
    # Validate rows
    echo -e "${BOLD_CYAN}Row Validation:${NC}"
    
    local line_num=0
    TOTAL_RECORDS=0
    VALID_RECORDS=0
    INVALID_RECORDS=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip header
        [[ $line_num -eq 1 ]] && continue
        
        ((TOTAL_RECORDS++))
        
        # Count columns
        local row_columns=$(echo "$line" | awk -F',' '{print NF}')
        
        if [[ $row_columns -ne $num_columns ]]; then
            ((INVALID_RECORDS++))
            [[ "$SHOW_ERRORS" == true ]] && warning "Line $line_num: Column count mismatch (expected $num_columns, got $row_columns)"
            [[ "$STRICT_MODE" == true ]] && ERRORS+=("Line $line_num: Column mismatch")
        else
            ((VALID_RECORDS++))
        fi
        
        # Check for empty fields
        if echo "$line" | grep -q ",,"; then
            [[ "$SHOW_ERRORS" == true ]] && warning "Line $line_num: Empty fields detected"
        fi
    done < "$file"
    
    echo
    printf "Total records: %d\n" "$TOTAL_RECORDS"
    printf "Valid records: %d (%.1f%%)\n" "$VALID_RECORDS" "$(awk "BEGIN {printf \"%.1f\", ($VALID_RECORDS/$TOTAL_RECORDS)*100}")"
    printf "Invalid records: %d (%.1f%%)\n" "$INVALID_RECORDS" "$(awk "BEGIN {printf \"%.1f\", ($INVALID_RECORDS/$TOTAL_RECORDS)*100}")"
    
    [[ $INVALID_RECORDS -eq 0 ]] && success "All records valid" || warning "$INVALID_RECORDS invalid records found"
    
    return 0
}

################################################################################
# XML Validation
################################################################################

validate_xml() {
    local file="$1"
    
    print_header "XML VALIDATION" 70
    echo
    
    if command_exists xmllint; then
        if xmllint --noout "$file" 2>/dev/null; then
            success "XML syntax valid"
            
            # Schema validation if provided
            if [[ -n "$SCHEMA_FILE" ]]; then
                if xmllint --schema "$SCHEMA_FILE" --noout "$file" 2>/dev/null; then
                    success "XSD schema validation passed"
                else
                    error "XSD schema validation failed"
                    return 1
                fi
            fi
        else
            error "Invalid XML syntax"
            xmllint --noout "$file" 2>&1 | head -5
            return 1
        fi
    else
        warning "xmllint not found, skipping XML validation"
    fi
    
    return 0
}

################################################################################
# Main Validation Router
################################################################################

validate_file() {
    local file="$1"
    
    [[ ! -f "$file" ]] && error_exit "File not found: $file" 1
    
    # Auto-detect format
    if [[ -z "$FORMAT" ]]; then
        case "${file##*.}" in
            json) FORMAT="json" ;;
            csv) FORMAT="csv" ;;
            xml) FORMAT="xml" ;;
            yaml|yml) FORMAT="yaml" ;;
            *) FORMAT="text" ;;
        esac
    fi
    
    info "Validating $FORMAT file: $file"
    echo
    
    case "$FORMAT" in
        json)
            validate_json "$file"
            ;;
        csv)
            validate_csv "$file"
            ;;
        xml)
            validate_xml "$file"
            ;;
        *)
            warning "No specific validation available for format: $FORMAT"
            info "File size: $(du -h "$file" | cut -f1)"
            info "Line count: $(wc -l < "$file")"
            ;;
    esac
    
    # Print summary
    echo
    print_separator
    
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}✗ Validation failed with ${#ERRORS[@]} errors${NC}"
        if [[ "$SHOW_ERRORS" == true ]]; then
            echo
            echo "Errors:"
            for err in "${ERRORS[@]}"; do
                echo "  • $err"
            done
        fi
        return 1
    else
        echo -e "${GREEN}✓ Validation passed${NC}"
        return 0
    fi
}

################################################################################
# Usage
################################################################################

show_usage() {
    cat << EOF
${WHITE}Data Validator - Comprehensive Data Quality Checks${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show help message
    -i, --input FILE        Input file to validate
    -s, --schema FILE       Schema file for validation
    -f, --format FORMAT     Data format: json, csv, xml, yaml
    --strict                Strict mode (fail on any error)
    --show-errors           Show detailed error messages
    -o, --output FILE       Save validation report
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Validate JSON file
    $(basename "$0") -i data.json
    
    # Validate CSV with strict mode
    $(basename "$0") -i data.csv --strict --show-errors
    
    # Validate against schema
    $(basename "$0") -i data.json -s schema.json
    
    # Validate XML with XSD
    $(basename "$0") -i data.xml -s schema.xsd

${CYAN}Validation Checks:${NC}
    • Syntax validation
    • Schema compliance
    • Data type checking
    • Null value detection
    • Column count consistency (CSV)
    • Data quality metrics

EOF
}

################################################################################
# Main
################################################################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -i|--input) INPUT_FILE="$2"; shift 2 ;;
        -s|--schema) SCHEMA_FILE="$2"; shift 2 ;;
        -f|--format) FORMAT="$2"; shift 2 ;;
        --strict) STRICT_MODE=true; shift ;;
        --show-errors) SHOW_ERRORS=true; shift ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

[[ -z "$INPUT_FILE" ]] && error_exit "Input file required (-i)" 2

# Redirect output if specified
[[ -n "$OUTPUT_FILE" ]] && exec > "$OUTPUT_FILE"

validate_file "$INPUT_FILE"

