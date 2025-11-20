# Awesome Bash Scripts 🚀

A comprehensive, production-ready collection of professional bash scripts for Linux system administration, automation, and daily tasks. Features an interactive menu system, auto-completion, centralized configuration management, and extensive documentation.

[![Scripts](https://img.shields.io/badge/scripts-53-brightgreen)](scripts/)
[![Categories](https://img.shields.io/badge/categories-10%2F10-success)](scripts/)
[![Complete](https://img.shields.io/badge/status-100%25%20complete-success)](scripts/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## ✨ Key Features

- **53 Production-Ready Scripts** across all 10 categories
- **Interactive Menu System** for easy browsing and execution
- **Auto-Completion** for Bash and Zsh
- **Configuration Management** with profiles and presets
- **Comprehensive Testing Framework** with unit and integration tests
- **Shared Libraries** for consistent functionality
- **Multi-Channel Notifications** (desktop, email, webhooks)
- **Professional Documentation** with examples and best practices

## 📁 Repository Structure

```
awesome-bash-scripts/
├── install.sh              # Universal installer with dependency management
├── awesome-bash.sh         # Interactive TUI menu system
├── lib/                    # Shared libraries
│   ├── common.sh          # Core utilities and helpers
│   ├── colors.sh          # ANSI color codes and formatting
│   ├── config.sh          # Configuration management
│   └── notifications.sh   # Multi-channel notifications
├── completions/           # Shell auto-completion
│   ├── abs-completion.bash # Bash completion
│   └── _abs               # Zsh completion
├── scripts/               # Main scripts directory
│   ├── monitoring/       # 8 scripts - System & service monitoring
│   ├── backup/           # 6 scripts - Backup and recovery
│   ├── file-management/  # 5 scripts - File operations
│   ├── system/           # 6 scripts - System administration
│   ├── security/         # 4 scripts - Security auditing
│   ├── network/          # 6 scripts - Network tools
│   ├── utilities/        # 6 scripts - General utilities
│   ├── development/      # 4 scripts - Development tools
│   ├── media/            # 4 scripts - Media processing
│   └── database/         # 4 scripts - Database management
├── tests/                # Testing framework
│   ├── test-runner.sh    # Comprehensive test runner
│   ├── unit/            # Unit tests
│   └── integration/     # Integration tests
├── templates/            # Script templates
├── examples/             # Example scripts
├── docs/                 # Documentation
│   ├── best-practices.md
│   ├── common-pitfalls.md
│   ├── installation.md
│   └── testing.md
├── CONTRIBUTING.md       # Contribution guidelines
├── PROJECT-OVERVIEW.md   # Detailed project overview
├── LICENSE              # MIT License
└── README.md           # This file
```

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/awesome-bash-scripts.git
cd awesome-bash-scripts

# Install (user installation - recommended)
./install.sh

# Or system-wide installation
sudo ./install.sh --system
```

The installer will:
- ✅ Install all dependencies automatically
- ✅ Set up auto-completion for Bash/Zsh
- ✅ Create convenient `abs-` prefixed commands in your PATH
- ✅ Configure default settings

### Interactive Menu (Recommended)

```bash
# Launch interactive menu
./awesome-bash.sh

# Or after installation
awesome-bash
```

The interactive menu provides:
- 📂 Browse scripts by category
- 🔍 Search by name or description
- ℹ️ View script information and usage
- ▶️ Execute scripts with guided prompts
- ⚙️ Access configuration manager
- 📖 Built-in help system

### Using Individual Scripts

```bash
# After installation, all scripts available with abs- prefix
abs-system-monitor --help
abs-password-generator -l 32
abs-port-scanner example.com

# Tab completion works!
abs-<TAB><TAB>  # Shows all available scripts
abs-system-monitor --<TAB><TAB>  # Shows all options

# Or run directly from repository
./scripts/monitoring/system-monitor.sh --help
```

### Configuration Management

```bash
# Interactive configuration
abs-config-manager interactive

# Command-line operations
abs-config-manager get ABS_LOG_LEVEL
abs-config-manager set ABS_VERBOSE true
abs-config-manager list

# Profile management
abs-config-manager profile save production
abs-config-manager profile load production
abs-config-manager profile list
```

## 📋 Script Categories

### 🖥️ Monitoring Scripts (8 scripts)
- **system-monitor.sh** - Comprehensive system resource monitoring
- **service-monitor.sh** - Systemd service health checking
- **log-analyzer.sh** - Advanced log file analysis
- **network-monitor.sh** - Network traffic monitoring
- **disk-health-monitor.sh** - S.M.A.R.T. disk health monitoring
- **ssl-certificate-monitor.sh** - SSL certificate expiration monitoring
- **process-monitor.sh** - Process resource usage monitoring and management
- **container-monitor.sh** - Docker/Podman container health monitoring

[View Monitoring Scripts →](scripts/monitoring/)

### 💾 Backup Scripts (6 scripts)
- **backup-manager.sh** - Full/incremental/differential backups
- **database-backup.sh** - Automated database backups (MySQL, PostgreSQL, MongoDB, SQLite)
- **sync-backup.sh** - Rsync-based synchronization
- **cloud-backup.sh** - Multi-cloud backup (S3, B2, GCS, Azure)
- **snapshot-manager.sh** - LVM/BTRFS snapshot management and rotation
- **restore-manager.sh** - Interactive backup restoration tool

[View Backup Scripts →](scripts/backup/)

### 📁 File Management Scripts (5 scripts)
- **file-organizer.sh** - Intelligent file organization
- **duplicate-finder.sh** - Find and remove duplicate files
- **bulk-renamer.sh** - Powerful bulk file renaming
- **disk-space-analyzer.sh** - Disk usage analysis and visualization
- **file-archiver.sh** - Archive old files by age/access time

[View File Management Scripts →](scripts/file-management/)

### ⚙️ System Scripts (6 scripts)
- **system-info.sh** - Comprehensive system information
- **package-cleanup.sh** - Package manager cleanup
- **user-manager.sh** - User account management and auditing
- **update-manager.sh** - System update automation with hooks
- **service-manager.sh** - Systemd service management wrapper
- **cron-manager.sh** - Crontab management and validation

[View System Scripts →](scripts/system/)

### 🔒 Security Scripts (4 scripts)
- **security-audit.sh** - Security configuration audit
- **firewall-manager.sh** - Universal firewall management
- **ssh-hardening.sh** - SSH server hardening and auditing
- **fail2ban-manager.sh** - Fail2ban configuration and management

[View Security Scripts →](scripts/security/)

### 🌐 Network Scripts (6 scripts)
- **port-scanner.sh** - Advanced port scanner with service detection
- **bandwidth-monitor.sh** - Real-time bandwidth monitoring
- **dns-checker.sh** - DNS resolution testing and diagnostics
- **network-diagnostics.sh** - Comprehensive network troubleshooting
- **vpn-manager.sh** - VPN connection management (OpenVPN, WireGuard)
- **network-speed-test.sh** - Network speed and latency testing

[View Network Scripts →](scripts/network/)

### 🛠️ Utility Scripts (6 scripts)
- **password-generator.sh** - Secure password generator
- **system-benchmark.sh** - System performance benchmarking
- **config-manager.sh** - Configuration management tool
- **url-checker.sh** - Bulk URL availability and SSL checker
- **text-processor.sh** - Advanced text manipulation and parsing
- **hash-calculator.sh** - File integrity checking with multiple algorithms

[View Utility Scripts →](scripts/utilities/)

### 💻 Development Scripts (4 scripts)
- **git-toolkit.sh** - Git operations and statistics
- **project-init.sh** - Project initialization wizard
- **docker-cleanup.sh** - Docker system cleanup and optimization
- **code-formatter.sh** - Multi-language code formatting tool

[View Development Scripts →](scripts/development/)

### 🎬 Media Scripts (4 scripts)
- **video-converter.sh** - FFmpeg-based video conversion
- **image-optimizer.sh** - Batch image optimization
- **audio-converter.sh** - Audio format conversion (MP3, FLAC, WAV, OGG, AAC)
- **media-metadata.sh** - Extract and edit media file metadata

[View Media Scripts →](scripts/media/)

### 🗄️ Database Scripts (4 scripts)
- **db-monitor.sh** - Multi-database performance monitoring
- **db-query-analyzer.sh** - Query analysis and optimization
- **db-migration-tool.sh** - Database schema migration helper
- **db-backup-verify.sh** - Verify database backup integrity

[View Database Scripts →](scripts/database/)

## 🎯 Example Usage

### System Monitoring

```bash
# Real-time system monitoring
abs-system-monitor --watch

# Monitor with alerts
abs-system-monitor --cpu-alert 80 --mem-alert 80 --disk-alert 90

# JSON output for integration
abs-system-monitor --json --once > system-stats.json
```

### Backup Automation

```bash
# Full backup with compression
abs-backup-manager --backup --type full --source /home --destination /backups --compression gzip

# Incremental backup with rotation
abs-backup-manager --backup --type incremental --rotation 7

# Database backup
abs-database-backup --type mysql --database mydb --encrypt
```

### Network Tools

```bash
# Port scanning
abs-port-scanner example.com --top 100 --banner

# Bandwidth monitoring
abs-bandwidth-monitor -i eth0 --graph --alert 10MB
```

### Media Processing

```bash
# Video conversion
abs-video-converter --profile web-hd input.mov

# Batch image optimization
abs-image-optimizer -d ~/Photos --max-width 1920 -q 85
```

## 🧪 Testing

```bash
# Run all tests
./tests/test-runner.sh

# Run specific test types
./tests/test-runner.sh --unit
./tests/test-runner.sh --integration

# With coverage report
./tests/test-runner.sh --coverage

# Verbose output
./tests/test-runner.sh --verbose
```

## 📚 Documentation

- **[Installation Guide](docs/installation.md)** - Detailed installation instructions
- **[Best Practices](docs/best-practices.md)** - Guidelines for bash scripting
- **[Common Pitfalls](docs/common-pitfalls.md)** - Avoid common mistakes
- **[Testing Guide](docs/testing.md)** - How to write and run tests
- **[Contributing](CONTRIBUTING.md)** - Contribution guidelines
- **[Project Overview](PROJECT-OVERVIEW.md)** - Detailed project information

## 🔧 Requirements

### Core Requirements
- Bash 4.0 or higher
- Linux-based operating system
- Basic GNU utilities (coreutils)

### Optional Tools (installed automatically)
- `bc` - Calculator for numeric operations
- `jq` - JSON processing
- `curl` - URL transfers
- `rsync` - File synchronization
- `git` - Version control

### Script-Specific Dependencies
- **Monitoring**: `htop`, `iotop` (optional)
- **Media**: `ffmpeg`, `imagemagick`
- **Network**: `netcat`, `iperf3` (optional)
- **Security**: `ufw`, `firewalld`, or `iptables`

The installer will detect and offer to install missing dependencies.

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

### Quick Contribution Guide

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Follow the [script template](templates/script-template.sh)
4. Add tests for your changes
5. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
6. Push to the branch (`git push origin feature/AmazingFeature`)
7. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Luca**

## 🙏 Acknowledgments

- Inspired by best practices from the Linux community
- Built with feedback from system administrators worldwide
- Thanks to all contributors

## 📊 Repository Statistics

- **Total Scripts**: 53
- **Categories Filled**: 10 out of 10 (100%) ✅
- **Shared Libraries**: 4
- **Test Coverage**: Unit and integration tests
- **Documentation Files**: 8
- **Lines of Code**: 25,000+
- **Active Maintenance**: ✅ Yes
- **Status**: 🎉 **ENHANCED**

## 🗺️ Roadmap

- [x] Complete all 10 script categories ✅
- [x] Shared library system ✅
- [x] Configuration management ✅
- [x] Auto-completion ✅
- [x] Interactive menu ✅
- [x] Testing framework ✅
- [ ] Implement CI/CD pipeline
- [ ] Create Docker image
- [ ] Add web dashboard
- [ ] Package for major distributions (DEB, RPM, AUR)
- [ ] Internationalization (i18n) support
- [ ] Plugin system for extensions

## 🔗 Links

- [Repository](https://github.com/yourusername/awesome-bash-scripts)
- [Issue Tracker](https://github.com/yourusername/awesome-bash-scripts/issues)
- [Releases](https://github.com/yourusername/awesome-bash-scripts/releases)
- [Wiki](https://github.com/yourusername/awesome-bash-scripts/wiki)

## ⭐ Star History

If you find this project useful, please consider giving it a star! ⭐

---

**Made with ❤️ by the open source community**