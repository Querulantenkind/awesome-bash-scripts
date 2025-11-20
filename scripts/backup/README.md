# Backup Scripts

Professional backup solutions for data protection, disaster recovery, and system backups. These scripts provide comprehensive backup strategies with compression, encryption, rotation, and restore capabilities.

## 📦 Available Scripts

### 1. backup-manager.sh
**Comprehensive backup solution with full, incremental, and differential backups**

A full-featured backup manager supporting multiple backup strategies, compression methods, encryption, and intelligent rotation.

#### Features
- ✅ **Multiple backup types**: Full, incremental, differential
- ✅ **Compression**: gzip, bzip2, xz, or none
- ✅ **GPG encryption**: Secure backups with public key encryption
- ✅ **Backup rotation**: Automatic cleanup of old backups
- ✅ **Metadata tracking**: Detailed backup information and checksums
- ✅ **Exclude patterns**: Skip specific files or directories
- ✅ **Verification**: Integrity checking after backup
- ✅ **Restore capability**: Full restore from backup archives
- ✅ **Dry-run mode**: Preview what will be backed up

#### Usage Examples

```bash
# Full backup with compression
./backup-manager.sh -s /home/user -d /backup -t full -m xz

# Incremental backup
./backup-manager.sh -s /var/www -d /backup -t incremental

# Encrypted backup
./backup-manager.sh -s /home -d /backup -e -k user@example.com

# Backup with exclusions
./backup-manager.sh -s /home -d /backup -x "*.tmp" -x "*.cache" -x ".git/"

# Restore from backup
./backup-manager.sh --restore /backup/full-2024-11-20.tar.gz -d /restore

# List available backups
./backup-manager.sh --list -d /backup

# Dry run
./backup-manager.sh -s /data -d /backup --dry-run
```

---

### 2. database-backup.sh
**Automated database backup for MySQL/MariaDB, PostgreSQL, MongoDB, and SQLite**

Specialized database backup tool with support for multiple database systems, compression, encryption, and automated rotation.

#### Features
- ✅ **Multi-database support**: MySQL/MariaDB, PostgreSQL, MongoDB, SQLite
- ✅ **All databases option**: Backup all databases at once
- ✅ **Compression**: gzip compression
- ✅ **GPG encryption**: Secure encrypted backups
- ✅ **Automatic rotation**: Keep only N most recent backups
- ✅ **Metadata**: Detailed backup information and checksums
- ✅ **Configuration file**: Store credentials securely
- ✅ **Logging**: Comprehensive backup logs

#### Usage Examples

```bash
# MySQL backup
./database-backup.sh -t mysql -u root -d mydb -o /backup -c

# PostgreSQL backup (all databases)
./database-backup.sh -t postgresql -u postgres -d all -o /backup

# MongoDB with encryption
./database-backup.sh -t mongodb -d mydb -o /backup -e -k user@example.com

# SQLite backup
./database-backup.sh -t sqlite -d /path/to/database.db -o /backup

# Using configuration file
./database-backup.sh --config /etc/db-backup.conf

# List backups
./database-backup.sh --list -o /backup
```

#### Configuration File Example

```bash
# /etc/db-backup.conf
DB_TYPE=mysql
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=secret
DB_NAME=all
OUTPUT_DIR=/backup/databases
ENABLE_COMPRESS=true
ENABLE_ENCRYPT=false
ROTATION_COUNT=14
```

---

### 3. sync-backup.sh
**Rsync-based incremental backups and synchronization**

Efficient sync-based backup using rsync with support for remote backups, bandwidth limiting, and space-efficient hardlinked incremental backups.

#### Features
- ✅ **Rsync-based**: Fast, efficient incremental backups
- ✅ **Remote backups**: SSH support for remote destinations
- ✅ **Bandwidth limiting**: Control network usage
- ✅ **Hardlinked incrementals**: Space-efficient backups
- ✅ **Archive directory**: Keep deleted/changed files
- ✅ **Exclude patterns**: Skip unwanted files
- ✅ **Compression**: On-the-fly compression
- ✅ **Checksum verification**: Ensure file integrity
- ✅ **Progress tracking**: Detailed sync statistics
- ✅ **Dry-run mode**: Test before actual sync

#### Usage Examples

```bash
# Local backup
./sync-backup.sh -s /home/user -d /backup/home

# Remote backup over SSH
./sync-backup.sh -s /var/www -r backup.server.com -u backupuser

# Sync with exclusions and deletion
./sync-backup.sh -s /data -d /backup -x "*.tmp" -x "cache/" --delete

# Incremental with archive
./sync-backup.sh -s /home -d /backup/current --backup-dir /backup/archive

# Hardlinked incremental (space-efficient)
./sync-backup.sh -s /home -d /backup/2024-11-20 --link-dest /backup/2024-11-19

# Bandwidth-limited remote backup
./sync-backup.sh -s /data -r backup.host.com -b 1000 --compress

# Dry run
./sync-backup.sh -s /home -d /backup --dry-run --progress
```

---

### 4. cloud-backup.sh
**Hybrid cloud backup orchestrator with rclone integration and encryption**

Seamlessly packages local data, optionally encrypts it, and ships to both local targets and any rclone-supported remote (S3, Backblaze, OneDrive, etc.). Includes retention, alerting, JSON exports, and profiles.

#### Features
- ✅ **Multi-target delivery**: Local cache + any rclone remote
- ✅ **Compression profiles**: `tar.gz`, `tar.xz`, `tar.zst`, or raw tar
- ✅ **Encryption**: GPG symmetric or age recipients
- ✅ **Retention policies**: Local pruning + remote `--min-age` cleanup
- ✅ **Alerts & verification**: Checksums, optional alerts via notifications
- ✅ **Profiles**: Load reusable configs from `~/.config/awesome-bash-scripts`
- ✅ **Output formats**: Human summary, machine-friendly JSON, CSV
- ✅ **Dry-run planner**: Show actions without touching data

#### Usage Examples

```bash
# Backup /srv to Backblaze B2 with GPG encryption
./cloud-backup.sh -s /srv -r b2:company/backups --encrypt gpg --key-file ~/.keys/b2.pass

# Local staging with tar.xz compression and 14-day retention
./cloud-backup.sh -s /var/log -d /backups/logs --compression tar.xz --retention 14

# JSON summary for automation pipelines
./cloud-backup.sh -s /data --remote s3:prod/backups --json

# Dry-run planner
./cloud-backup.sh -s /srv/app --remote onedrive:abs --dry-run

# Restore from remote archive to /restore
./cloud-backup.sh --restore srv-20241120-0100.tar.gz --target /restore --remote b2:company/backups
```

#### Notes
- Metadata stored under `${ABS_LOG_DIR}/cloud-backups`
- `--profile NAME` loads configs from `~/.config/awesome-bash-scripts/profiles/cloud-backup/`
- Use `--bandwidth` to throttle rclone uploads (KB/s)
- JSON/CSV output integrates with Prometheus, SIEM, or custom dashboards

---

## 🛡️ Backup Strategies

### Full Backups
Complete backup of all specified data. Best for:
- Initial backups
- Weekly/monthly comprehensive backups
- System snapshots
- Archive creation

### Incremental Backups
Only backs up files changed since the last backup (full or incremental). Best for:
- Daily backups
- Minimal storage usage
- Fast backup operations
- Continuous backup schedules

### Differential Backups
Backs up files changed since the last full backup. Best for:
- Balance between full and incremental
- Easier restore process than incremental
- Regular scheduled backups

### Sync-Based Backups
Mirrors source to destination with efficient updates. Best for:
- Continuous synchronization
- Server mirroring
- Remote backups
- Space-efficient incrementals with hardlinks

---

## 📋 Best Practices

### 1. The 3-2-1 Backup Rule
- **3** copies of data
- **2** different storage types
- **1** offsite copy

### 2. Test Your Backups
```bash
# Regular restore tests
./backup-manager.sh --restore /backup/latest.tar.gz -d /tmp/test-restore
```

### 3. Automate Backups
```bash
# Crontab examples

# Daily incremental backup at 2 AM
0 2 * * * /path/to/backup-manager.sh -s /home -d /backup -t incremental -l /var/log/backup.log

# Weekly full backup on Sunday
0 3 * * 0 /path/to/backup-manager.sh -s /home -d /backup -t full -m xz -l /var/log/backup.log

# Daily database backup at 1 AM
0 1 * * * /path/to/database-backup.sh -t mysql -d all -o /backup/db -c -r 7

# Hourly sync to remote server
0 * * * * /path/to/sync-backup.sh -s /var/www -r backup.server.com -u backup --compress
```

### 4. Monitor Backup Success
```bash
# Check last backup status
tail -n 50 /var/log/backup.log

# Verify backup integrity
./backup-manager.sh --verify /backup/latest.tar.gz
```

### 5. Secure Sensitive Backups
```bash
# Always encrypt sensitive data
./backup-manager.sh -s /sensitive -d /backup -e -k admin@example.com

# Use encrypted databases backups
./database-backup.sh -t mysql -d sensitive_db -o /backup -e -k admin@example.com

# Protect backup directories
chmod 700 /backup
```

---

## 🔧 Dependencies

### Required
- `tar` - Archive creation (backup-manager)
- `sha256sum` - Checksum verification
- `rsync` - Sync operations (sync-backup)

### Database Tools
- `mysqldump` - MySQL/MariaDB backups
- `pg_dump`, `pg_dumpall` - PostgreSQL backups
- `mongodump` - MongoDB backups
- `sqlite3` - SQLite backups

### Optional
- `gzip`, `bzip2`, `xz` - Compression
- `gpg` - Encryption
- `ssh` - Remote backups

### Installation

**Ubuntu/Debian:**
```bash
sudo apt-get install tar rsync gzip bzip2 xz-utils gpg openssh-client
sudo apt-get install mysql-client postgresql-client mongodb-clients sqlite3
```

**Fedora/RHEL:**
```bash
sudo dnf install tar rsync gzip bzip2 xz gpg openssh-clients
sudo dnf install mysql postgresql mongodb-database sqlite
```

**Arch Linux:**
```bash
sudo pacman -S tar rsync gzip bzip2 xz gpg openssh
sudo pacman -S mysql-clients postgresql mongodb-tools sqlite
```

---

## 📊 Storage Calculations

### Backup Size Estimates
- **Full backup**: 100% of source data
- **Incremental**: ~5-20% of full backup (varies by change rate)
- **Differential**: Grows between full backups
- **Compressed**: ~30-70% reduction (depends on data type)

### Rotation Planning
```bash
# 7 daily incrementals + 1 weekly full = ~8-10 full backups worth of storage
# 30 daily rotations ≈ 30 days of backup history

# Calculate storage needed
SOURCE_SIZE=$(du -sh /home/user | awk '{print $1}')
# Daily incremental: ~10% of source
# Weekly full: 100% of source
# Monthly storage: ~4 full + 28 incremental ≈ 6.8x source size compressed
```

---

## 🔄 Recovery Procedures

### Full System Restore
```bash
# 1. Restore latest full backup
./backup-manager.sh --restore /backup/full-latest.tar.gz -d /restore

# 2. Apply incremental backups in order (if used)
./backup-manager.sh --restore /backup/incremental-1.tar.gz -d /restore
./backup-manager.sh --restore /backup/incremental-2.tar.gz -d /restore

# 3. Verify restored files
diff -r /original /restore
```

### Database Recovery
```bash
# MySQL restore
mysql -u root -p database_name < backup.sql

# PostgreSQL restore
psql -U postgres < backup.sql

# MongoDB restore
mongorestore --db database_name /path/to/backup/

# SQLite restore
cp backup.db /path/to/database.db
```

### Sync-Based Recovery
```bash
# Reverse sync to restore
./sync-backup.sh -s /backup/current -d /home/user --dry-run
# If looks good, remove --dry-run
```

---

## 📝 Logging and Monitoring

### Enable Logging
```bash
# All scripts support logging
./backup-manager.sh -s /data -d /backup -l /var/log/backup.log
./database-backup.sh -t mysql -d all -o /backup -l /var/log/db-backup.log
./sync-backup.sh -s /home -d /backup -l /var/log/sync.log
```

### Monitor Logs
```bash
# View recent backup activity
tail -f /var/log/backup.log

# Check for errors
grep ERROR /var/log/backup.log

# Backup statistics
grep "completed successfully" /var/log/backup.log | wc -l
```

### Email Notifications
```bash
#!/bin/bash
# backup-with-notification.sh
./backup-manager.sh -s /data -d /backup -l /var/log/backup.log

if [ $? -eq 0 ]; then
    echo "Backup completed successfully" | mail -s "Backup Success" admin@example.com
else
    echo "Backup failed! Check logs" | mail -s "Backup FAILED" admin@example.com
fi
```

---

## 🎯 Use Cases

### Home User
```bash
# Daily documents backup
./backup-manager.sh -s ~/Documents -d /backup -t incremental -m gzip

# Weekly full backup of home directory
./backup-manager.sh -s /home/user -d /backup -t full -m xz -r 4
```

### Small Business
```bash
# Hourly sync to NAS
./sync-backup.sh -s /var/www -d /mnt/nas/backups --compress

# Daily encrypted database backups
./database-backup.sh -t mysql -d all -o /backup -c -e -k admin@company.com

# Weekly full system backup
./backup-manager.sh -s / -d /backup -t full -x "/proc/*" -x "/sys/*" -x "/tmp/*"
```

### System Administrator
```bash
# Automated backup rotation
./backup-manager.sh -s /etc -d /backup/config -t full -r 30
./database-backup.sh -t postgresql -d all -o /backup/db -c -r 14
./sync-backup.sh -s /var/log -d /backup/logs -r backup.server.com

# Remote encrypted backups
./sync-backup.sh -s /critical/data -r offsite.backup.com -u backup --compress -b 5000
```

---

## ❗ Important Notes

- Always test backups by performing restores
- Monitor backup logs for failures
- Keep backups on separate physical devices
- Test disaster recovery procedures regularly
- Document your backup procedures
- Secure backup files with appropriate permissions
- Consider encryption for sensitive data
- Verify backup integrity periodically
- Plan for backup storage growth

---

**Happy Backing Up!** 💾

For issues or suggestions, please open an issue on the repository.
