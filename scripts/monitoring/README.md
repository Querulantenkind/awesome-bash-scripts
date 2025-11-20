# Monitoring Scripts

Professional monitoring tools for system resources, services, logs, and network activity. These scripts provide comprehensive monitoring capabilities with real-time updates, alerts, and detailed analysis.

## 📊 Available Scripts

### 1. system-monitor.sh
**Comprehensive system resource monitoring with alerts and logging**

Monitor CPU, memory, disk, network, and process information with customizable thresholds and alert capabilities.

#### Features
- ✅ CPU usage monitoring (per-core and overall)
- ✅ Memory usage tracking (RAM and Swap)
- ✅ Disk usage for all mounted filesystems
- ✅ System load averages (1m, 5m, 15m)
- ✅ Network statistics
- ✅ Process tracking and top consumers
- ✅ Configurable alert thresholds
- ✅ Continuous watch mode
- ✅ JSON export capability
- ✅ Color-coded status indicators

#### Usage Examples

```bash
# Basic system monitoring
./system-monitor.sh

# Continuous monitoring every 5 seconds
./system-monitor.sh --watch 5

# Enable alerts with custom thresholds
./system-monitor.sh --alert --cpu 90 --memory 85 --disk 90

# Watch mode with alerts and logging
./system-monitor.sh -w 3 -a -c 75 -m 80 -l /var/log/sysmonitor.log

# JSON output for automation
./system-monitor.sh --json

# Summary view only
./system-monitor.sh --summary

# Verbose mode with no color (for scripts)
./system-monitor.sh --verbose --no-color
```

#### Options
```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-l, --log FILE          Log output to file
-w, --watch SECONDS     Continuous monitoring mode
-a, --alert             Enable threshold alerts
-c, --cpu PERCENT       CPU alert threshold (default: 80)
-m, --memory PERCENT    Memory alert threshold (default: 80)
-d, --disk PERCENT      Disk alert threshold (default: 85)
-j, --json              Output in JSON format
-s, --summary           Show summary only
--no-color              Disable colored output
```

#### Alert Configuration
The script supports customizable thresholds for:
- **CPU Usage**: Alert when CPU exceeds threshold
- **Memory Usage**: Alert when RAM usage exceeds threshold
- **Disk Usage**: Alert when any disk exceeds threshold

#### Output Formats
- **Standard**: Color-coded terminal output with detailed sections
- **Summary**: Quick overview of key metrics
- **JSON**: Machine-readable format for automation

---

### 2. service-monitor.sh
**Monitor systemd services with health checks and automatic recovery**

Track service status, uptime, resource usage, and automatically restart failed services with notification support.

#### Features
- ✅ Real-time service status monitoring
- ✅ Automatic service restart on failure
- ✅ Desktop notifications (notify-send)
- ✅ Email alerts
- ✅ Service uptime tracking
- ✅ Memory and resource usage per service
- ✅ Configuration file support
- ✅ Monitor all enabled services
- ✅ List failed/active services
- ✅ JSON export

#### Usage Examples

```bash
# Monitor specific services
./service-monitor.sh nginx postgresql redis

# Continuous monitoring with auto-restart
./service-monitor.sh --watch 30 --auto-restart sshd nginx apache2

# List all failed services
./service-monitor.sh --list-failed

# List all active services
./service-monitor.sh --list-active

# Monitor with notifications
./service-monitor.sh -w 60 -n -a nginx postgresql

# Use configuration file
./service-monitor.sh --config /etc/service-monitor.conf --notify --auto-restart

# Monitor all enabled services
./service-monitor.sh --check-all --json

# Email alerts
./service-monitor.sh -w 30 -e admin@example.com nginx mysql
```

#### Options
```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-l, --log FILE          Log output to file
-w, --watch SECONDS     Continuous monitoring (default: 30s)
-a, --auto-restart      Automatically restart failed services
-n, --notify            Send desktop notifications
-e, --email EMAIL       Send email alerts
-c, --config FILE       Load services from config file
-j, --json              Output in JSON format
--list-failed           List all failed services
--list-active           List all active services
--check-all             Monitor all enabled services
```

#### Configuration File Format
Create a file with one service name per line:
```
nginx
postgresql
redis
mysql
# Comments are supported
sshd
```

#### Service Information Displayed
- Service status (active/inactive/failed)
- Enabled state (enabled/disabled)
- Uptime (how long service has been running)
- Memory usage
- Process ID (PID)
- Number of tasks
- Service description

---

### 3. log-analyzer.sh
**Advanced log file analysis with pattern detection and statistics**

Analyze log files with support for multiple formats, real-time monitoring, pattern search, and statistical analysis.

#### Features
- ✅ Multiple log format detection (syslog, nginx, apache, JSON)
- ✅ Real-time log following (like tail -f)
- ✅ Pattern matching with regex
- ✅ Error and warning filtering
- ✅ Statistical analysis
- ✅ HTTP status code distribution
- ✅ Top IP addresses analysis
- ✅ Time-based filtering
- ✅ Alert on specific patterns
- ✅ JSON export

#### Usage Examples

```bash
# Basic log analysis
./log-analyzer.sh /var/log/syslog

# Follow log in real-time
./log-analyzer.sh --follow /var/log/nginx/error.log

# Show errors and warnings only
./log-analyzer.sh --errors /var/log/application.log

# Statistical analysis
./log-analyzer.sh --stats /var/log/syslog

# Search for specific pattern
./log-analyzer.sh --pattern "authentication failure" /var/log/auth.log

# Analyze nginx access log
./log-analyzer.sh --http-codes --top-ips 20 /var/log/nginx/access.log

# Follow with alerts
./log-analyzer.sh --follow --alert-on "CRITICAL" /var/log/app.log

# Filter by IP address
./log-analyzer.sh --ip 192.168.1.100 /var/log/apache2/access.log

# Show last 200 lines
./log-analyzer.sh --tail 200 /var/log/syslog

# Filter by log level
./log-analyzer.sh --level ERROR /var/log/application.log

# Save analysis to file
./log-analyzer.sh --stats --output report.txt /var/log/syslog
```

#### Options
```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-f, --follow            Follow log file in real-time
-n, --lines NUM         Number of lines to analyze (default: 1000)
-p, --pattern PATTERN   Search for specific pattern (regex)
-e, --errors            Show only errors and warnings
-s, --stats             Display statistical analysis
-t, --time-range RANGE  Analyze logs within time range
-l, --level LEVEL       Filter by log level (ERROR|WARN|INFO|DEBUG)
-o, --output FILE       Save report to file
-j, --json              Output in JSON format
--tail NUM              Show last N lines (default: 100)
--ip IP                 Filter by IP address
--http-codes            Show HTTP status code distribution
--top-ips NUM           Show top N IP addresses
--alert-on PATTERN      Alert when pattern is found
```

#### Supported Log Formats
- **Syslog**: Standard Linux system logs
- **Apache/Nginx Access**: Web server access logs
- **Nginx Error**: Web server error logs
- **JSON**: Application logs in JSON format
- **Generic**: Plain text logs

#### Statistics Provided
- Total line count
- Error count and percentage
- Warning count and percentage
- Info message count
- Debug message count
- Time range of analyzed logs

---

### 4. network-monitor.sh
**Comprehensive network monitoring and connectivity testing**

Monitor network interfaces, bandwidth, connections, ports, and perform connectivity tests with real-time statistics.

#### Features
- ✅ Network interface statistics
- ✅ Real-time bandwidth monitoring
- ✅ Active connection tracking
- ✅ Listening port detection
- ✅ Connectivity testing
- ✅ Latency/ping monitoring
- ✅ Port scanning
- ✅ Connection state tracking
- ✅ Multiple interface support
- ✅ JSON export

#### Usage Examples

```bash
# Basic network overview
./network-monitor.sh

# Continuous bandwidth monitoring
./network-monitor.sh --watch 5 --bandwidth

# Monitor specific interface
./network-monitor.sh --interface eth0 --bandwidth

# Show listening ports and connections
./network-monitor.sh --ports --connections

# Test connectivity to host
./network-monitor.sh --test google.com

# Monitor latency continuously
./network-monitor.sh --latency 8.8.8.8 --watch 1

# Port scan a host
./network-monitor.sh --scan 192.168.1.1

# Comprehensive monitoring
./network-monitor.sh -w 5 -i eth0 -b -p -c

# JSON output with logging
./network-monitor.sh --json --log /var/log/network.log
```

#### Options
```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-w, --watch SECONDS     Continuous monitoring (default: 5s)
-i, --interface IFACE   Monitor specific network interface
-p, --ports             Show listening ports
-c, --connections       Show active connections
-b, --bandwidth         Monitor bandwidth usage
-t, --test HOST         Test connectivity to host
-s, --scan HOST         Port scan host (common ports)
-l, --latency HOST      Monitor latency/ping to host
-j, --json              Output in JSON format
--log FILE              Log output to file
```

#### Network Information Displayed
- Interface state (up/down)
- IPv4 and IPv6 addresses
- MAC address
- MTU (Maximum Transmission Unit)
- RX/TX bytes and packets
- Network errors and dropped packets
- Real-time bandwidth (download/upload rates)
- Active connection states
- Listening ports with associated programs

#### Connectivity Tests
- DNS resolution
- ICMP ping (5 packets)
- Average latency
- Common port availability (80, 443, 22)

---

## 🔧 Dependencies

### Required (all scripts)
- `bash` >= 4.0
- Standard GNU utilities: `awk`, `sed`, `grep`, `bc`

### Script-Specific Dependencies

**system-monitor.sh**
- `bc` - For calculations
- `iostat` (optional) - For detailed I/O stats
- `top` - Process monitoring

**service-monitor.sh**
- `systemctl` - Systemd service management
- `notify-send` (optional) - Desktop notifications
- `mail` (optional) - Email alerts

**log-analyzer.sh**
- `tail` - Log following
- Standard text processing tools

**network-monitor.sh**
- `ip` (iproute2) - Network interface management
- `ss` or `netstat` - Connection tracking
- `ping` - Connectivity testing
- `nc` (netcat, optional) - Port scanning

### Installing Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get install bc iproute2 net-tools iputils-ping netcat-openbsd
```

**Fedora/RHEL:**
```bash
sudo dnf install bc iproute net-tools iputils netcat
```

**Arch Linux:**
```bash
sudo pacman -S bc iproute2 net-tools iputils gnu-netcat
```

---

## 📋 Usage Patterns

### Continuous Monitoring
All scripts support watch mode for continuous monitoring:
```bash
./system-monitor.sh --watch 5
./service-monitor.sh --watch 30
./log-analyzer.sh --follow
./network-monitor.sh --watch 5 --bandwidth
```

### Automation & Scripting
Use JSON output for integration with other tools:
```bash
./system-monitor.sh --json | jq '.cpu.usage_percent'
./service-monitor.sh --json --check-all > services.json
./network-monitor.sh --json | jq '.interface.rx_bytes'
```

### Logging
All scripts support logging to file:
```bash
./system-monitor.sh -w 60 -l /var/log/system-monitor.log
./service-monitor.sh -w 30 -l /var/log/service-monitor.log
./network-monitor.sh -w 5 --log /var/log/network-monitor.log
```

### Cron Jobs
Schedule monitoring tasks:
```bash
# Check services every 5 minutes
*/5 * * * * /path/to/service-monitor.sh --auto-restart nginx mysql >> /var/log/service-check.log 2>&1

# Daily system report
0 8 * * * /path/to/system-monitor.sh --stats >> /var/log/daily-report.log 2>&1

# Hourly log analysis
0 * * * * /path/to/log-analyzer.sh --stats /var/log/application.log >> /var/log/log-analysis.log 2>&1
```

---

## 🚨 Alerts and Notifications

### System Monitor Alerts
Configure thresholds and get alerts:
```bash
./system-monitor.sh -w 60 -a -c 85 -m 90 -d 95
```

### Service Monitor Notifications
Desktop and email notifications:
```bash
./service-monitor.sh -w 30 -a -n -e admin@example.com nginx mysql
```

### Log Analyzer Alerts
Alert on specific patterns:
```bash
./log-analyzer.sh -f --alert-on "CRITICAL|FATAL" /var/log/app.log
```

---

## 💡 Best Practices

1. **Start Simple**: Begin with basic monitoring, add features as needed
2. **Set Appropriate Thresholds**: Adjust alert thresholds based on your system
3. **Use Configuration Files**: For service monitoring, maintain a config file
4. **Enable Logging**: Keep historical data for analysis
5. **Combine Scripts**: Use multiple scripts together for comprehensive monitoring
6. **Automate**: Set up cron jobs for regular monitoring
7. **Test Alerts**: Verify notifications work before relying on them
8. **Monitor the Monitors**: Ensure monitoring scripts themselves are running

---

## 🔍 Troubleshooting

### Permission Issues
Some features require elevated privileges:
```bash
sudo ./service-monitor.sh --check-all
sudo ./network-monitor.sh --ports
```

### Missing Dependencies
Check if required tools are installed:
```bash
command -v systemctl || echo "systemd not available"
command -v ss || echo "ss not available, will use netstat"
```

### High Resource Usage
Reduce monitoring frequency:
```bash
./system-monitor.sh --watch 30  # Instead of every 5 seconds
```

### Log File Access
Ensure read permissions:
```bash
sudo chmod +r /var/log/nginx/error.log
# Or run with sudo
sudo ./log-analyzer.sh /var/log/secure
```

---

## 📊 Example Monitoring Setup

### Complete System Monitoring
```bash
#!/bin/bash
# Run all monitoring scripts

echo "=== System Resources ==="
./system-monitor.sh --summary

echo -e "\n=== Critical Services ==="
./service-monitor.sh nginx postgresql redis mysql

echo -e "\n=== Network Status ==="
./network-monitor.sh --connections

echo -e "\n=== Recent Errors ==="
./log-analyzer.sh --errors --tail 20 /var/log/syslog
```

### Production Server Monitoring
```bash
# In cron: */5 * * * *
./system-monitor.sh -a -c 90 -m 90 -l /var/log/monitors/system.log
./service-monitor.sh -a -n critical-service-1 critical-service-2 -l /var/log/monitors/services.log
./log-analyzer.sh --errors /var/log/application.log >> /var/log/monitors/errors.log
```

---

## 🎯 Use Cases

### System Administrator
- Monitor system health with `system-monitor.sh`
- Track critical services with `service-monitor.sh --auto-restart`
- Analyze logs for issues with `log-analyzer.sh --errors`

### DevOps Engineer
- Automated monitoring with JSON output
- Integration with alerting systems
- Historical data collection and analysis

### Web Developer
- Analyze nginx/apache logs with `log-analyzer.sh --http-codes`
- Monitor application logs for errors
- Track network connectivity to APIs

### Security Analyst
- Monitor authentication logs with `log-analyzer.sh --pattern "failed"`
- Track network connections with `network-monitor.sh --connections`
- Detect unusual patterns in logs

---

## 📝 Notes

- All scripts use color-coded output for better readability
- JSON mode automatically disables colors for clean data export
- Watch mode can be interrupted with Ctrl+C
- Scripts are designed to be both human-readable and machine-parseable
- Verbose mode provides additional debugging information

---

**Happy Monitoring!** 📊

For issues or suggestions, please open an issue on the repository.
