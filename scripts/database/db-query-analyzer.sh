#!/bin/bash

################################################################################
# Script Name: db-query-analyzer.sh
# Description: Database query analyzer that identifies slow queries, analyzes
#              execution plans, and provides optimization recommendations for
#              MySQL and PostgreSQL databases.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./db-query-analyzer.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -t, --type TYPE         Database type: mysql, postgresql
#   -H, --host HOST         Database host (default: localhost)
#   -P, --port PORT         Database port
#   -u, --user USER         Database user
#   -p, --password PASS     Database password
#   -d, --database NAME     Database name
#   -q, --query "QUERY"     Analyze specific query
#   -f, --file FILE         Analyze queries from file
#   --slow-log FILE         Analyze MySQL slow query log
#   --threshold SECONDS     Slow query threshold (default: 1)
#   --explain               Show EXPLAIN output
#   --recommendations       Show optimization recommendations
#   --indexes               Suggest missing indexes
#   --statistics            Show table statistics
#   -o, --output FILE       Save results to file
#   --format FORMAT         Output format: text, json, csv
#   -v, --verbose           Verbose output
#
# Examples:
#   ./db-query-analyzer.sh -t mysql -u root -q "SELECT * FROM users WHERE email = 'test@example.com'"
#   ./db-query-analyzer.sh -t postgresql --slow-log /var/log/mysql/slow.log
#   ./db-query-analyzer.sh -t mysql --recommendations --indexes
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Connection error
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

DB_TYPE=""
DB_HOST="localhost"
DB_PORT=""
DB_USER=""
DB_PASSWORD=""
DB_NAME=""

QUERY=""
QUERY_FILE=""
SLOW_LOG=""
THRESHOLD=1
SHOW_EXPLAIN=false
SHOW_RECOMMENDATIONS=false
SUGGEST_INDEXES=false
SHOW_STATISTICS=false
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
VERBOSE=false

# Analysis results
declare -a ISSUES=()
declare -a RECOMMENDATIONS=()

################################################################################
# MySQL Analysis
################################################################################

analyze_mysql_query() {
    local query="$1"
    
    local mysql_cmd="mysql -h $DB_HOST -P ${DB_PORT:-3306}"
    [[ -n "$DB_USER" ]] && mysql_cmd+=" -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=" -p$DB_PASSWORD"
    [[ -n "$DB_NAME" ]] && mysql_cmd+=" -D $DB_NAME"
    mysql_cmd+=" -e"
    
    print_header "MYSQL QUERY ANALYSIS" 70
    echo
    echo -e "${BOLD}Query:${NC}"
    echo "$query" | sed 's/^/  /'
    echo
    
    # EXPLAIN output
    if [[ "$SHOW_EXPLAIN" == true ]] || [[ "$SHOW_RECOMMENDATIONS" == true ]]; then
        echo -e "${BOLD_CYAN}EXPLAIN Output:${NC}"
        local explain_output=$($mysql_cmd "EXPLAIN $query" 2>&1)
        echo "$explain_output"
        echo
        
        # Analyze EXPLAIN output
        analyze_mysql_explain "$explain_output"
    fi
    
    # Query timing
    echo -e "${BOLD_CYAN}Execution Time:${NC}"
    local start_time=$(date +%s.%N)
    $mysql_cmd "$query" > /dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    echo "  ${duration}s"
    
    if (( $(echo "$duration > $THRESHOLD" | bc -l) )); then
        warning "Query exceeds slow query threshold (${THRESHOLD}s)"
    fi
    echo
    
    # Show recommendations
    if [[ "$SHOW_RECOMMENDATIONS" == true ]] && [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo -e "${BOLD_CYAN}Recommendations:${NC}"
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo "  • $rec"
        done
        echo
    fi
}

analyze_mysql_explain() {
    local explain_output="$1"
    
    # Check for full table scans
    if echo "$explain_output" | grep -q "ALL"; then
        ISSUES+=("Full table scan detected")
        RECOMMENDATIONS+=("Consider adding indexes to avoid full table scan")
    fi
    
    # Check for filesort
    if echo "$explain_output" | grep -q "Using filesort"; then
        ISSUES+=("Using filesort")
        RECOMMENDATIONS+=("Consider adding index for ORDER BY clause")
    fi
    
    # Check for temporary table
    if echo "$explain_output" | grep -q "Using temporary"; then
        ISSUES+=("Using temporary table")
        RECOMMENDATIONS+=("Consider optimizing JOIN or GROUP BY clause")
    fi
    
    # Check for large rows examined
    local rows=$(echo "$explain_output" | awk '{print $9}' | tail -1)
    if [[ "$rows" =~ ^[0-9]+$ ]] && [[ $rows -gt 10000 ]]; then
        ISSUES+=("Large number of rows examined: $rows")
        RECOMMENDATIONS+=("Consider adding WHERE clause or index to reduce rows examined")
    fi
    
    # Check for missing indexes
    if echo "$explain_output" | grep -q "NULL" | grep -q "key"; then
        ISSUES+=("No index used")
        RECOMMENDATIONS+=("Add appropriate index for better performance")
    fi
}

analyze_mysql_slow_log() {
    local log_file="$1"
    
    if [[ ! -f "$log_file" ]]; then
        error_exit "Slow log file not found: $log_file" 1
    fi
    
    print_header "MYSQL SLOW QUERY LOG ANALYSIS" 70
    echo
    echo "Log file: $log_file"
    echo
    
    # Extract slow queries
    echo -e "${BOLD_CYAN}Top 10 Slowest Queries:${NC}"
    
    # Parse slow log (simplified)
    grep "Query_time" "$log_file" | head -20 | while read -r line; do
        echo "  $line"
    done
    
    echo
    echo -e "${BOLD_CYAN}Most Common Slow Queries:${NC}"
    grep "SELECT\|UPDATE\|INSERT\|DELETE" "$log_file" | \
        sed 's/[0-9]\+/N/g' | \
        sort | uniq -c | sort -rn | head -10
}

suggest_mysql_indexes() {
    local mysql_cmd="mysql -h $DB_HOST -P ${DB_PORT:-3306}"
    [[ -n "$DB_USER" ]] && mysql_cmd+=" -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=" -p$DB_PASSWORD"
    [[ -n "$DB_NAME" ]] && mysql_cmd+=" -D $DB_NAME"
    mysql_cmd+=" -e"
    
    print_header "INDEX ANALYSIS" 70
    echo
    
    # Tables without primary key
    echo -e "${BOLD_CYAN}Tables Without Primary Key:${NC}"
    $mysql_cmd "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_TYPE = 'BASE TABLE' AND TABLE_NAME NOT IN (SELECT TABLE_NAME FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_TYPE = 'PRIMARY KEY' AND TABLE_SCHEMA = '$DB_NAME');" 2>/dev/null || echo "None"
    echo
    
    # Tables with large number of rows but no index
    echo -e "${BOLD_CYAN}Large Tables Without Indexes:${NC}"
    $mysql_cmd "SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_ROWS > 1000 AND TABLE_NAME NOT IN (SELECT DISTINCT TABLE_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$DB_NAME');" 2>/dev/null || echo "None"
    echo
    
    # Unused indexes
    echo -e "${BOLD_CYAN}Potentially Unused Indexes:${NC}"
    $mysql_cmd "SELECT object_schema, object_name, index_name FROM performance_schema.table_io_waits_summary_by_index_usage WHERE index_name IS NOT NULL AND count_star = 0 AND object_schema = '$DB_NAME' ORDER BY object_schema, object_name;" 2>/dev/null || echo "Performance schema not available"
}

show_mysql_statistics() {
    local mysql_cmd="mysql -h $DB_HOST -P ${DB_PORT:-3306}"
    [[ -n "$DB_USER" ]] && mysql_cmd+=" -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=" -p$DB_PASSWORD"
    [[ -n "$DB_NAME" ]] && mysql_cmd+=" -D $DB_NAME"
    mysql_cmd+=" -e"
    
    print_header "TABLE STATISTICS" 70
    echo
    
    echo -e "${BOLD_CYAN}Table Sizes:${NC}"
    $mysql_cmd "SELECT TABLE_NAME, ROUND(((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024), 2) AS 'Size (MB)', TABLE_ROWS FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' ORDER BY (DATA_LENGTH + INDEX_LENGTH) DESC;" 2>/dev/null
    echo
    
    echo -e "${BOLD_CYAN}Index Sizes:${NC}"
    $mysql_cmd "SELECT TABLE_NAME, INDEX_NAME, ROUND(STAT_VALUE * @@innodb_page_size / 1024 / 1024, 2) AS 'Size (MB)' FROM mysql.innodb_index_stats WHERE database_name = '$DB_NAME' AND stat_name = 'size' ORDER BY STAT_VALUE DESC LIMIT 10;" 2>/dev/null || echo "Statistics not available"
}

################################################################################
# PostgreSQL Analysis
################################################################################

analyze_postgresql_query() {
    local query="$1"
    
    local psql_cmd="psql -h $DB_HOST -p ${DB_PORT:-5432}"
    [[ -n "$DB_USER" ]] && psql_cmd+=" -U $DB_USER"
    [[ -n "$DB_NAME" ]] && psql_cmd+=" -d $DB_NAME"
    psql_cmd+=" -c"
    
    print_header "POSTGRESQL QUERY ANALYSIS" 70
    echo
    echo -e "${BOLD}Query:${NC}"
    echo "$query" | sed 's/^/  /'
    echo
    
    # EXPLAIN ANALYZE
    if [[ "$SHOW_EXPLAIN" == true ]] || [[ "$SHOW_RECOMMENDATIONS" == true ]]; then
        echo -e "${BOLD_CYAN}EXPLAIN ANALYZE Output:${NC}"
        local explain_output=$($psql_cmd "EXPLAIN ANALYZE $query" 2>&1)
        echo "$explain_output"
        echo
        
        # Analyze EXPLAIN output
        analyze_postgresql_explain "$explain_output"
    fi
    
    # Show recommendations
    if [[ "$SHOW_RECOMMENDATIONS" == true ]] && [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo -e "${BOLD_CYAN}Recommendations:${NC}"
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo "  • $rec"
        done
        echo
    fi
}

analyze_postgresql_explain() {
    local explain_output="$1"
    
    # Check for sequential scan
    if echo "$explain_output" | grep -q "Seq Scan"; then
        ISSUES+=("Sequential scan detected")
        RECOMMENDATIONS+=("Consider adding index to improve performance")
    fi
    
    # Check for high execution time
    if echo "$explain_output" | grep -q "Execution Time:"; then
        local exec_time=$(echo "$explain_output" | grep "Execution Time:" | awk '{print $3}')
        if (( $(echo "$exec_time > $THRESHOLD * 1000" | bc -l) )); then
            ISSUES+=("High execution time: ${exec_time}ms")
        fi
    fi
    
    # Check for nested loops with high cost
    if echo "$explain_output" | grep -q "Nested Loop"; then
        local cost=$(echo "$explain_output" | grep "Nested Loop" | grep -o "cost=[0-9.]*" | cut -d= -f2 | head -1)
        if [[ -n "$cost" ]] && (( $(echo "$cost > 10000" | bc -l) )); then
            ISSUES+=("Expensive nested loop: cost=$cost")
            RECOMMENDATIONS+=("Consider optimizing JOIN conditions or adding indexes")
        fi
    fi
    
    # Check for sort operations
    if echo "$explain_output" | grep -q "Sort"; then
        RECOMMENDATIONS+=("Sort operation detected - consider adding index for ORDER BY")
    fi
}

suggest_postgresql_indexes() {
    local psql_cmd="psql -h $DB_HOST -p ${DB_PORT:-5432}"
    [[ -n "$DB_USER" ]] && psql_cmd+=" -U $DB_USER"
    [[ -n "$DB_NAME" ]] && psql_cmd+=" -d $DB_NAME"
    psql_cmd+=" -t -A -c"
    
    print_header "INDEX ANALYSIS" 70
    echo
    
    # Tables without primary key
    echo -e "${BOLD_CYAN}Tables Without Primary Key:${NC}"
    $psql_cmd "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename NOT IN (SELECT tablename FROM pg_indexes WHERE indexname LIKE '%_pkey');" 2>/dev/null || echo "None"
    echo
    
    # Unused indexes
    echo -e "${BOLD_CYAN}Potentially Unused Indexes:${NC}"
    $psql_cmd "SELECT schemaname, tablename, indexname FROM pg_stat_user_indexes WHERE idx_scan = 0 AND schemaname = 'public' ORDER BY pg_relation_size(indexrelid) DESC;" 2>/dev/null || echo "None"
    echo
    
    # Missing indexes (tables with sequential scans)
    echo -e "${BOLD_CYAN}Tables With High Sequential Scans:${NC}"
    $psql_cmd "SELECT schemaname, tablename, seq_scan, seq_tup_read FROM pg_stat_user_tables WHERE seq_scan > 100 ORDER BY seq_scan DESC LIMIT 10;" 2>/dev/null
}

show_postgresql_statistics() {
    local psql_cmd="psql -h $DB_HOST -p ${DB_PORT:-5432}"
    [[ -n "$DB_USER" ]] && psql_cmd+=" -U $DB_USER"
    [[ -n "$DB_NAME" ]] && psql_cmd+=" -d $DB_NAME"
    psql_cmd+=" -c"
    
    print_header "TABLE STATISTICS" 70
    echo
    
    echo -e "${BOLD_CYAN}Table Sizes:${NC}"
    $psql_cmd "SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;" 2>/dev/null
    echo
    
    echo -e "${BOLD_CYAN}Index Sizes:${NC}"
    $psql_cmd "SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) AS size FROM pg_stat_user_indexes ORDER BY pg_relation_size(indexrelid) DESC LIMIT 10;" 2>/dev/null
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Database Query Analyzer - SQL Query Performance Analysis${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -t, --type TYPE         Database type: mysql, postgresql
    -H, --host HOST         Database host (default: localhost)
    -P, --port PORT         Database port
    -u, --user USER         Database user
    -p, --password PASS     Database password
    -d, --database NAME     Database name
    -q, --query "QUERY"     Analyze specific query
    -f, --file FILE         Analyze queries from file
    --slow-log FILE         Analyze slow query log (MySQL)
    --threshold SECONDS     Slow query threshold (default: 1)
    --explain               Show EXPLAIN output
    --recommendations       Show optimization recommendations
    --indexes               Suggest missing indexes
    --statistics            Show table statistics
    -o, --output FILE       Save results to file
    --format FORMAT         Output format: text, json, csv
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Analyze specific query
    $(basename "$0") -t mysql -u root -d mydb -q "SELECT * FROM users WHERE email = 'test@example.com'" --explain
    
    # Get optimization recommendations
    $(basename "$0") -t postgresql -u postgres -d mydb -q "SELECT * FROM orders WHERE user_id = 123" --recommendations
    
    # Analyze slow query log
    $(basename "$0") -t mysql --slow-log /var/log/mysql/slow.log
    
    # Suggest missing indexes
    $(basename "$0") -t mysql -u root -d mydb --indexes
    
    # Show table statistics
    $(basename "$0") -t postgresql -u postgres -d mydb --statistics

${CYAN}Features:${NC}
    • EXPLAIN plan analysis
    • Slow query detection
    • Index recommendations
    • Query optimization suggestions
    • Table and index statistics
    • Slow query log parsing (MySQL)

${CYAN}Common Issues Detected:${NC}
    • Full table scans
    • Missing indexes
    • Inefficient JOINs
    • Using filesort
    • Using temporary tables
    • High execution time
    • Large result sets

${CYAN}Dependencies:${NC}
    MySQL:      mysql-client
    PostgreSQL: postgresql-client

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
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "Database type required" 2
            DB_TYPE="$2"
            shift 2
            ;;
        -H|--host)
            [[ -z "${2:-}" ]] && error_exit "Host required" 2
            DB_HOST="$2"
            shift 2
            ;;
        -P|--port)
            [[ -z "${2:-}" ]] && error_exit "Port required" 2
            DB_PORT="$2"
            shift 2
            ;;
        -u|--user)
            [[ -z "${2:-}" ]] && error_exit "User required" 2
            DB_USER="$2"
            shift 2
            ;;
        -p|--password)
            [[ -z "${2:-}" ]] && error_exit "Password required" 2
            DB_PASSWORD="$2"
            shift 2
            ;;
        -d|--database)
            [[ -z "${2:-}" ]] && error_exit "Database required" 2
            DB_NAME="$2"
            shift 2
            ;;
        -q|--query)
            [[ -z "${2:-}" ]] && error_exit "Query required" 2
            QUERY="$2"
            shift 2
            ;;
        -f|--file)
            [[ -z "${2:-}" ]] && error_exit "File required" 2
            QUERY_FILE="$2"
            shift 2
            ;;
        --slow-log)
            [[ -z "${2:-}" ]] && error_exit "Log file required" 2
            SLOW_LOG="$2"
            shift 2
            ;;
        --threshold)
            [[ -z "${2:-}" ]] && error_exit "Threshold required" 2
            THRESHOLD="$2"
            shift 2
            ;;
        --explain)
            SHOW_EXPLAIN=true
            shift
            ;;
        --recommendations)
            SHOW_RECOMMENDATIONS=true
            SHOW_EXPLAIN=true
            shift
            ;;
        --indexes)
            SUGGEST_INDEXES=true
            shift
            ;;
        --statistics)
            SHOW_STATISTICS=true
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

# Validate arguments
[[ -z "$DB_TYPE" ]] && error_exit "Database type required (-t)" 2

# Main execution
if [[ -n "$QUERY" ]]; then
    case "$DB_TYPE" in
        mysql)
            analyze_mysql_query "$QUERY"
            ;;
        postgresql)
            analyze_postgresql_query "$QUERY"
            ;;
        *)
            error_exit "Unsupported database type: $DB_TYPE" 2
            ;;
    esac
elif [[ -n "$SLOW_LOG" ]]; then
    analyze_mysql_slow_log "$SLOW_LOG"
elif [[ "$SUGGEST_INDEXES" == true ]]; then
    case "$DB_TYPE" in
        mysql)
            suggest_mysql_indexes
            ;;
        postgresql)
            suggest_postgresql_indexes
            ;;
    esac
elif [[ "$SHOW_STATISTICS" == true ]]; then
    case "$DB_TYPE" in
        mysql)
            show_mysql_statistics
            ;;
        postgresql)
            show_postgresql_statistics
            ;;
    esac
else
    error_exit "Please specify a query (-q), file (-f), or action (--indexes, --statistics)" 2
fi
