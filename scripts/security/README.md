# Security Scripts

Professional security tools for system auditing, hardening, and firewall management. These scripts help maintain security best practices and protect Linux systems.

## 🔒 Available Scripts

### 1. security-audit.sh
**Comprehensive security audit and vulnerability assessment tool**

Performs thorough security checks on user accounts, file permissions, network configuration, services, and firewall settings.

#### Features
- ✅ **User account security**: UID 0 users, passwordless accounts, sudo access
- ✅ **File permissions**: World-writable files, SUID/SGID files, critical file permissions
- ✅ **Network security**: Open ports, SSH configuration, unnecessary services
- ✅ **Service security**: Active/failed services, insecure services
- ✅ **Firewall status**: UFW, firewalld, iptables configuration
- ✅ **Issue categorization**: Critical, warnings, info
- ✅ **Detailed reporting**: Summary with severity levels
- ✅ **JSON output**: Machine-readable format
- ✅ **Selective audits**: Choose specific checks

#### Usage Examples

```bash
# Complete security audit
./security-audit.sh --all

# Check specific areas
./security-audit.sh --users --permissions

# Network security only
./security-audit.sh --network --firewall

# Generate report
./security-audit.sh --all -o security-report.txt

# JSON output for automation
./security-audit.sh --all --json -o audit.json

# Quick user and permission check
./security-audit.sh -u -p
```

#### Security Checks

**User Account Security (`-u, --users`)**
- Users with UID 0 (root privileges)
- Users without passwords
- Sudo access configuration
- Inactive/old accounts (90+ days)

**File Permission Security (`-p, --permissions`)**
- World-writable files
- SUID/SGID files count
- `/etc/passwd` permissions (should be 644)
- `/etc/shadow` permissions (should be 640/600)

**Network Security (`-n, --network`)**
- Open listening ports
- Telnet service (port 23) - critical if open
- SSH root login status
- SSH password authentication
- Network services

**Service Security (`-s, --services`)**
- Active services count
- Failed services
- Insecure services (telnet, rsh, rlogin)
- Unnecessary services

**Firewall Configuration (`-f, --firewall`)**
- UFW status and configuration
- firewalld status
- iptables rules count
- Firewall presence check

---

### 2. firewall-manager.sh
**Universal firewall management tool**

Simplified firewall control supporting UFW, firewalld, and iptables with common profiles and easy rule management.

#### Features
- ✅ **Multi-firewall support**: UFW, firewalld, iptables
- ✅ **Simple commands**: status, enable, disable, allow, deny
- ✅ **Security profiles**: SSH, web, mail, database
- ✅ **Rule management**: Easy port allow/deny
- ✅ **Status reporting**: Detailed firewall configuration
- ✅ **Auto-detection**: Automatically detects firewall type

#### Usage Examples

```bash
# Check firewall status
./firewall-manager.sh status

# Enable firewall
sudo ./firewall-manager.sh enable

# Disable firewall
sudo ./firewall-manager.sh disable

# Allow specific port
sudo ./firewall-manager.sh allow 8080

# Deny specific port
sudo ./firewall-manager.sh deny 23

# Apply security profiles
sudo ./firewall-manager.sh --profile ssh
sudo ./firewall-manager.sh --profile web
sudo ./firewall-manager.sh --profile mail
sudo ./firewall-manager.sh --profile database

# List all rules
sudo ./firewall-manager.sh list
```

#### Security Profiles

**SSH Profile**
- Allows port 22 (SSH)

**Web Profile**
- Allows port 80 (HTTP)
- Allows port 443 (HTTPS)

**Mail Profile**
- Allows port 25 (SMTP)
- Allows port 143 (IMAP)
- Allows port 993 (IMAPS)

**Database Profile**
- Allows port 3306 (MySQL)
- Allows port 5432 (PostgreSQL)

---

### 3. integrity-monitor.sh
**File integrity monitoring with baselines, JSON reporting, and notifications**

Creates cryptographic baselines for critical paths, detects file changes, permission drifts, and deletions, and can continuously watch with interval scans or export machine-friendly reports.

#### Features
- ✅ **Baseline management**: `init` to snapshot directories/files
- ✅ **Multiple hash algorithms**: sha256 (default), sha1, md5
- ✅ **JSON + text reports**: Save to `${ABS_LOG_DIR}/integrity/last-report.json`
- ✅ **Notifications**: `--notify` hooks into desktop/email/webhook channels
- ✅ **Watch mode**: Continuous scans with configurable intervals
- ✅ **Selective paths**: Add multiple `--path` targets (defaults to `/etc`)

#### Usage Examples
```bash
# Create baseline for /etc and /usr/local/bin
./integrity-monitor.sh init -p /etc -p /usr/local/bin

# Scan current state and print summary
./integrity-monitor.sh scan -p /etc -f table

# Export JSON report
./integrity-monitor.sh scan -p /etc --format json > integrity.json

# Continuous watch every 60 seconds with notifications
./integrity-monitor.sh watch -p /etc -i 60 --notify

# Show last saved report
./integrity-monitor.sh report
```

#### Workflow Tips
- Store baseline at `/var/backups/integrity-baseline.db` using `--baseline`
- Combine with cron: `0 * * * * /path/to/integrity-monitor.sh scan -p /etc >/dev/null`
- Use `--hash sha1` when aligning with legacy compliance tools
- Pair with `cloud-backup.sh` to offload baseline snapshots securely

---

## 🛡️ Security Best Practices

### Regular Security Audits

**Weekly Audits**
```bash
# Run weekly security check
./security-audit.sh --all -o "audit-$(date +%Y-%m-%d).txt"
```

**Monthly Deep Audit**
```bash
# Comprehensive monthly audit
./security-audit.sh --all --verbose -o monthly-audit.txt
```

**Automated Audits**
```bash
#!/bin/bash
# /usr/local/bin/daily-security-check.sh

REPORT=$(/path/to/security-audit.sh --all)
CRITICAL=$(echo "$REPORT" | grep "Critical Issues:" | awk '{print $3}')

if [ "$CRITICAL" -gt 0 ]; then
    echo "$REPORT" | mail -s "Security Alert: $CRITICAL Critical Issues" admin@example.com
fi
```

Add to crontab:
```bash
# Daily security check at 3 AM
0 3 * * * /usr/local/bin/daily-security-check.sh
```

### Firewall Management

**Initial Setup**
```bash
# 1. Enable firewall
sudo ./firewall-manager.sh enable

# 2. Allow only necessary services
sudo ./firewall-manager.sh --profile ssh

# 3. Check status
sudo ./firewall-manager.sh status
```

**Adding Services**
```bash
# Web server
sudo ./firewall-manager.sh allow 80
sudo ./firewall-manager.sh allow 443

# Or use profile
sudo ./firewall-manager.sh --profile web
```

**Removing Services**
```bash
# Close unnecessary ports
sudo ./firewall-manager.sh deny 23  # Telnet
sudo ./firewall-manager.sh deny 21  # FTP
```

---

## 🎯 Common Security Workflows

### New Server Setup
```bash
# 1. Run initial security audit
./security-audit.sh --all -o initial-audit.txt

# 2. Enable and configure firewall
sudo ./firewall-manager.sh enable
sudo ./firewall-manager.sh --profile ssh

# 3. Review audit findings
cat initial-audit.txt

# 4. Fix critical issues
# (Follow recommendations from audit)

# 5. Run audit again
./security-audit.sh --all -o post-hardening-audit.txt
```

### Security Hardening
```bash
# 1. Audit current state
./security-audit.sh --all -o before-hardening.txt

# 2. Fix user issues
# Remove users with UID 0 (except root)
# Set passwords for all accounts
# Review sudo access

# 3. Fix permission issues
chmod 644 /etc/passwd
chmod 640 /etc/shadow
# Fix world-writable files

# 4. Configure firewall
sudo ./firewall-manager.sh enable
sudo ./firewall-manager.sh --profile ssh

# 5. Disable unnecessary services
sudo systemctl disable telnet
sudo systemctl stop rsh

# 6. Verify hardening
./security-audit.sh --all -o after-hardening.txt
```

### Compliance Checking
```bash
#!/bin/bash
# Check compliance with security baseline

echo "=== Security Compliance Report ===" > compliance-report.txt
echo "Date: $(date)" >> compliance-report.txt
echo "" >> compliance-report.txt

/path/to/security-audit.sh --all >> compliance-report.txt

# Check for critical issues
CRITICAL=$(grep "Critical Issues:" compliance-report.txt | awk '{print $3}')

if [ "$CRITICAL" -eq 0 ]; then
    echo "COMPLIANT: No critical issues found" >> compliance-report.txt
else
    echo "NON-COMPLIANT: $CRITICAL critical issues found" >> compliance-report.txt
fi
```

### Incident Response
```bash
# 1. Immediate security assessment
./security-audit.sh --all -o incident-audit-$(date +%Y%m%d-%H%M).txt

# 2. Check active connections
./security-audit.sh --network -o network-status.txt

# 3. Review user activity
./security-audit.sh --users -o user-activity.txt

# 4. Lock down if needed
sudo ./firewall-manager.sh deny all
sudo ./firewall-manager.sh --profile ssh
```

---

## 📋 Automation Examples

### Daily Security Monitoring
```bash
#!/bin/bash
# /usr/local/bin/daily-security-monitor.sh

DATE=$(date +%Y-%m-%d)
LOG_DIR="/var/log/security-audits"
mkdir -p "$LOG_DIR"

# Run audit
/path/to/security-audit.sh --all -o "$LOG_DIR/audit-$DATE.txt"

# Check for critical issues
CRITICAL=$(grep "Critical Issues:" "$LOG_DIR/audit-$DATE.txt" | awk '{print $3}')

if [ "$CRITICAL" -gt 0 ]; then
    # Send alert
    mail -s "Security Alert: $CRITICAL Critical Issues - $DATE" admin@example.com < "$LOG_DIR/audit-$DATE.txt"
fi
```

### Firewall Backup and Restore
```bash
#!/bin/bash
# Backup firewall rules

BACKUP_DIR="/var/backups/firewall"
mkdir -p "$BACKUP_DIR"

if command -v ufw &> /dev/null; then
    sudo ufw status numbered > "$BACKUP_DIR/ufw-backup-$(date +%Y%m%d).txt"
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --list-all > "$BACKUP_DIR/firewalld-backup-$(date +%Y%m%d).txt"
elif command -v iptables &> /dev/null; then
    sudo iptables-save > "$BACKUP_DIR/iptables-backup-$(date +%Y%m%d).rules"
fi
```

---

## 🔍 Security Checklist

### Critical Items (Fix Immediately)
- [ ] Multiple users with UID 0
- [ ] Users without passwords
- [ ] World-writable files in critical directories
- [ ] Insecure `/etc/shadow` permissions
- [ ] Telnet service running (port 23)
- [ ] SSH root login enabled
- [ ] No firewall configured

### High Priority
- [ ] Excessive SUID/SGID files
- [ ] SSH password authentication enabled
- [ ] Unnecessary services running
- [ ] Failed services present
- [ ] Weak firewall rules

### Medium Priority
- [ ] Inactive user accounts (90+ days)
- [ ] Sudo access review
- [ ] Open ports review
- [ ] Service configuration review

### Maintenance
- [ ] Regular security audits scheduled
- [ ] Firewall rules documented
- [ ] Security logs monitored
- [ ] Updates applied regularly

---

## 🚨 Common Security Issues and Fixes

### Issue: Multiple UID 0 Users
**Problem**: Additional users with root privileges
**Fix**:
```bash
# List users with UID 0
awk -F: '$3 == 0 {print $1}' /etc/passwd

# Remove or change UID for non-root users
sudo usermod -u 1001 suspicious_user
```

### Issue: Users Without Passwords
**Problem**: Accounts can be accessed without authentication
**Fix**:
```bash
# Lock the account
sudo passwd -l username

# Or set a password
sudo passwd username
```

### Issue: World-Writable Files
**Problem**: Any user can modify files
**Fix**:
```bash
# Find world-writable files
find / -xdev -type f -perm -0002 -ls

# Fix permissions
chmod o-w /path/to/file
```

### Issue: SSH Root Login Enabled
**Problem**: Direct root SSH access is insecure
**Fix**:
```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Change to:
PermitRootLogin no

# Restart SSH
sudo systemctl restart sshd
```

### Issue: No Firewall
**Problem**: All ports are accessible
**Fix**:
```bash
# Enable firewall
sudo ./firewall-manager.sh enable

# Configure basic rules
sudo ./firewall-manager.sh --profile ssh
```

---

## 📊 Security Metrics

### Audit Score Interpretation

**Critical Issues: 0**
- System is secure
- Regular monitoring recommended

**Critical Issues: 1-3**
- Address issues promptly
- Review security policies

**Critical Issues: 4+**
- Immediate action required
- Comprehensive security review needed

**Warnings: 0-5**
- Normal range
- Review recommendations

**Warnings: 6-10**
- Consider addressing warnings
- May indicate configuration issues

**Warnings: 11+**
- Review system configuration
- May need security hardening

---

## 🔧 Troubleshooting

### Security Audit

**Requires root privileges**
```bash
# Run with sudo
sudo ./security-audit.sh --all
```

**Slow execution**
```bash
# Run specific checks only
./security-audit.sh --users --permissions
```

**False positives**
```bash
# Review each issue carefully
# Some configurations may be intentional
# Document exceptions
```

### Firewall Manager

**Firewall not detected**
```bash
# Check available firewalls
which ufw firewall-cmd iptables

# Install appropriate firewall
sudo apt-get install ufw  # Ubuntu/Debian
sudo dnf install firewalld  # Fedora/RHEL
```

**Rules not persisting**
```bash
# UFW
sudo ufw enable

# firewalld
sudo firewall-cmd --runtime-to-permanent

# iptables
sudo iptables-save > /etc/iptables/rules.v4
```

---

## ⚠️ Important Warnings

- **Security audits require root privileges** for complete checks
- **Review before applying fixes** - some configurations may be intentional
- **Test firewall changes** in non-production environment first
- **Backup firewall rules** before making changes
- **Document security decisions** and exceptions
- **Regular audits are essential** - run at least weekly
- **Keep audit logs** for compliance and investigation
- **Never disable firewall** without understanding the risks

---

## 📚 Additional Security Resources

### Security Standards
- CIS Benchmarks (https://www.cisecurity.org/cis-benchmarks/)
- NIST Security Guidelines
- OWASP Top 10

### Security Tools
- `lynis` - Security auditing tool
- `rkhunter` - Rootkit hunter
- `chkrootkit` - Rootkit checker
- `fail2ban` - Intrusion prevention

### Best Practices
- Principle of least privilege
- Defense in depth
- Regular updates and patches
- Strong authentication
- Network segmentation
- Security monitoring and logging

---

**Stay Secure!** 🔒

For issues or suggestions, please open an issue on the repository.
