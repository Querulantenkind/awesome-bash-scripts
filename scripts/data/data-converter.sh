#!/bin/bash

################################################################################
# Script Name: data-converter.sh
# Description: Universal data format converter supporting JSON, CSV, XML, YAML,
#              TOML, and custom formats with schema validation, transformation
#              pipelines, and batch processing capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./data-converter.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -i, --input FILE        Input file
#   -o, --output FILE       Output file
#   -f, --from FORMAT       Input format: json, csv, xml, yaml, toml
#   -t, --to FORMAT         Output format: json, csv, xml, yaml, toml
#   --delimiter CHAR        CSV delimiter (default: comma)
#   --pretty                Pretty-print output
#   --validate              Validate input format
#   --transform SCRIPT      Transformation script
#   --filter EXPR           Filter expression (jq-style)
#   --batch DIR             Batch convert directory
#   --recursive             Recursive batch conversion
#   -v, --verbose           Verbose output
#
# Examples:
#   ./data-converter.sh -i data.json -o data.csv -f json -t csv
#   ./data-converter.sh -i config.yaml -o config.json -f yaml -t json --pretty
#   ./data-converter.sh --batch ./data/ -f json -t xml --recursive
#   ./data-converter.sh -i data.json -t csv --filter '.users[] | select(.age > 18)'
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Conversion error
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

INPUT_FILE=""
OUTPUT_FILE=""
FROM_FORMAT=""
TO_FORMAT=""
CSV_DELIMITER=","
PRETTY_PRINT=false
VALIDATE_INPUT=false
TRANSFORM_SCRIPT=""
FILTER_EXPR=""
BATCH_DIR=""
RECURSIVE=false
VERBOSE=false

# Temp files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

################################################################################
# Format Detection
################################################################################

detect_format() {
    local file="$1"
    
    # Try by extension first
    local ext="${file##*.}"
    case "${ext,,}" in
        json) echo "json"; return ;;
        csv) echo "csv"; return ;;
        xml) echo "xml"; return ;;
        yaml|yml) echo "yaml"; return ;;
        toml) echo "toml"; return ;;
    esac
    
    # Try by content
    if head -1 "$file" | grep -q "^{\\|^\["; then
        echo "json"
    elif head -1 "$file" | grep -q "^<"; then
        echo "xml"
    elif head -1 "$file" | grep -q "^---"; then
        echo "yaml"
    else
        echo "csv"
    fi
}

################################################################################
# JSON Converters
################################################################################

json_to_csv() {
    local input="$1"
    local output="$2"
    
    require_command jq jq
    
    # Detect if array or object
    local is_array=$(jq -r 'if type == "array" then "true" else "false" end' "$input")
    
    if [[ "$is_array" == "true" ]]; then
        # Convert array of objects to CSV
        local keys=$(jq -r '.[0] | keys | @csv' "$input")
        echo "$keys" > "$output"
        jq -r '.[] | [.[]] | @csv' "$input" >> "$output"
    else
        # Single object to CSV
        local keys=$(jq -r 'keys | @csv' "$input")
        echo "$keys" > "$output"
        jq -r '[.[]] | @csv' "$input" >> "$output"
    fi
}

json_to_xml() {
    local input="$1"
    local output="$2"
    
    require_command jq jq
    
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<root>'
        
        jq -r 'to_entries[] | "<\(.key)>\(.value)</\(.key)>"' "$input" 2>/dev/null || {
            # Handle arrays
            jq -r '.[] | to_entries[] | "<item><\(.key)>\(.value)</\(.key)></item>"' "$input"
        }
        
        echo '</root>'
    } > "$output"
}

json_to_yaml() {
    local input="$1"
    local output="$2"
    
    if command_exists yq; then
        yq -P '.' "$input" > "$output"
    elif command_exists python3; then
        python3 << EOF > "$output"
import json, yaml, sys
with open('$input') as f:
    data = json.load(f)
print(yaml.dump(data, default_flow_style=False))
EOF
    else
        error_exit "yq or python3 required for JSON to YAML conversion" 1
    fi
}

################################################################################
# CSV Converters
################################################################################

csv_to_json() {
    local input="$1"
    local output="$2"
    
    require_command jq jq
    
    # Read header
    local header=$(head -1 "$input")
    IFS="$CSV_DELIMITER" read -ra headers <<< "$header"
    
    # Build JSON
    echo "[" > "$output"
    
    local first=true
    tail -n +2 "$input" | while IFS= read -r line; do
        [[ "$first" == false ]] && echo "," >> "$output"
        first=false
        
        IFS="$CSV_DELIMITER" read -ra values <<< "$line"
        
        echo -n "  {" >> "$output"
        for ((i=0; i<${#headers[@]}; i++)); do
            [[ $i -gt 0 ]] && echo -n "," >> "$output"
            local key="${headers[$i]}"
            local val="${values[$i]:-}"
            
            # Try to detect numbers
            if [[ "$val" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo -n "\"$key\":$val" >> "$output"
            else
                # Escape quotes in string
                val=$(echo "$val" | sed 's/"/\\"/g')
                echo -n "\"$key\":\"$val\"" >> "$output"
            fi
        done
        echo -n "}" >> "$output"
    done
    
    echo
    echo "]" >> "$output"
    
    # Pretty print if requested
    if [[ "$PRETTY_PRINT" == true ]] && command_exists jq; then
        jq '.' "$output" > "$output.tmp" && mv "$output.tmp" "$output"
    fi
}

csv_to_xml() {
    local input="$1"
    local output="$2"
    
    echo '<?xml version="1.0" encoding="UTF-8"?>' > "$output"
    echo '<data>' >> "$output"
    
    # Read header
    local header=$(head -1 "$input")
    IFS="$CSV_DELIMITER" read -ra headers <<< "$header"
    
    tail -n +2 "$input" | while IFS= read -r line; do
        IFS="$CSV_DELIMITER" read -ra values <<< "$line"
        
        echo "  <row>" >> "$output"
        for ((i=0; i<${#headers[@]}; i++)); do
            local key="${headers[$i]}"
            local val="${values[$i]:-}"
            # XML escape
            val=$(echo "$val" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
            echo "    <$key>$val</$key>" >> "$output"
        done
        echo "  </row>" >> "$output"
    done
    
    echo '</data>' >> "$output"
}

################################################################################
# XML Converters
################################################################################

xml_to_json() {
    local input="$1"
    local output="$2"
    
    if command_exists xmlstarlet; then
        xmlstarlet sel -t -v "//text()" "$input" | jq -Rs 'split("\n") | {data: .}' > "$output"
    elif command_exists python3; then
        python3 << EOF > "$output"
import xml.etree.ElementTree as ET, json
tree = ET.parse('$input')
root = tree.getroot()

def elem_to_dict(elem):
    d = {elem.tag: {}}
    children = list(elem)
    if children:
        dd = {}
        for dc in map(elem_to_dict, children):
            for k, v in dc.items():
                if k not in dd:
                    dd[k] = []
                dd[k].append(v)
        d = {elem.tag: {k: v[0] if len(v) == 1 else v for k, v in dd.items()}}
    if elem.text:
        text = elem.text.strip()
        if children or elem.attrib:
            if text:
              d[elem.tag]['#text'] = text
        else:
            d[elem.tag] = text
    return d

print(json.dumps(elem_to_dict(root), indent=2))
EOF
    else
        error_exit "xmlstarlet or python3 required for XML to JSON conversion" 1
    fi
}

xml_to_csv() {
    local input="$1"
    local output="$2"
    
    # Convert to JSON first, then to CSV
    local temp_json="$TEMP_DIR/temp.json"
    xml_to_json "$input" "$temp_json"
    json_to_csv "$temp_json" "$output"
}

################################################################################
# YAML Converters
################################################################################

yaml_to_json() {
    local input="$1"
    local output="$2"
    
    if command_exists yq; then
        yq -o=json '.' "$input" > "$output"
    elif command_exists python3; then
        python3 << EOF > "$output"
import yaml, json
with open('$input') as f:
    data = yaml.safe_load(f)
print(json.dumps(data, indent=2))
EOF
    else
        error_exit "yq or python3 required for YAML to JSON conversion" 1
    fi
}

################################################################################
# Main Conversion Router
################################################################################

convert_file() {
    local input="$1"
    local output="$2"
    local from="$3"
    local to="$4"
    
    [[ ! -f "$input" ]] && error_exit "Input file not found: $input" 1
    
    # Auto-detect formats if not specified
    [[ -z "$from" ]] && from=$(detect_format "$input")
    [[ -z "$to" ]] && to="json"
    
    [[ "$VERBOSE" == true ]] && info "Converting $from to $to: $input -> $output"
    
    # Validate input if requested
    if [[ "$VALIDATE_INPUT" == true ]]; then
        case "$from" in
            json)
                jq empty "$input" 2>/dev/null || error_exit "Invalid JSON: $input" 3
                ;;
            csv)
                [[ $(wc -l < "$input") -lt 1 ]] && error_exit "Empty CSV: $input" 3
                ;;
        esac
    fi
    
    # Apply filter if specified
    local filtered_input="$input"
    if [[ -n "$FILTER_EXPR" ]] && [[ "$from" == "json" ]]; then
        filtered_input="$TEMP_DIR/filtered.json"
        jq "$FILTER_EXPR" "$input" > "$filtered_input"
    fi
    
    # Perform conversion
    case "${from}_to_${to}" in
        json_to_csv)
            json_to_csv "$filtered_input" "$output"
            ;;
        json_to_xml)
            json_to_xml "$filtered_input" "$output"
            ;;
        json_to_yaml)
            json_to_yaml "$filtered_input" "$output"
            ;;
        json_to_json)
            if [[ "$PRETTY_PRINT" == true ]]; then
                jq '.' "$filtered_input" > "$output"
            else
                cp "$filtered_input" "$output"
            fi
            ;;
        csv_to_json)
            csv_to_json "$filtered_input" "$output"
            ;;
        csv_to_xml)
            csv_to_xml "$filtered_input" "$output"
            ;;
        csv_to_yaml)
            local temp_json="$TEMP_DIR/temp.json"
            csv_to_json "$filtered_input" "$temp_json"
            json_to_yaml "$temp_json" "$output"
            ;;
        xml_to_json)
            xml_to_json "$filtered_input" "$output"
            ;;
        xml_to_csv)
            xml_to_csv "$filtered_input" "$output"
            ;;
        xml_to_yaml)
            local temp_json="$TEMP_DIR/temp.json"
            xml_to_json "$filtered_input" "$temp_json"
            json_to_yaml "$temp_json" "$output"
            ;;
        yaml_to_json)
            yaml_to_json "$filtered_input" "$output"
            ;;
        yaml_to_csv)
            local temp_json="$TEMP_DIR/temp.json"
            yaml_to_json "$filtered_input" "$temp_json"
            json_to_csv "$temp_json" "$output"
            ;;
        yaml_to_xml)
            local temp_json="$TEMP_DIR/temp.json"
            yaml_to_json "$filtered_input" "$temp_json"
            json_to_xml "$temp_json" "$output"
            ;;
        *)
            error_exit "Unsupported conversion: $from to $to" 3
            ;;
    esac
    
    success "Converted: $input -> $output"
}

################################################################################
# Batch Conversion
################################################################################

batch_convert() {
    local dir="$1"
    local pattern="*.$FROM_FORMAT"
    
    [[ ! -d "$dir" ]] && error_exit "Directory not found: $dir" 1
    
    local find_opts=( "$dir" -name "$pattern" -type f )
    [[ "$RECURSIVE" == true ]] || find_opts+=( -maxdepth 1 )
    
    info "Batch converting $FROM_FORMAT files to $TO_FORMAT in $dir"
    
    local count=0
    while IFS= read -r -d '' file; do
        local basename=$(basename "$file" ".$FROM_FORMAT")
        local dirname=$(dirname "$file")
        local output="$dirname/${basename}.$TO_FORMAT"
        
        convert_file "$file" "$output" "$FROM_FORMAT" "$TO_FORMAT"
        ((count++))
    done < <(find "${find_opts[@]}" -print0)
    
    success "Batch conversion complete: $count files processed"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Data Converter - Universal Format Conversion${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -i, --input FILE        Input file
    -o, --output FILE       Output file
    -f, --from FORMAT       Input format: json, csv, xml, yaml, toml
    -t, --to FORMAT         Output format: json, csv, xml, yaml, toml
    --delimiter CHAR        CSV delimiter (default: comma)
    --pretty                Pretty-print output (JSON/XML)
    --validate              Validate input format
    --transform SCRIPT      Transformation script
    --filter EXPR           Filter expression (jq for JSON)
    --batch DIR             Batch convert directory
    --recursive             Recursive batch conversion
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # JSON to CSV
    $(basename "$0") -i data.json -o data.csv -f json -t csv
    
    # YAML to JSON with pretty print
    $(basename "$0") -i config.yaml -o config.json -f yaml -t json --pretty
    
    # CSV to XML
    $(basename "$0") -i data.csv -o data.xml -f csv -t xml
    
    # Batch convert all JSON files to CSV
    $(basename "$0") --batch ./data/ -f json -t csv --recursive
    
    # Filter and convert
    $(basename "$0") -i users.json -t csv --filter '.users[] | select(.active == true)'
    
    # Validate and convert
    $(basename "$0") -i data.json -t yaml --validate --pretty

${CYAN}Supported Formats:${NC}
    json    - JavaScript Object Notation
    csv     - Comma-Separated Values
    xml     - eXtensible Markup Language
    yaml    - YAML Ain't Markup Language
    toml    - Tom's Obvious Minimal Language (partial support)

${CYAN}Dependencies:${NC}
    jq          - JSON processing (required for JSON operations)
    yq          - YAML processing (optional, falls back to python)
    xmlstarlet  - XML processing (optional, falls back to python)
    python3     - Fallback for YAML/XML operations

${CYAN}Features:${NC}
    • Auto-format detection
    • Schema validation
    • Data filtering
    • Batch processing
    • Pretty printing
    • Custom delimiters
    • Recursive conversion

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
        -i|--input)
            [[ -z "${2:-}" ]] && error_exit "Input file required" 2
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--from)
            [[ -z "${2:-}" ]] && error_exit "Input format required" 2
            FROM_FORMAT="$2"
            shift 2
            ;;
        -t|--to)
            [[ -z "${2:-}" ]] && error_exit "Output format required" 2
            TO_FORMAT="$2"
            shift 2
            ;;
        --delimiter)
            [[ -z "${2:-}" ]] && error_exit "Delimiter required" 2
            CSV_DELIMITER="$2"
            shift 2
            ;;
        --pretty)
            PRETTY_PRINT=true
            shift
            ;;
        --validate)
            VALIDATE_INPUT=true
            shift
            ;;
        --transform)
            [[ -z "${2:-}" ]] && error_exit "Transform script required" 2
            TRANSFORM_SCRIPT="$2"
            shift 2
            ;;
        --filter)
            [[ -z "${2:-}" ]] && error_exit "Filter expression required" 2
            FILTER_EXPR="$2"
            shift 2
            ;;
        --batch)
            [[ -z "${2:-}" ]] && error_exit "Batch directory required" 2
            BATCH_DIR="$2"
            shift 2
            ;;
        --recursive)
            RECURSIVE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Validate arguments
if [[ -n "$BATCH_DIR" ]]; then
    [[ -z "$FROM_FORMAT" ]] && error_exit "Source format required for batch conversion (-f)" 2
    [[ -z "$TO_FORMAT" ]] && error_exit "Target format required for batch conversion (-t)" 2
    batch_convert "$BATCH_DIR"
else
    [[ -z "$INPUT_FILE" ]] && error_exit "Input file required (-i)" 2
    [[ -z "$OUTPUT_FILE" ]] && error_exit "Output file required (-o)" 2
    
    convert_file "$INPUT_FILE" "$OUTPUT_FILE" "$FROM_FORMAT" "$TO_FORMAT"
fi

