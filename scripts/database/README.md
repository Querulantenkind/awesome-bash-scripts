# Database Scripts

Scripts for database management, backup, and maintenance.

## Categories

- **Backup/Restore**: Database backup and restoration
- **Maintenance**: Database optimization and cleanup
- **Migration**: Schema and data migration scripts
- **Monitoring**: Database performance monitoring
- **Import/Export**: Data import and export utilities

## Scripts

### 1. `db-monitor.sh`
Multi-database performance monitoring tool supporting MySQL, PostgreSQL, MongoDB, and Redis.

**Features:**
- Real-time monitoring with configurable intervals
- Connection monitoring and pool analysis
- Query statistics and counters
- Performance metrics (cache hit ratio, QPS, etc.)
- Slow query detection
- Lock monitoring
- Replication status monitoring
- Configurable alerts
- Multiple output formats (text, JSON, CSV)

**Usage:**
```bash
# Monitor MySQL connections
./db-monitor.sh -t mysql -u root -p password --connections

# Monitor PostgreSQL performance
./db-monitor.sh -t postgresql -u postgres --performance --once

# Monitor MongoDB with all metrics
./db-monitor.sh -t mongodb --connections --queries --performance

# Monitor Redis with alerts
./db-monitor.sh -t redis --alert-connections 100

# Continuous monitoring with interval
./db-monitor.sh -t mysql --interval 10 --performance
```

**Supported Databases:**
- MySQL/MariaDB (port 3306)
- PostgreSQL (port 5432)
- MongoDB (port 27017)
- Redis (port 6379)

**Monitoring Options:**
- `--connections` - Active connections and connection pool
- `--queries` - Query statistics and counters
- `--performance` - Performance metrics and cache stats
- `--slow-queries` - Long-running queries
- `--locks` - Lock information
- `--replication` - Replication status (master/slave)

**Dependencies:**
- MySQL: mysql-client
- PostgreSQL: postgresql-client
- MongoDB: mongodb-clients (mongosh or mongo)
- Redis: redis-tools

---

### 2. `db-query-analyzer.sh`
SQL query performance analyzer that identifies issues and provides optimization recommendations.

**Features:**
- EXPLAIN plan analysis
- Slow query detection
- Query execution timing
- Index recommendations
- Optimization suggestions
- Table and index statistics
- Slow query log parsing (MySQL)
- Common anti-pattern detection

**Usage:**
```bash
# Analyze specific query
./db-query-analyzer.sh -t mysql -u root -d mydb \\
  -q "SELECT * FROM users WHERE email = 'test@example.com'" --explain

# Get optimization recommendations
./db-query-analyzer.sh -t postgresql -u postgres -d mydb \\
  -q "SELECT * FROM orders WHERE user_id = 123" --recommendations

# Analyze slow query log
./db-query-analyzer.sh -t mysql --slow-log /var/log/mysql/slow.log

# Suggest missing indexes
./db-query-analyzer.sh -t mysql -u root -d mydb --indexes

# Show table statistics
./db-query-analyzer.sh -t postgresql -u postgres -d mydb --statistics
```

**Issues Detected:**
- Full table scans
- Missing indexes
- Inefficient JOINs
- Using filesort
- Using temporary tables
- High execution time
- Large result sets
- Nested loops with high cost

**Recommendations Provided:**
- Add appropriate indexes
- Optimize WHERE clauses
- Improve JOIN conditions
- Add ORDER BY indexes
- Reduce rows examined
- Partition large tables
- Use covering indexes

**Dependencies:**
- MySQL: mysql-client
- PostgreSQL: postgresql-client

---

## Common Workflows

### Database Health Check
```bash
# Check MySQL health
./db-monitor.sh -t mysql -u root -p password \\
  --connections --performance --slow-queries --once

# Check PostgreSQL health
./db-monitor.sh -t postgresql -u postgres \\
  --connections --performance --replication --once

# Check MongoDB cluster
./db-monitor.sh -t mongodb --replication --performance --once
```

### Query Optimization
```bash
# Analyze slow query
./db-query-analyzer.sh -t mysql -u root -d mydb \\
  -q "SELECT * FROM large_table WHERE status = 'active'" \\
  --explain --recommendations

# Find missing indexes
./db-query-analyzer.sh -t postgresql -u postgres -d mydb --indexes

# Review table statistics
./db-query-analyzer.sh -t mysql -u root -d mydb --statistics
```

### Continuous Monitoring
```bash
# Monitor with 10-second interval
./db-monitor.sh -t mysql -u root -p password \\
  --interval 10 --connections --performance

# Alert on high connections
./db-monitor.sh -t postgresql --alert-connections 80 \\
  --interval 5

# Monitor replication lag
./db-monitor.sh -t mysql --replication --interval 30
```

---

## Best Practices

### Database Monitoring
1. **Regular health checks**: Monitor connections, performance, and replication daily
2. **Set appropriate alerts**: Configure thresholds for connections and slow queries
3. **Watch for locks**: Monitor locks during peak hours
4. **Track slow queries**: Enable slow query log and analyze regularly
5. **Monitor replication**: Check replication lag and status frequently

### Query Optimization
1. **Use EXPLAIN**: Always analyze queries with EXPLAIN before optimization
2. **Index strategically**: Add indexes for frequently used WHERE and JOIN columns
3. **Avoid full scans**: Use WHERE clauses to limit rows examined
4. **Optimize JOINs**: Ensure JOIN columns are indexed
5. **Test changes**: Benchmark queries before and after optimization

### Performance Tuning
1. **Monitor cache hit ratio**: Aim for >99% cache hit ratio
2. **Watch connection count**: Ensure connection pool is sized appropriately
3. **Track query patterns**: Identify and optimize most frequent queries
4. **Regular maintenance**: Run ANALYZE/OPTIMIZE TABLE regularly
5. **Review indexes**: Remove unused indexes, add missing ones

---

## Troubleshooting

### Connection Issues
- **Too many connections**: Increase `max_connections` or reduce connection pool size
- **Connection timeout**: Check network latency and firewall settings
- **Authentication failed**: Verify credentials and host permissions

### Performance Issues
- **High CPU usage**: Check for full table scans and missing indexes
- **Slow queries**: Analyze with db-query-analyzer.sh and add indexes
- **Lock contention**: Identify blocking queries and optimize transactions
- **Memory issues**: Tune buffer pool size and query cache

### Replication Issues
- **Replication lag**: Check network, increase replication threads
- **Replication stopped**: Review binary log position and errors
- **Slave behind**: Consider parallel replication or faster hardware

---

## Performance Metrics Guide

### MySQL Metrics
- **Threads_connected**: Current connections (should be <80% of max)
- **Queries per second**: Database throughput
- **Buffer pool hit ratio**: Cache effectiveness (aim for >99%)
- **Slow queries**: Queries exceeding long_query_time
- **Table locks**: Lock contention indicator

### PostgreSQL Metrics
- **Active connections**: Current active queries
- **Cache hit ratio**: Buffer cache effectiveness
- **Transactions**: Commits vs rollbacks
- **Dead tuples**: Vacuum efficiency
- **Lock waits**: Blocking queries

### MongoDB Metrics
- **Operations**: Insert/query/update/delete rates
- **Connections**: Current and available
- **Memory**: Resident and virtual memory usage
- **Replication lag**: Slave delay behind master
- **Lock percentage**: Lock acquisition time

### Redis Metrics
- **Connected clients**: Active connections
- **Commands processed**: Operations per second
- **Memory usage**: Used vs max memory
- **Keyspace**: Total keys and expiration
- **Evicted keys**: Memory pressure indicator

---

## Installation

### Install Database Clients

**Debian/Ubuntu:**
```bash
# MySQL client
sudo apt install mysql-client

# PostgreSQL client
sudo apt install postgresql-client

# MongoDB client
sudo apt install mongodb-clients

# Redis client
sudo apt install redis-tools
```

**Fedora/RHEL:**
```bash
# MySQL client
sudo dnf install mysql

# PostgreSQL client
sudo dnf install postgresql

# MongoDB client
sudo dnf install mongodb-mongosh

# Redis client
sudo dnf install redis
```

**Arch Linux:**
```bash
# MySQL client
sudo pacman -S mysql-clients

# PostgreSQL client
sudo pacman -S postgresql-libs

# MongoDB client
sudo pacman -S mongodb-tools

# Redis client
sudo pacman -S redis
```

---

## Security Notes

1. **Passwords**: Avoid passing passwords via command line (use config file or environment variables)
2. **Permissions**: Ensure monitoring user has only necessary SELECT privileges
3. **SSL/TLS**: Use encrypted connections for remote databases
4. **Audit logs**: Enable database audit logging for compliance
5. **Access control**: Restrict network access to database ports

---

## Integration Examples

### Cron Jobs
```bash
# Daily health check
0 9 * * * /path/to/db-monitor.sh -t mysql --once --performance > /var/log/db-health.log

# Hourly slow query check
0 * * * * /path/to/db-monitor.sh -t mysql --slow-queries --once

# Weekly index analysis
0 0 * * 0 /path/to/db-query-analyzer.sh -t mysql --indexes > /var/log/db-indexes.log
```

### Monitoring Integration
```bash
# Prometheus-compatible output (JSON)
./db-monitor.sh -t mysql --performance --format json

# Grafana dashboard data
./db-monitor.sh -t postgresql --connections --format json --interval 60

# Alert on threshold breach
./db-monitor.sh -t mysql --alert-connections 100 --alert-slow-query 5
```

---

## Related Scripts

- **[database-backup.sh](../backup/)** - Automated database backup
- **[system-monitor.sh](../monitoring/)** - System resource monitoring
- **[log-analyzer.sh](../monitoring/)** - Log file analysis

---

## Use Cases

### Database Administrators
- Monitor database health and performance
- Identify and resolve slow queries
- Plan capacity and scaling
- Troubleshoot replication issues
- Optimize index strategy

### Developers
- Analyze query performance during development
- Identify N+1 query problems
- Optimize ORM-generated queries
- Test query changes before deployment
- Understand query execution plans

### DevOps Engineers
- Integrate monitoring into CI/CD pipelines
- Set up automated alerts
- Track database metrics over time
- Capacity planning and forecasting
- Incident response and troubleshooting

---

**Note**: Always test database scripts on non-production systems first.

