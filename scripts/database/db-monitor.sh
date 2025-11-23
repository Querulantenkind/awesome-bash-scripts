#!/bin/bash

################################################################################
# Script Name: db-monitor.sh
# Description: Database performance monitoring tool supporting MySQL, PostgreSQL,
#              MongoDB, and Redis. Monitors connections, queries, performance
#              metrics, and provides alerts and recommendations.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./db-monitor.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -t, --type TYPE         Database type: mysql, postgresql, mongodb, redis
#   -H, --host HOST         Database host (default: localhost)
#   -P, --port PORT         Database port
#   -u, --user USER         Database user
#   -p, --password PASS     Database password
#   -d, --database NAME     Database name
#   --interval SECONDS      Monitoring interval (default: 5)
#   --duration SECONDS      Monitoring duration (0 = infinite)
#   --connections           Monitor connections
#   --queries               Monitor queries
#   --performance           Monitor performance metrics
#   --slow-queries          Show slow queries
#   --locks                 Monitor locks
#   --replication           Monitor replication status
#   --alert-connections N   Alert when connections exceed N
#   --alert-slow-query S    Alert when query exceeds S seconds
#   -o, --output FILE       Save results to file
#   -f, --format FORMAT     Output format: text, json, csv
#   --once                  Run once and exit
#   -v, --verbose           Verbose output
#
# Examples:
#   ./db-monitor.sh -t mysql -u root -p password
#   ./db-monitor.sh -t postgresql --connections --queries
#   ./db-monitor.sh -t mongodb --performance --once
#   ./db-monitor.sh -t redis --interval 10 --alert-connections 100
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

INTERVAL=5
DURATION=0
MONITOR_CONNECTIONS=false
MONITOR_QUERIES=false
MONITOR_PERFORMANCE=false
MONITOR_SLOW_QUERIES=false
MONITOR_LOCKS=false
MONITOR_REPLICATION=false

ALERT_CONNECTIONS=""
ALERT_SLOW_QUERY=""
OUTPUT_FILE=""
OUTPUT_FORMAT="text"
RUN_ONCE=false
VERBOSE=false

# Default ports
declare -A DEFAULT_PORTS=(
    ["mysql"]="3306"
    ["postgresql"]="5432"
    ["mongodb"]="27017"
    ["redis"]="6379"
)

################################################################################
# Dependency Check
################################################################################

check_db_client() {
    local db_type="$1"
    
    case "$db_type" in
        mysql)
            require_command mysql mysql-client
            ;;
        postgresql)
            require_command psql postgresql-client
            ;;
        mongodb)
            if ! command_exists mongosh && ! command_exists mongo; then
                error_exit "MongoDB client required. Install: sudo apt install mongodb-clients" 3
            fi
            ;;
        redis)
            require_command redis-cli redis-tools
            ;;
    esac
}

################################################################################
# MySQL Monitoring
################################################################################

monitor_mysql() {
    local action="$1"
    
    local mysql_cmd="mysql -h $DB_HOST -P ${DB_PORT:-3306}"
    [[ -n "$DB_USER" ]] && mysql_cmd+=" -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mysql_cmd+=" -p$DB_PASSWORD"
    mysql_cmd+=" -e"
    
    case "$action" in
        connections)
            echo -e "${BOLD_CYAN}MySQL Connections:${NC}"
            $mysql_cmd "SHOW PROCESSLIST;" | awk 'NR>1 {print}' | head -20
            
            local active=$($mysql_cmd "SHOW PROCESSLIST;" | grep -c "^" || echo 0)
            local max=$($mysql_cmd "SHOW VARIABLES LIKE 'max_connections';" | awk 'NR>1 {print $2}')
            local usage=$(echo "scale=2; $active * 100 / $max" | bc)
            
            echo
            echo "Active: $active / $max (${usage}%)"
            
            if [[ -n "$ALERT_CONNECTIONS" ]] && [[ $active -gt $ALERT_CONNECTIONS ]]; then
                warning "Connection count exceeds threshold: $active > $ALERT_CONNECTIONS"
            fi
            ;;
            
        queries)
            echo -e "${BOLD_CYAN}MySQL Query Statistics:${NC}"
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Questions';" | awk 'NR>1 {print "Total Queries:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Queries';" | awk 'NR>1 {print "Total Commands:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Com_select';" | awk 'NR>1 {print "SELECT:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Com_insert';" | awk 'NR>1 {print "INSERT:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Com_update';" | awk 'NR>1 {print "UPDATE:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Com_delete';" | awk 'NR>1 {print "DELETE:", $2}'
            ;;
            
        performance)
            echo -e "${BOLD_CYAN}MySQL Performance Metrics:${NC}"
            
            # Uptime
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Uptime';" | awk 'NR>1 {print "Uptime:", $2, "seconds"}'
            
            # QPS
            local queries=$($mysql_cmd "SHOW GLOBAL STATUS LIKE 'Queries';" | awk 'NR>1 {print $2}')
            local uptime=$($mysql_cmd "SHOW GLOBAL STATUS LIKE 'Uptime';" | awk 'NR>1 {print $2}')
            local qps=$(echo "scale=2; $queries / $uptime" | bc)
            echo "Queries Per Second: $qps"
            
            # Buffer pool
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';" | awk 'NR>1 {print "Buffer Pool Reads:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';" | awk 'NR>1 {print "Disk Reads:", $2}'
            
            # Threads
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Threads_running';" | awk 'NR>1 {print "Threads Running:", $2}'
            $mysql_cmd "SHOW GLOBAL STATUS LIKE 'Threads_connected';" | awk 'NR>1 {print "Threads Connected:", $2}'
            ;;
            
        slow)
            echo -e "${BOLD_CYAN}MySQL Slow Queries:${NC}"
            
            local slow_log=$($mysql_cmd "SHOW VARIABLES LIKE 'slow_query_log';" | awk 'NR>1 {print $2}')
            local slow_time=$($mysql_cmd "SHOW VARIABLES LIKE 'long_query_time';" | awk 'NR>1 {print $2}')
            local slow_count=$($mysql_cmd "SHOW GLOBAL STATUS LIKE 'Slow_queries';" | awk 'NR>1 {print $2}')
            
            echo "Slow Query Log: $slow_log"
            echo "Long Query Time: ${slow_time}s"
            echo "Slow Queries: $slow_count"
            
            # Currently running slow queries
            echo
            echo "Currently Running Queries (>1s):"
            $mysql_cmd "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 50) FROM information_schema.PROCESSLIST WHERE TIME > 1 ORDER BY TIME DESC LIMIT 10;" | awk 'NR>1 {print}'
            ;;
            
        locks)
            echo -e "${BOLD_CYAN}MySQL Locks:${NC}"
            $mysql_cmd "SHOW OPEN TABLES WHERE In_use > 0;"
            ;;
            
        replication)
            echo -e "${BOLD_CYAN}MySQL Replication Status:${NC}"
            $mysql_cmd "SHOW SLAVE STATUS\G" || echo "Not a slave or no replication configured"
            ;;
    esac
}

################################################################################
# PostgreSQL Monitoring
################################################################################

monitor_postgresql() {
    local action="$1"
    
    local psql_cmd="psql -h $DB_HOST -p ${DB_PORT:-5432}"
    [[ -n "$DB_USER" ]] && psql_cmd+=" -U $DB_USER"
    [[ -n "$DB_NAME" ]] && psql_cmd+=" -d $DB_NAME" || psql_cmd+=" -d postgres"
    psql_cmd+=" -t -A -c"
    
    case "$action" in
        connections)
            echo -e "${BOLD_CYAN}PostgreSQL Connections:${NC}"
            $psql_cmd "SELECT count(*) as total, state FROM pg_stat_activity GROUP BY state;" 2>/dev/null
            
            echo
            $psql_cmd "SELECT pid, usename, application_name, client_addr, state, query_start FROM pg_stat_activity WHERE state != 'idle' LIMIT 10;" 2>/dev/null
            ;;
            
        queries)
            echo -e "${BOLD_CYAN}PostgreSQL Query Statistics:${NC}"
            $psql_cmd "SELECT datname, xact_commit, xact_rollback, blks_read, blks_hit FROM pg_stat_database WHERE datname NOT IN ('template0', 'template1');" 2>/dev/null
            ;;
            
        performance)
            echo -e "${BOLD_CYAN}PostgreSQL Performance Metrics:${NC}"
            
            # Cache hit ratio
            echo "Cache Hit Ratio:"
            $psql_cmd "SELECT sum(heap_blks_read) as heap_read, sum(heap_blks_hit) as heap_hit, sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) * 100 as ratio FROM pg_statio_user_tables;" 2>/dev/null
            
            # Database size
            echo
            echo "Database Sizes:"
            $psql_cmd "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname NOT IN ('template0', 'template1') ORDER BY pg_database_size(datname) DESC;" 2>/dev/null
            ;;
            
        slow)
            echo -e "${BOLD_CYAN}PostgreSQL Slow Queries:${NC}"
            $psql_cmd "SELECT pid, now() - pg_stat_activity.query_start AS duration, query FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds' AND state = 'active';" 2>/dev/null
            ;;
            
        locks)
            echo -e "${BOLD_CYAN}PostgreSQL Locks:${NC}"
            $psql_cmd "SELECT blocked_locks.pid AS blocked_pid, blocking_locks.pid AS blocking_pid, blocked_activity.usename AS blocked_user, blocking_activity.usename AS blocking_user FROM pg_catalog.pg_locks blocked_locks JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype WHERE NOT blocked_locks.granted;" 2>/dev/null || echo "No locks found"
            ;;
            
        replication)
            echo -e "${BOLD_CYAN}PostgreSQL Replication Status:${NC}"
            $psql_cmd "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "No replication configured"
            ;;
    esac
}

################################################################################
# MongoDB Monitoring
################################################################################

monitor_mongodb() {
    local action="$1"
    
    local mongo_client="mongosh"
    command_exists mongosh || mongo_client="mongo"
    
    local mongo_cmd="$mongo_client --host $DB_HOST --port ${DB_PORT:-27017} --quiet"
    [[ -n "$DB_USER" ]] && mongo_cmd+=" -u $DB_USER"
    [[ -n "$DB_PASSWORD" ]] && mongo_cmd+=" -p $DB_PASSWORD"
    
    case "$action" in
        connections)
            echo -e "${BOLD_CYAN}MongoDB Connections:${NC}"
            $mongo_cmd --eval "db.serverStatus().connections" 2>/dev/null
            ;;
            
        queries)
            echo -e "${BOLD_CYAN}MongoDB Query Statistics:${NC}"
            $mongo_cmd --eval "db.serverStatus().opcounters" 2>/dev/null
            ;;
            
        performance)
            echo -e "${BOLD_CYAN}MongoDB Performance Metrics:${NC}"
            $mongo_cmd --eval "printjson(db.serverStatus({metrics: 1}))" 2>/dev/null | grep -A 20 "metrics"
            ;;
            
        slow)
            echo -e "${BOLD_CYAN}MongoDB Slow Queries:${NC}"
            $mongo_cmd --eval "db.currentOp({\"secs_running\": {\$gt: 5}})" 2>/dev/null
            ;;
            
        replication)
            echo -e "${BOLD_CYAN}MongoDB Replication Status:${NC}"
            $mongo_cmd --eval "rs.status()" 2>/dev/null || echo "Not in replica set"
            ;;
    esac
}

################################################################################
# Redis Monitoring
################################################################################

monitor_redis() {
    local action="$1"
    
    local redis_cmd="redis-cli -h $DB_HOST -p ${DB_PORT:-6379}"
    [[ -n "$DB_PASSWORD" ]] && redis_cmd+=" -a $DB_PASSWORD"
    
    case "$action" in
        connections)
            echo -e "${BOLD_CYAN}Redis Connections:${NC}"
            $redis_cmd INFO clients 2>/dev/null
            ;;
            
        queries)
            echo -e "${BOLD_CYAN}Redis Command Statistics:${NC}"
            $redis_cmd INFO commandstats 2>/dev/null
            ;;
            
        performance)
            echo -e "${BOLD_CYAN}Redis Performance Metrics:${NC}"
            $redis_cmd INFO stats 2>/dev/null
            echo
            $redis_cmd INFO memory 2>/dev/null
            ;;
            
        replication)
            echo -e "${BOLD_CYAN}Redis Replication Status:${NC}"
            $redis_cmd INFO replication 2>/dev/null
            ;;
    esac
}

################################################################################
# Main Monitoring Loop
################################################################################

run_monitoring() {
    local start_time=$(date +%s)
    
    while true; do
        clear
        
        print_header "DATABASE MONITOR - ${DB_TYPE^^}" 70
        echo
        echo "Host: $DB_HOST:${DB_PORT:-${DEFAULT_PORTS[$DB_TYPE]}}"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        print_separator
        
        # Monitor based on selected options
        if [[ "$MONITOR_CONNECTIONS" == true ]] || [[ "$MONITOR_QUERIES" == false && "$MONITOR_PERFORMANCE" == false ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql connections ;;
                postgresql) monitor_postgresql connections ;;
                mongodb) monitor_mongodb connections ;;
                redis) monitor_redis connections ;;
            esac
            echo
        fi
        
        if [[ "$MONITOR_QUERIES" == true ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql queries ;;
                postgresql) monitor_postgresql queries ;;
                mongodb) monitor_mongodb queries ;;
                redis) monitor_redis queries ;;
            esac
            echo
        fi
        
        if [[ "$MONITOR_PERFORMANCE" == true ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql performance ;;
                postgresql) monitor_postgresql performance ;;
                mongodb) monitor_mongodb performance ;;
                redis) monitor_redis performance ;;
            esac
            echo
        fi
        
        if [[ "$MONITOR_SLOW_QUERIES" == true ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql slow ;;
                postgresql) monitor_postgresql slow ;;
                mongodb) monitor_mongodb slow ;;
            esac
            echo
        fi
        
        if [[ "$MONITOR_LOCKS" == true ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql locks ;;
                postgresql) monitor_postgresql locks ;;
            esac
            echo
        fi
        
        if [[ "$MONITOR_REPLICATION" == true ]]; then
            case "$DB_TYPE" in
                mysql) monitor_mysql replication ;;
                postgresql) monitor_postgresql replication ;;
                mongodb) monitor_mongodb replication ;;
                redis) monitor_redis replication ;;
            esac
            echo
        fi
        
        # Check duration
        if [[ "$RUN_ONCE" == true ]]; then
            break
        fi
        
        if [[ $DURATION -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            if [[ $elapsed -ge $DURATION ]]; then
                break
            fi
        fi
        
        sleep "$INTERVAL"
    done
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Database Monitor - Multi-Database Performance Monitoring${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -t, --type TYPE         Database type: mysql, postgresql, mongodb, redis
    -H, --host HOST         Database host (default: localhost)
    -P, --port PORT         Database port (auto-detect by type)
    -u, --user USER         Database user
    -p, --password PASS     Database password
    -d, --database NAME     Database name
    --interval SECONDS      Monitoring interval (default: 5)
    --duration SECONDS      Monitoring duration (0 = infinite)
    --connections           Monitor connections
    --queries               Monitor queries
    --performance           Monitor performance metrics
    --slow-queries          Show slow queries
    --locks                 Monitor locks
    --replication           Monitor replication status
    --alert-connections N   Alert when connections exceed N
    --alert-slow-query S    Alert when query exceeds S seconds
    -o, --output FILE       Save results to file
    -f, --format FORMAT     Output format: text, json, csv
    --once                  Run once and exit
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Monitor MySQL connections
    $(basename "$0") -t mysql -u root -p password --connections
    
    # Monitor PostgreSQL performance
    $(basename "$0") -t postgresql --performance --once
    
    # Monitor MongoDB with all metrics
    $(basename "$0") -t mongodb --connections --queries --performance
    
    # Monitor Redis with alerts
    $(basename "$0") -t redis --alert-connections 100
    
    # Continuous monitoring with interval
    $(basename "$0") -t mysql --interval 10 --performance

${CYAN}Supported Databases:${NC}
    mysql       MySQL/MariaDB (port 3306)
    postgresql  PostgreSQL (port 5432)
    mongodb     MongoDB (port 27017)
    redis       Redis (port 6379)

${CYAN}Monitoring Options:${NC}
    --connections   Active connections and connection pool
    --queries       Query statistics and counters
    --performance   Performance metrics and cache stats
    --slow-queries  Long-running queries
    --locks         Lock information
    --replication   Replication status (master/slave)

${CYAN}Dependencies:${NC}
    MySQL:      mysql-client
    PostgreSQL: postgresql-client
    MongoDB:    mongodb-clients (mongosh or mongo)
    Redis:      redis-tools

${CYAN}Notes:${NC}
    - Default monitoring shows connections if no options specified
    - Use --once for single snapshot
    - Password can also be set via environment variable
    - Some features require appropriate database permissions

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
        --interval)
            [[ -z "${2:-}" ]] && error_exit "Interval required" 2
            INTERVAL="$2"
            shift 2
            ;;
        --duration)
            [[ -z "${2:-}" ]] && error_exit "Duration required" 2
            DURATION="$2"
            shift 2
            ;;
        --connections)
            MONITOR_CONNECTIONS=true
            shift
            ;;
        --queries)
            MONITOR_QUERIES=true
            shift
            ;;
        --performance)
            MONITOR_PERFORMANCE=true
            shift
            ;;
        --slow-queries)
            MONITOR_SLOW_QUERIES=true
            shift
            ;;
        --locks)
            MONITOR_LOCKS=true
            shift
            ;;
        --replication)
            MONITOR_REPLICATION=true
            shift
            ;;
        --alert-connections)
            [[ -z "${2:-}" ]] && error_exit "Connection threshold required" 2
            ALERT_CONNECTIONS="$2"
            shift 2
            ;;
        --alert-slow-query)
            [[ -z "${2:-}" ]] && error_exit "Slow query threshold required" 2
            ALERT_SLOW_QUERY="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --once)
            RUN_ONCE=true
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
[[ -z "$DB_TYPE" ]] && error_exit "Database type required (-t)" 2

# Check database client
check_db_client "$DB_TYPE"

# Set default port if not specified
[[ -z "$DB_PORT" ]] && DB_PORT="${DEFAULT_PORTS[$DB_TYPE]}"

# Run monitoring
if [[ -n "$OUTPUT_FILE" ]]; then
    run_monitoring > "$OUTPUT_FILE"
else
    run_monitoring
fi
