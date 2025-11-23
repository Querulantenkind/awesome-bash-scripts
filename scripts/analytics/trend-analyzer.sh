#!/bin/bash

################################################################################
# Script Name: trend-analyzer.sh
# Description: Time-series data trend analyzer that identifies patterns, anomalies,
#              and forecasts trends from historical data with statistical analysis
#              and visualization capabilities.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./trend-analyzer.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -f, --file FILE         Input data file (CSV or text)
#   -c, --column NUM        Column number to analyze (default: last)
#   -d, --delimiter CHAR    CSV delimiter (default: comma)
#   -t, --time-col NUM      Time/date column number
#   --analyze               Perform trend analysis
#   --forecast PERIODS      Forecast N periods ahead
#   --anomalies             Detect anomalies
#   --threshold SIGMA       Anomaly threshold (default: 3 sigma)
#   --moving-avg WINDOW     Calculate moving average
#   --growth                Calculate growth rates
#   --seasonality           Detect seasonality
#   --correlation FILE      Correlate with another dataset
#   --chart                 Generate ASCII chart
#   -o, --output FILE       Save results to file
#   --format FORMAT         Output format: text, json, csv
#   -v, --verbose           Verbose output
#
# Examples:
#   ./trend-analyzer.sh -f metrics.csv --analyze --chart
#   ./trend-analyzer.sh -f data.csv --forecast 10 --moving-avg 7
#   ./trend-analyzer.sh -f sales.csv --anomalies --threshold 2.5
#   ./trend-analyzer.sh -f metrics.csv --seasonality --format json
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
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
DATA_COLUMN=""
TIME_COLUMN=""
DELIMITER=","
DO_ANALYSIS=false
FORECAST_PERIODS=0
DETECT_ANOMALIES=false
ANOMALY_THRESHOLD=3
MOVING_AVG_WINDOW=0
CALC_GROWTH=false
DETECT_SEASONALITY=false
CORRELATION_FILE=""
GENERATE_CHART=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
VERBOSE=false

# Data storage
declare -a TIME_VALUES
declare -a DATA_VALUES
declare -a FORECAST_VALUES

################################################################################
# Data Loading
################################################################################

load_data() {
    local file="$1"
    
    [[ ! -f "$file" ]] && error_exit "File not found: $file" 1
    
    local line_num=0
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Parse CSV
        IFS="$DELIMITER" read -ra fields <<< "$line"
        
        # Determine column indices
        if [[ -z "$DATA_COLUMN" ]]; then
            DATA_COLUMN=${#fields[@]}
        fi
        
        if [[ -z "$TIME_COLUMN" ]]; then
            TIME_COLUMN=1
        fi
        
        # Extract values
        local time_val="${fields[$((TIME_COLUMN-1))]}"
        local data_val="${fields[$((DATA_COLUMN-1))]}"
        
        # Skip header if not numeric
        if ! [[ "$data_val" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
            [[ $line_num -eq 1 ]] && continue
            warning "Skipping non-numeric value at line $line_num: $data_val"
            continue
        fi
        
        TIME_VALUES+=("$time_val")
        DATA_VALUES+=("$data_val")
    done < "$file"
    
    local count=${#DATA_VALUES[@]}
    [[ $count -eq 0 ]] && error_exit "No data loaded from file" 1
    
    [[ "$VERBOSE" == true ]] && info "Loaded $count data points"
}

################################################################################
# Statistical Functions
################################################################################

calculate_stats() {
    local -n values=$1
    local count=${#values[@]}
    
    [[ $count -eq 0 ]] && return 1
    
    # Calculate mean
    local sum=0
    for val in "${values[@]}"; do
        sum=$(awk "BEGIN {print $sum + $val}")
    done
    local mean=$(awk "BEGIN {printf \"%.4f\", $sum / $count}")
    
    # Calculate variance and std dev
    local var_sum=0
    for val in "${values[@]}"; do
        local diff=$(awk "BEGIN {print $val - $mean}")
        var_sum=$(awk "BEGIN {print $var_sum + ($diff * $diff)}")
    done
    local variance=$(awk "BEGIN {printf \"%.4f\", $var_sum / $count}")
    local stddev=$(awk "BEGIN {printf \"%.4f\", sqrt($variance)}")
    
    # Find min and max
    local min=${values[0]}
    local max=${values[0]}
    for val in "${values[@]}"; do
        min=$(awk "BEGIN {print ($val < $min) ? $val : $min}")
        max=$(awk "BEGIN {print ($val > $max) ? $val : $max}")
    done
    
    echo "$mean $stddev $min $max"
}

moving_average() {
    local window=$1
    local -n in_values=$2
    local count=${#in_values[@]}
    
    declare -a ma_values
    
    for ((i=0; i<count; i++)); do
        local sum=0
        local window_count=0
        
        for ((j=0; j<window && i-j>=0; j++)); do
            sum=$(awk "BEGIN {print $sum + ${in_values[$((i-j))]}}")
            ((window_count++))
        done
        
        local avg=$(awk "BEGIN {printf \"%.4f\", $sum / $window_count}")
        ma_values+=("$avg")
    done
    
    # Return array
    echo "${ma_values[@]}"
}

calculate_trend() {
    local -n x_vals=$1
    local -n y_vals=$2
    local count=${#y_vals[@]}
    
    # Simple linear regression: y = mx + b
    local sum_x=0
    local sum_y=0
    local sum_xy=0
    local sum_x2=0
    
    for ((i=0; i<count; i++)); do
        local x=$i  # Use index as x if no time values
        local y=${y_vals[$i]}
        
        sum_x=$(awk "BEGIN {print $sum_x + $x}")
        sum_y=$(awk "BEGIN {print $sum_y + $y}")
        sum_xy=$(awk "BEGIN {print $sum_xy + ($x * $y)}")
        sum_x2=$(awk "BEGIN {print $sum_x2 + ($x * $x)}")
    done
    
    # Calculate slope and intercept
    local n=$count
    local slope=$(awk "BEGIN {printf \"%.6f\", ($n * $sum_xy - $sum_x * $sum_y) / ($n * $sum_x2 - $sum_x * $sum_x)}")
    local intercept=$(awk "BEGIN {printf \"%.6f\", ($sum_y - $slope * $sum_x) / $n}")
    
    echo "$slope $intercept"
}

detect_anomalies_fn() {
    local threshold=$1
    local -n values=$2
    local -n timestamps=$3
    
    # Calculate stats
    read -r mean stddev min max <<< "$(calculate_stats values)"
    
    local lower_bound=$(awk "BEGIN {print $mean - ($threshold * $stddev)}")
    local upper_bound=$(awk "BEGIN {print $mean + ($threshold * $stddev)}")
    
    echo -e "${BOLD_CYAN}Anomaly Detection (${threshold}σ):${NC}"
    echo "Mean: $mean, StdDev: $stddev"
    echo "Bounds: [$lower_bound, $upper_bound]"
    echo
    
    local anomaly_count=0
    for ((i=0; i<${#values[@]}; i++)); do
        local val=${values[$i]}
        local time=${timestamps[$i]}
        
        if (( $(awk "BEGIN {print ($val < $lower_bound || $val > $upper_bound) ? 1 : 0}") )); then
            echo -e "${RED}Anomaly at $time: $val${NC}"
            ((anomaly_count++))
        fi
    done
    
    echo
    echo "Total anomalies detected: $anomaly_count"
}

################################################################################
# Analysis Functions
################################################################################

perform_analysis() {
    print_header "TREND ANALYSIS" 70
    echo
    
    local count=${#DATA_VALUES[@]}
    
    # Basic statistics
    echo -e "${BOLD_CYAN}Descriptive Statistics:${NC}"
    read -r mean stddev min max <<< "$(calculate_stats DATA_VALUES)"
    
    printf "  Sample Size: %d\n" "$count"
    printf "  Mean:        %.4f\n" "$mean"
    printf "  Std Dev:     %.4f\n" "$stddev"
    printf "  Min:         %.4f\n" "$min"
    printf "  Max:         %.4f\n" "$max"
    printf "  Range:       %.4f\n" "$(awk "BEGIN {print $max - $min}")"
    echo
    
    # Trend calculation
    echo -e "${BOLD_CYAN}Trend Analysis:${NC}"
    read -r slope intercept <<< "$(calculate_trend TIME_VALUES DATA_VALUES)"
    
    printf "  Slope:       %.6f\n" "$slope"
    printf "  Intercept:   %.6f\n" "$intercept"
    
    if (( $(awk "BEGIN {print ($slope > 0.001) ? 1 : 0}") )); then
        echo -e "  Direction:   ${GREEN}↑ Increasing${NC}"
    elif (( $(awk "BEGIN {print ($slope < -0.001) ? 1 : 0}") )); then
        echo -e "  Direction:   ${RED}↓ Decreasing${NC}"
    else
        echo -e "  Direction:   ${YELLOW}→ Stable${NC}"
    fi
    
    # Growth rate (first to last)
    local first=${DATA_VALUES[0]}
    local last=${DATA_VALUES[$((count-1))]}
    local growth=$(awk "BEGIN {printf \"%.2f\", (($last - $first) / $first) * 100}")
    printf "  Total Growth: %.2f%%\n" "$growth"
    echo
    
    # Volatility
    echo -e "${BOLD_CYAN}Volatility:${NC}"
    local cv=$(awk "BEGIN {printf \"%.2f\", ($stddev / $mean) * 100}")
    printf "  Coefficient of Variation: %.2f%%\n" "$cv"
    
    if (( $(awk "BEGIN {print ($cv < 10) ? 1 : 0}") )); then
        echo "  Assessment: Low volatility"
    elif (( $(awk "BEGIN {print ($cv < 30) ? 1 : 0}") )); then
        echo "  Assessment: Moderate volatility"
    else
        echo "  Assessment: High volatility"
    fi
}

forecast_trend() {
    local periods=$1
    
    print_header "TREND FORECAST" 70
    echo
    
    # Calculate trend line
    read -r slope intercept <<< "$(calculate_trend TIME_VALUES DATA_VALUES)"
    
    echo "Forecasting $periods periods ahead..."
    echo
    
    local count=${#DATA_VALUES[@]}
    local last_val=${DATA_VALUES[$((count-1))]}
    
    echo -e "${BOLD_CYAN}Forecast:${NC}"
    for ((i=1; i<=periods; i++)); do
        local x=$((count + i - 1))
        local forecast=$(awk "BEGIN {printf \"%.4f\", $slope * $x + $intercept}")
        
        printf "  Period +%d: %.4f\n" "$i" "$forecast"
        FORECAST_VALUES+=("$forecast")
    done
    echo
    
    # Forecast confidence (simple approach)
    read -r mean stddev min max <<< "$(calculate_stats DATA_VALUES)"
    local margin=$(awk "BEGIN {printf \"%.4f\", 1.96 * $stddev}")
    
    echo -e "${BOLD_CYAN}95% Confidence Intervals:${NC}"
    for ((i=1; i<=periods; i++)); do
        local forecast=${FORECAST_VALUES[$((i-1))]}
        local lower=$(awk "BEGIN {printf \"%.4f\", $forecast - $margin}")
        local upper=$(awk "BEGIN {printf \"%.4f\", $forecast + $margin}")
        
        printf "  Period +%d: [%.4f, %.4f]\n" "$i" "$lower" "$upper"
    done
}

calculate_growth_rates() {
    print_header "GROWTH RATE ANALYSIS" 70
    echo
    
    echo -e "${BOLD_CYAN}Period-over-Period Growth Rates:${NC}"
    
    local prev=${DATA_VALUES[0]}
    printf "  Period 1: %.4f (baseline)\n" "$prev"
    
    for ((i=1; i<${#DATA_VALUES[@]}; i++)); do
        local curr=${DATA_VALUES[$i]}
        local growth=$(awk "BEGIN {printf \"%.2f\", (($curr - $prev) / $prev) * 100}")
        
        if (( $(awk "BEGIN {print ($growth > 0) ? 1 : 0}") )); then
            echo -e "  Period $((i+1)): %.4f (${GREEN}+%.2f%%${NC})\n" "$curr" "$growth"
        else
            echo -e "  Period $((i+1)): %.4f (${RED}%.2f%%${NC})\n" "$curr" "$growth"
        fi
        
        prev=$curr
    done
}

detect_seasonality_fn() {
    print_header "SEASONALITY DETECTION" 70
    echo
    
    local count=${#DATA_VALUES[@]}
    
    # Try common periods: 7, 30, 12 (daily, monthly, yearly patterns)
    for period in 7 12 24 30; do
        [[ $count -lt $((period * 2)) ]] && continue
        
        local autocorr=0
        local valid_pairs=0
        
        for ((i=0; i<count-period; i++)); do
            local val1=${DATA_VALUES[$i]}
            local val2=${DATA_VALUES[$((i+period))]}
            
            autocorr=$(awk "BEGIN {print $autocorr + ($val1 * $val2)}")
            ((valid_pairs++))
        done
        
        [[ $valid_pairs -gt 0 ]] && autocorr=$(awk "BEGIN {printf \"%.4f\", $autocorr / $valid_pairs}")
        
        echo "Period $period: Autocorrelation = $autocorr"
        
        if (( $(awk "BEGIN {print ($autocorr > 0.7) ? 1 : 0}") )); then
            echo -e "  ${GREEN}Strong seasonality detected${NC}"
        elif (( $(awk "BEGIN {print ($autocorr > 0.4) ? 1 : 0}") )); then
            echo -e "  ${YELLOW}Moderate seasonality detected${NC}"
        fi
    done
}

################################################################################
# Visualization
################################################################################

generate_chart() {
    print_header "DATA VISUALIZATION" 70
    echo
    
    local -n values=$1
    local count=${#values[@]}
    local height=20
    local width=60
    
    # Find data range
    read -r mean stddev min max <<< "$(calculate_stats values)"
    
    local range=$(awk "BEGIN {print $max - $min}")
    [[ $(awk "BEGIN {print ($range == 0) ? 1 : 0}") -eq 1 ]] && range=1
    
    # Create chart
    for ((row=height; row>=0; row--)); do
        local y_val=$(awk "BEGIN {printf \"%.2f\", $min + ($range * $row / $height)}")
        printf "%8.2f │" "$y_val"
        
        for ((col=0; col<width && col<count; col++)); do
            local idx=$((col * count / width))
            [[ $idx -ge $count ]] && idx=$((count-1))
            
            local val=${values[$idx]}
            local norm_val=$(awk "BEGIN {print int(($val - $min) / $range * $height + 0.5)}")
            
            if [[ $norm_val -eq $row ]]; then
                echo -n "●"
            elif [[ $norm_val -gt $row ]]; then
                echo -n "│"
            else
                echo -n " "
            fi
        done
        echo
    done
    
    # X-axis
    echo -n "         └"
    for ((col=0; col<width; col++)); do
        echo -n "─"
    done
    echo
    
    # Legend
    echo
    echo "Data points: $count"
    echo "Range: [$min, $max]"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Trend Analyzer - Time-Series Data Analysis${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -f, --file FILE         Input data file (CSV or text)
    -c, --column NUM        Column number to analyze (default: last)
    -d, --delimiter CHAR    CSV delimiter (default: comma)
    -t, --time-col NUM      Time/date column number
    --analyze               Perform trend analysis
    --forecast PERIODS      Forecast N periods ahead
    --anomalies             Detect anomalies
    --threshold SIGMA       Anomaly threshold (default: 3 sigma)
    --moving-avg WINDOW     Calculate moving average
    --growth                Calculate growth rates
    --seasonality           Detect seasonality
    --correlation FILE      Correlate with another dataset
    --chart                 Generate ASCII chart
    -o, --output FILE       Save results to file
    --format FORMAT         Output format: text, json, csv
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Complete trend analysis
    $(basename "$0") -f metrics.csv --analyze --chart
    
    # Forecast future values
    $(basename "$0") -f data.csv --forecast 10 --moving-avg 7
    
    # Detect anomalies
    $(basename "$0") -f sales.csv --anomalies --threshold 2.5
    
    # Seasonality detection
    $(basename "$0") -f metrics.csv --seasonality --format json
    
    # Growth rate analysis
    $(basename "$0") -f revenue.csv --growth --chart

${CYAN}Analysis Types:${NC}
    --analyze      Descriptive statistics and trend direction
    --forecast     Linear trend forecasting with confidence intervals
    --anomalies    Statistical outlier detection
    --growth       Period-over-period growth rates
    --seasonality  Detect repeating patterns
    --chart        ASCII visualization

${CYAN}Input Format:${NC}
    CSV files with numeric data in columns
    First row can be headers (will be skipped if non-numeric)
    
    Example:
    timestamp,value
    2024-01-01,100
    2024-01-02,105
    2024-01-03,98

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
        -f|--file)
            [[ -z "${2:-}" ]] && error_exit "File required" 2
            INPUT_FILE="$2"
            shift 2
            ;;
        -c|--column)
            [[ -z "${2:-}" ]] && error_exit "Column required" 2
            DATA_COLUMN="$2"
            shift 2
            ;;
        -d|--delimiter)
            [[ -z "${2:-}" ]] && error_exit "Delimiter required" 2
            DELIMITER="$2"
            shift 2
            ;;
        -t|--time-col)
            [[ -z "${2:-}" ]] && error_exit "Time column required" 2
            TIME_COLUMN="$2"
            shift 2
            ;;
        --analyze)
            DO_ANALYSIS=true
            shift
            ;;
        --forecast)
            [[ -z "${2:-}" ]] && error_exit "Forecast periods required" 2
            FORECAST_PERIODS="$2"
            shift 2
            ;;
        --anomalies)
            DETECT_ANOMALIES=true
            shift
            ;;
        --threshold)
            [[ -z "${2:-}" ]] && error_exit "Threshold required" 2
            ANOMALY_THRESHOLD="$2"
            shift 2
            ;;
        --moving-avg)
            [[ -z "${2:-}" ]] && error_exit "Window size required" 2
            MOVING_AVG_WINDOW="$2"
            shift 2
            ;;
        --growth)
            CALC_GROWTH=true
            shift
            ;;
        --seasonality)
            DETECT_SEASONALITY=true
            shift
            ;;
        --correlation)
            [[ -z "${2:-}" ]] && error_exit "Correlation file required" 2
            CORRELATION_FILE="$2"
            shift 2
            ;;
        --chart)
            GENERATE_CHART=true
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
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

# Validate inputs
[[ -z "$INPUT_FILE" ]] && error_exit "Input file required (-f)" 2

# Redirect output if needed
[[ -n "$OUTPUT_FILE" ]] && exec > "$OUTPUT_FILE"

# Load data
load_data "$INPUT_FILE"

# Perform requested analyses
[[ "$DO_ANALYSIS" == true ]] && perform_analysis && echo

[[ $FORECAST_PERIODS -gt 0 ]] && forecast_trend "$FORECAST_PERIODS" && echo

[[ "$DETECT_ANOMALIES" == true ]] && detect_anomalies_fn "$ANOMALY_THRESHOLD" DATA_VALUES TIME_VALUES && echo

[[ "$CALC_GROWTH" == true ]] && calculate_growth_rates && echo

[[ "$DETECT_SEASONALITY" == true ]] && detect_seasonality_fn && echo

[[ "$GENERATE_CHART" == true ]] && generate_chart DATA_VALUES && echo

# Default to analysis if nothing specified
if [[ "$DO_ANALYSIS" == false ]] && [[ $FORECAST_PERIODS -eq 0 ]] && [[ "$DETECT_ANOMALIES" == false ]] && [[ "$CALC_GROWTH" == false ]] && [[ "$DETECT_SEASONALITY" == false ]] && [[ "$GENERATE_CHART" == false ]]; then
    perform_analysis
    [[ $MOVING_AVG_WINDOW -gt 0 ]] && info "Use --chart to visualize the data"
fi

