# Network Scripts

Scripts for network configuration, testing, and troubleshooting.

## Categories

- **Network Testing**: Connectivity tests, speed tests, latency checks
- **Configuration**: Network interface management, DNS setup
- **Monitoring**: Network traffic analysis, connection monitoring
- **Security**: Firewall rules, port scanning detection
- **Remote Access**: SSH management, VPN setup

## Scripts

### 1. `port-scanner.sh`
Advanced network port scanner with service detection, parallel scanning, and multiple output formats.

**Features:**
- TCP/UDP port scanning
- Service detection and banner grabbing
- Parallel scanning with configurable threads
- Stealth SYN scanning (requires root)
- Multiple output formats (text, JSON, CSV, XML)
- Common port presets and custom ranges

**Usage:**
```bash
./port-scanner.sh example.com                    # Scan common ports
./port-scanner.sh -p 1-1000 --banner example.com # Scan range with banners
./port-scanner.sh --top 100 -f json example.com  # Top 100 ports as JSON
```

### 2. `bandwidth-monitor.sh`
Real-time bandwidth monitoring tool that tracks network usage per interface, process, and connection.

**Features:**
- Real-time bandwidth monitoring
- Per-interface statistics
- Process bandwidth tracking (requires root)
- Active connection monitoring
- Bandwidth alerts and thresholds
- Visual graphs and multiple output formats

**Usage:**
```bash
./bandwidth-monitor.sh                    # Monitor all interfaces
./bandwidth-monitor.sh -i eth0 -g        # Monitor eth0 with graph
sudo ./bandwidth-monitor.sh -p -t 5      # Top 5 processes by bandwidth
```

---

**Note**: Some scripts may require root privileges for network operations.

