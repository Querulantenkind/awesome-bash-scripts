# Analytics Scripts

Collection of data analytics, reporting, and visualization scripts for log aggregation, metrics collection, trend analysis, and dashboard generation.

## Scripts

### 1. `log-aggregator.sh`
Multi-source log aggregation and analysis tool.

**Features:**
- Multiple log sources (file, syslog, journald, remote SSH)
- Real-time log following
- Pattern filtering and log level filtering
- Log correlation across sources
- Anomaly detection
- Multiple output formats (text, JSON, CSV, HTML)
- Alert system with email notifications

**Usage:**
```bash
# Aggregate error logs from file
./log-aggregator.sh -s file -f /var/log/syslog --level ERROR

# Follow journald logs
./log-aggregator.sh -s journald --since "1 hour ago" --tail

# Collect from remote host
./log-aggregator.sh -s remote -r server.com -p "nginx" --stats

# Aggregate multiple sources with JSON output
./log-aggregator.sh -f /var/log/app1.log -f /var/log/app2.log --aggregate --format json

# Real-time monitoring with alerts
./log-aggregator.sh -s syslog --tail --alert "Failed" --alert-email admin@example.com
```

---

### 2. `metrics-reporter.sh`
Comprehensive metrics collection and reporting system.

**Features:**
- Multiple metric types (system, process, network, disk)
- Multiple output formats (text, JSON, Prometheus, InfluxDB, Graphite)
- Time-series collection with intervals
- Metric aggregation and percentiles (p50, p95, p99)
- Custom labels for multi-environment support
- Process-specific monitoring
- Integration-ready output formats

**Usage:**
```bash
# System metrics in Prometheus format
./metrics-reporter.sh -t system --format prometheus

# Process metrics with monitoring
./metrics-reporter.sh -t process -p nginx --interval 10 --duration 300

# Network metrics with InfluxDB format
./metrics-reporter.sh -t network --format influx --timestamp

# Aggregated metrics with percentiles
./metrics-reporter.sh -t system --interval 5 --duration 60 --aggregate --percentiles

# Custom labels for environment
./metrics-reporter.sh -t system --labels env=prod,region=us-east --format prometheus
```

**Integration Examples:**
```bash
# Prometheus Node Exporter compatible
./metrics-reporter.sh -t system --format prometheus > /var/lib/node_exporter/metrics.prom

# InfluxDB ingestion
./metrics-reporter.sh -t system --format influx | curl -XPOST 'http://localhost:8086/write?db=metrics' --data-binary @-

# Graphite Carbon plaintext
./metrics-reporter.sh -t system --format graphite | nc graphite.example.com 2003
```

---

### 3. `trend-analyzer.sh`
Time-series data analysis and forecasting tool.

**Features:**
- Descriptive statistics (mean, std dev, min, max)
- Linear trend analysis
- Forecasting with confidence intervals
- Anomaly detection (configurable sigma threshold)
- Growth rate calculation
- Seasonality detection
- Moving averages
- ASCII chart visualization

**Usage:**
```bash
# Complete trend analysis
./trend-analyzer.sh -f metrics.csv --analyze --chart

# Forecast future values
./trend-analyzer.sh -f data.csv --forecast 10 --moving-avg 7

# Detect anomalies
./trend-analyzer.sh -f sales.csv --anomalies --threshold 2.5

# Seasonality detection
./trend-analyzer.sh -f metrics.csv --seasonality --format json

# Growth rate analysis
./trend-analyzer.sh -f revenue.csv --growth --chart
```

**Input Format:**
```csv
timestamp,value
2024-01-01,100
2024-01-02,105
2024-01-03,98
```

---

### 4. `dashboard-generator.sh`
Custom dashboard generator for terminal and HTML.

**Features:**
- Real-time terminal dashboards
- HTML dashboard generation
- Multiple widgets (CPU, memory, disk, network, processes, logs)
- Multiple layouts (single, grid)
- Auto-refresh capability
- Color themes
- Customizable refresh intervals

**Usage:**
```bash
# Terminal dashboard with default widgets
./dashboard-generator.sh

# Custom widgets in grid layout
./dashboard-generator.sh --widgets cpu,memory,disk,network --layout grid

# Generate HTML dashboard
./dashboard-generator.sh -t html -o dashboard.html --theme dark

# Real-time monitoring
./dashboard-generator.sh --refresh 2 --widgets cpu,memory,processes

# Full monitoring dashboard
./dashboard-generator.sh --widgets cpu,memory,disk,network,processes,uptime,logs --layout grid
```

**Available Widgets:**
- `cpu` - CPU usage and load averages
- `memory` - Memory and swap usage
- `disk` - Disk usage and I/O statistics
- `network` - Network interfaces and traffic
- `processes` - Running processes
- `uptime` - System uptime and information
- `logs` - Recent system logs

---

## Common Workflows

### Log Analysis Pipeline
```bash
# 1. Aggregate logs from multiple sources
./log-aggregator.sh -f /var/log/app1.log -f /var/log/app2.log \
  --aggregate -o aggregated.log

# 2. Analyze patterns
./log-aggregator.sh -s file -f aggregated.log \
  --correlate --stats

# 3. Generate alerts
./log-aggregator.sh -s file -f aggregated.log \
  --alert "ERROR" --alert-email admin@example.com --tail
```

### Metrics Monitoring
```bash
# 1. Collect metrics continuously
./metrics-reporter.sh -t system --interval 60 --format prometheus \
  -o /var/lib/metrics/system.prom &

# 2. Collect process-specific metrics
./metrics-reporter.sh -t process -p nginx --interval 30 \
  --format influx -o nginx_metrics.txt &

# 3. Generate dashboard
./dashboard-generator.sh --widgets cpu,memory,network,processes \
  --refresh 5
```

### Trend Analysis Pipeline
```bash
# 1. Export metrics to CSV
./metrics-reporter.sh -t system --interval 60 --duration 3600 \
  --format csv -o hourly_metrics.csv

# 2. Analyze trends
./trend-analyzer.sh -f hourly_metrics.csv --analyze --forecast 12 \
  --anomalies --chart -o trend_report.txt

# 3. Visualize in dashboard
./dashboard-generator.sh -t html -o trend_dashboard.html
```

---

## Best Practices

### Log Aggregation
1. **Filter early**: Use pattern matching to reduce data volume
2. **Centralize logs**: Aggregate from multiple sources for correlation
3. **Set up alerts**: Configure thresholds for critical errors
4. **Rotate output**: Manage output file sizes with rotation
5. **Use structured formats**: JSON/CSV for better processing

### Metrics Collection
1. **Choose appropriate intervals**: Balance granularity vs overhead
2. **Use labels**: Tag metrics with environment/region for filtering
3. **Export to time-series DB**: Use InfluxDB/Prometheus for long-term storage
4. **Monitor trends**: Track metrics over time, not just current values
5. **Set baselines**: Establish normal ranges for alerting

### Trend Analysis
1. **Clean your data**: Remove outliers before analysis
2. **Use appropriate windows**: Choose moving average windows wisely
3. **Validate forecasts**: Compare predictions with actual data
4. **Consider seasonality**: Account for daily/weekly/monthly patterns
5. **Multiple metrics**: Correlate different data sources

### Dashboard Design
1. **Less is more**: Show only essential metrics
2. **Group related metrics**: Use logical widget groupings
3. **Consistent refresh**: Match refresh rate to data change frequency
4. **Color coding**: Use colors to highlight issues
5. **Export options**: Generate HTML for sharing/archiving

---

## Integration Examples

### Prometheus Integration
```bash
# Export system metrics
./metrics-reporter.sh -t system --format prometheus \
  -o /var/lib/node_exporter/textfile_collector/custom_metrics.prom

# Add to Prometheus scrape config
# prometheus.yml:
# scrape_configs:
#   - job_name: 'custom-metrics'
#     static_configs:
#       - targets: ['localhost:9100']
```

### Grafana Integration
```bash
# Collect metrics in InfluxDB format
./metrics-reporter.sh -t system --interval 10 --format influx | \
  while read line; do
    curl -XPOST 'http://localhost:8086/write?db=metrics' -d "$line"
  done
```

### ELK Stack Integration
```bash
# Send logs to Logstash
./log-aggregator.sh -s journald --format json --tail | \
  nc logstash-host 5000
```

---

## Dependencies

### Required
- `bash` (≥4.0)
- `coreutils` (basic Unix utilities)
- `bc` (calculator for numeric operations)

### Optional
- `jq` - JSON processing (highly recommended)
- `curl` - API/remote operations
- `ssh` - Remote log collection
- `journalctl` - systemd journal access
- `yq` - YAML processing
- `xmlstarlet` - XML processing

### Installation
```bash
# Debian/Ubuntu
sudo apt install jq bc curl openssh-client systemd

# Fedora/RHEL
sudo dnf install jq bc curl openssh-clients systemd

# Arch Linux
sudo pacman -S jq bc curl openssh systemd
```

---

## Troubleshooting

### Log Aggregator Issues
- **Permission denied**: Run with sudo for system logs
- **Remote connection failed**: Check SSH keys and firewall
- **No logs collected**: Verify log file paths and permissions

### Metrics Reporter Issues
- **Missing data**: Ensure required /proc and /sys filesystems are mounted
- **Format errors**: Validate output with respective tools (promtool, influx CLI)
- **High CPU usage**: Increase collection interval

### Trend Analyzer Issues
- **Invalid data**: Check CSV format and numeric values
- **Poor forecasts**: Increase data points or adjust trend window
- **No seasonality detected**: Need minimum 2x period length of data

### Dashboard Generator Issues
- **Display issues**: Check terminal size (minimum 80x24)
- **HTML not rendering**: Validate HTML syntax
- **High refresh rate**: Increase interval to reduce system load

---

## Performance Notes

- **Log aggregation**: ~1000 lines/sec on modern hardware
- **Metrics collection**: Minimal overhead (<1% CPU)
- **Trend analysis**: Handles files up to 100K records efficiently
- **Dashboard refresh**: <100ms for typical widget set

---

## Security Considerations

1. **Log files may contain sensitive data**: Use appropriate permissions
2. **Remote SSH**: Use key-based authentication
3. **Alert emails**: Configure secure mail transport
4. **File permissions**: Restrict access to output files
5. **Metric exposure**: Be cautious exposing internal metrics publicly

---

## Use Cases

### DevOps Engineers
- Aggregate logs from multiple servers
- Monitor system metrics in real-time
- Generate dashboards for NOC displays
- Integrate with existing monitoring stack

### Data Analysts
- Analyze historical trends
- Forecast capacity requirements
- Detect anomalies in time-series data
- Generate reports for stakeholders

### System Administrators
- Troubleshoot issues via log correlation
- Monitor system health
- Track resource usage over time
- Alert on critical conditions

### Developers
- Debug application logs
- Profile application performance
- Monitor custom application metrics
- Visualize test results

---

## Related Scripts

- **[system-monitor.sh](../monitoring/)** - Real-time system monitoring
- **[db-monitor.sh](../database/)** - Database performance monitoring
- **[network-monitor.sh](../monitoring/)** - Network traffic analysis
