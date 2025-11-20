# System Scripts

Professional system administration and maintenance tools for Linux systems. These scripts help with system information gathering, package management, and system maintenance tasks.

## 🖥️ Available Scripts

### 1. system-info.sh
**Comprehensive system information gathering and reporting tool**

Collects detailed hardware, software, network, and performance information with multiple output formats.

#### Features
- ✅ **System information**: OS, kernel, hostname, uptime
- ✅ **CPU details**: Model, cores, threads, speed, cache, usage
- ✅ **Memory information**: RAM and swap usage statistics
- ✅ **Disk information**: All mounted filesystems and usage
- ✅ **Network details**: Interfaces, IPs, gateway, DNS
- ✅ **Process information**: Counts, top CPU/memory consumers
- ✅ **User information**: Current users, logged-in sessions
- ✅ **Hardware detection**: Manufacturer, model, BIOS (requires root)
- ✅ **Software inventory**: Package manager, installed packages
- ✅ **Service status**: systemd services overview
- ✅ **JSON export**: Machine-readable output format
- ✅ **Flexible reporting**: Choose specific categories

#### Usage Examples

```bash
# Show default information (system, CPU, memory, disk)
./system-info.sh

# Show all available information
./system-info.sh --all

# Show specific categories
./system-info.sh --system --cpu --memory

# Generate JSON report
./system-info.sh --all --json -o system-report.json

# Show hardware details (requires root)
sudo ./system-info.sh --hardware

# Show software and services
./system-info.sh --software --services

# Quick network overview
./system-info.sh --network
```

#### Output Categories

**System Information (`-s, --system`)**
- Hostname, OS, kernel version
- Architecture, uptime
- Load averages, date/time

**CPU Information (`-c, --cpu`)**
- Model, cores, threads
- Current and max MHz
- Cache size, current usage

**Memory Information (`-m, --memory`)**
- Total, used, free, available RAM
- Swap usage and statistics
- Memory percentage

**Disk Information (`-d, --disk`)**
- All mounted filesystems
- Size, used, available space
- Usage percentages

**Network Information (`-n, --network`)**
- Hostname and FQDN
- Primary and public IP
- Gateway and DNS servers
- All network interfaces with status

**Process Information (`-p, --processes`)**
- Total, running, sleeping, zombie counts
- Top 5 CPU consumers
- Top 5 memory consumers

**User Information (`-u, --users`)**
- Current user
- Total system users
- Logged-in sessions

**Hardware Details (`--hardware`)**
- System manufacturer
- Product name and serial
- BIOS version and date

**Software Inventory (`--software`)**
- Package manager type
- Number of installed packages
- Shell information

**Service Status (`--services`)**
- Total, active, failed services
- List of failed services

---

### 2. package-cleanup.sh
**System package cleanup and maintenance tool**

Removes orphaned packages, clears caches, and performs system maintenance across multiple package managers.

#### Features
- ✅ **Multi-distro support**: Debian/Ubuntu (apt), Red Hat/Fedora (dnf/yum), Arch (pacman)
- ✅ **Remove orphaned packages**: Clean up unused dependencies
- ✅ **Clear package caches**: Free up disk space
- ✅ **Auto mode**: Non-interactive cleanup
- ✅ **Dry-run mode**: Preview changes before applying
- ✅ **Selective cleanup**: Cache only or orphaned only
- ✅ **Logging support**: Track cleanup operations

#### Usage Examples

```bash
# Interactive cleanup
./package-cleanup.sh

# Automatic cleanup (no prompts)
./package-cleanup.sh --auto

# Clear package cache only
./package-cleanup.sh --cache

# Remove orphaned packages only
./package-cleanup.sh --orphaned

# Dry run (show what would be done)
./package-cleanup.sh --dry-run

# Automatic cleanup with logging
./package-cleanup.sh --auto --log /var/log/cleanup.log

# Verbose output
./package-cleanup.sh --verbose
```

#### What It Cleans

**APT (Debian/Ubuntu)**
- Package cache (`apt-get clean`)
- Orphaned packages (`apt-get autoremove`)
- Old configuration files

**DNF/YUM (Red Hat/Fedora)**
- Package cache (`dnf clean all`)
- Orphaned packages (`dnf autoremove`)

**Pacman (Arch Linux)**
- Package cache (`pacman -Sc`)
- Orphaned packages (`pacman -Rns`)

---

## 🔧 Common Use Cases

### System Documentation
```bash
# Generate complete system report
./system-info.sh --all -o system-documentation.txt

# JSON report for inventory systems
./system-info.sh --all --json -o inventory.json

# Quick system check
./system-info.sh
```

### Regular Maintenance
```bash
# Weekly package cleanup
./package-cleanup.sh --auto --log /var/log/weekly-cleanup.log

# Monthly deep cleanup
./package-cleanup.sh --auto

# Check what would be cleaned
./package-cleanup.sh --dry-run
```

### Troubleshooting
```bash
# Check system resources
./system-info.sh --cpu --memory --disk

# View network configuration
./system-info.sh --network

# Check running processes
./system-info.sh --processes
```

### Inventory Management
```bash
# Collect hardware info
sudo ./system-info.sh --hardware --software -o hardware-inventory.txt

# Track installed software
./system-info.sh --software -o software-list.txt
```

---

## 📋 Automation Examples

### Daily System Report
```bash
#!/bin/bash
# /usr/local/bin/daily-system-report.sh

DATE=$(date +%Y-%m-%d)
REPORT_DIR="/var/log/system-reports"
mkdir -p "$REPORT_DIR"

/path/to/system-info.sh --all -o "$REPORT_DIR/system-report-$DATE.txt"
```

Add to crontab:
```bash
# Daily system report at 2 AM
0 2 * * * /usr/local/bin/daily-system-report.sh
```

### Weekly Cleanup
```bash
#!/bin/bash
# /usr/local/bin/weekly-cleanup.sh

LOG="/var/log/weekly-cleanup.log"
echo "=== Cleanup started at $(date) ===" >> "$LOG"

/path/to/package-cleanup.sh --auto --log "$LOG"

echo "=== Cleanup completed at $(date) ===" >> "$LOG"
```

Add to crontab:
```bash
# Weekly cleanup on Sunday at 3 AM
0 3 * * 0 /usr/local/bin/weekly-cleanup.sh
```

### System Health Check
```bash
#!/bin/bash
# Check system health and send email if issues detected

REPORT=$(/path/to/system-info.sh --cpu --memory --disk)
CPU_USAGE=$(echo "$REPORT" | grep "CPU Usage" | awk '{print $3}' | tr -d '%')
MEM_USAGE=$(echo "$REPORT" | grep "RAM Used" | grep -oP '\d+%' | tr -d '%')

if [ "$CPU_USAGE" -gt 80 ] || [ "$MEM_USAGE" -gt 90 ]; then
    echo "$REPORT" | mail -s "System Alert: High Resource Usage" admin@example.com
fi
```

---

## 🎯 Best Practices

### System Information Gathering

1. **Regular Documentation**
```bash
# Monthly system documentation
./system-info.sh --all -o "system-doc-$(date +%Y-%m).txt"
```

2. **Before/After Comparisons**
```bash
# Before major changes
./system-info.sh --all -o system-before.txt

# After changes
./system-info.sh --all -o system-after.txt

# Compare
diff system-before.txt system-after.txt
```

3. **Security Audits**
```bash
# Collect information for security review
./system-info.sh --network --users --services -o security-audit.txt
```

### Package Management

1. **Regular Cleanup**
```bash
# Weekly automated cleanup
0 3 * * 0 /path/to/package-cleanup.sh --auto --log /var/log/cleanup.log
```

2. **Before Updates**
```bash
# Clean before system updates
./package-cleanup.sh --auto
sudo apt update && sudo apt upgrade
```

3. **Disk Space Management**
```bash
# When running low on disk space
./package-cleanup.sh --cache --auto
```

---

## 📊 Disk Space Savings

### Expected Cleanup Results

**APT (Debian/Ubuntu)**
- Package cache: 100MB - 2GB
- Orphaned packages: 50MB - 500MB
- Old configs: 1MB - 50MB

**DNF (Fedora/RHEL)**
- Package cache: 500MB - 5GB
- Orphaned packages: 100MB - 1GB

**Pacman (Arch)**
- Package cache: Variable (keeps 3 versions by default)
- Orphaned packages: 50MB - 500MB

### Check Space Before/After
```bash
# Before cleanup
df -h / | tail -1

# Run cleanup
./package-cleanup.sh --auto

# After cleanup
df -h / | tail -1
```

---

## 🔍 Troubleshooting

### System Info Script

**"Permission denied" for hardware info**
```bash
# Hardware detection requires root
sudo ./system-info.sh --hardware
```

**JSON output malformed**
```bash
# Ensure no other output is mixed in
./system-info.sh --all --json 2>/dev/null -o report.json
```

**Slow execution**
```bash
# Only gather needed information
./system-info.sh --system --cpu --memory
```

### Package Cleanup Script

**"Package manager not found"**
```bash
# Check supported package managers
which apt-get dpkg dnf yum pacman

# Install appropriate tools
sudo apt-get install apt  # Debian/Ubuntu
sudo dnf install dnf-utils  # Fedora
```

**Cleanup fails**
```bash
# Check permissions
sudo ./package-cleanup.sh --auto

# Check logs
./package-cleanup.sh --auto --log /tmp/cleanup.log
cat /tmp/cleanup.log
```

**Want to see what will be removed**
```bash
# Always use dry-run first
./package-cleanup.sh --dry-run
```

---

## 📝 Tips and Tricks

### System Information

**Quick Health Check**
```bash
# One-line system overview
./system-info.sh | grep -E "CPU|Memory|Disk"
```

**Monitor Specific Resource**
```bash
# Watch CPU usage
watch -n 5 './system-info.sh --cpu | grep Usage'
```

**Export for Documentation**
```bash
# Generate PDF report (requires pandoc)
./system-info.sh --all -o report.md
pandoc report.md -o system-report.pdf
```

### Package Cleanup

**Aggressive Cleanup**
```bash
# Maximum cleanup (be careful!)
./package-cleanup.sh --auto --cache --orphaned
```

**Scheduled Cleanup**
```bash
# Add to crontab for weekly execution
(crontab -l 2>/dev/null; echo "0 3 * * 0 /path/to/package-cleanup.sh --auto") | crontab -
```

**Check What's Orphaned**
```bash
# Debian/Ubuntu
apt-get autoremove --dry-run

# Fedora
dnf list extras

# Arch
pacman -Qtd
```

---

## ⚠️ Important Notes

### System Information
- Hardware detection requires root privileges
- Some information may not be available in containers
- JSON output is suitable for parsing by other tools
- Reports can contain sensitive information - secure appropriately

### Package Cleanup
- Always review what will be removed in interactive mode
- Orphaned packages may still be useful
- Cache cleanup is safe and recommended
- Some distributions auto-clean caches
- Test in non-production environment first

---

## 📚 Additional Resources

### System Information
- Run `./system-info.sh --help` for all options
- Check `man lscpu` for CPU information details
- See `man free` for memory information
- Review `man df` for disk information

### Package Management
- APT: `man apt-get`, `man apt`
- DNF: `man dnf`
- Pacman: `man pacman`
- General: Check your distribution's documentation

---

**Happy System Administration!** 🖥️

For issues or suggestions, please open an issue on the repository.
