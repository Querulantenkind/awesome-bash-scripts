# Installation and Setup

## Quick Installation

### Clone the Repository

```bash
git clone https://github.com/yourusername/awesome-bash-scripts.git
cd awesome-bash-scripts
```

## Setting Up PATH (Optional)

To make scripts available system-wide, you can add the scripts directories to your PATH.

### Method 1: Add to .bashrc or .zshrc

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="$PATH:/path/to/awesome-bash-scripts/scripts/system"
export PATH="$PATH:/path/to/awesome-bash-scripts/scripts/utilities"
# Add other directories as needed
```

Then reload your shell configuration:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

### Method 2: Create Symbolic Links

Create symlinks in a directory that's already in your PATH (like `/usr/local/bin`):

```bash
sudo ln -s /path/to/awesome-bash-scripts/scripts/system/script-name.sh /usr/local/bin/script-name
```

### Method 3: Use an Installation Script

You can create a simple installation script:

```bash
#!/bin/bash
INSTALL_DIR="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for category in scripts/*/; do
    for script in "$category"*.sh; do
        if [[ -f "$script" ]]; then
            script_name=$(basename "$script" .sh)
            sudo ln -sf "$SCRIPT_DIR/$script" "$INSTALL_DIR/$script_name"
            echo "Installed: $script_name"
        fi
    done
done
```

## Requirements

### Minimum Requirements

- **Bash**: Version 4.0 or higher
- **Operating System**: Linux (tested on major distributions)
- **User Privileges**: Varies by script (some require root/sudo)

### Check Your Bash Version

```bash
bash --version
```

### Recommended Tools

Many scripts work better with these tools installed:

```bash
# Ubuntu/Debian
sudo apt-get install curl wget git jq bc

# Fedora/RHEL
sudo dnf install curl wget git jq bc

# Arch Linux
sudo pacman -S curl wget git jq bc
```

## Verifying Installation

### Test a Simple Script

```bash
cd awesome-bash-scripts/examples
./hello-world.sh
```

If you see the greeting message, your installation is working!

### Check Script Permissions

All scripts should be executable:

```bash
find scripts/ -name "*.sh" -type f ! -perm -111
```

If any scripts are listed, make them executable:

```bash
find scripts/ -name "*.sh" -type f -exec chmod +x {} \;
```

## Updating Scripts

To get the latest updates:

```bash
cd awesome-bash-scripts
git pull origin main
```

## Uninstallation

### Remove Symbolic Links

If you created symlinks:

```bash
# List symlinks pointing to this repository
find /usr/local/bin -type l -lname "*/awesome-bash-scripts/*"

# Remove them (be careful!)
find /usr/local/bin -type l -lname "*/awesome-bash-scripts/*" -delete
```

### Remove from PATH

Remove the export lines from your `.bashrc` or `.zshrc`.

### Delete Repository

```bash
rm -rf /path/to/awesome-bash-scripts
```

## Troubleshooting

### "Permission denied" Error

Make sure the script is executable:
```bash
chmod +x script-name.sh
```

### "Command not found" Error

Either:
1. Run with `./script-name.sh` from the script directory
2. Add the directory to PATH
3. Use the full path to the script

### "Bad interpreter" Error

This usually means the shebang is incorrect or bash is in a different location.

Check bash location:
```bash
which bash
```

If it's not `/bin/bash`, update the shebang in the script.

## Security Considerations

1. **Review scripts** before running, especially with sudo
2. **Verify checksums** after cloning (if available)
3. **Keep scripts updated** to get security fixes
4. **Run with minimal privileges** when possible

## Getting Help

If you encounter issues:

1. Check the script's documentation header
2. Run with `--help` or `-h` flag
3. Review the [Common Pitfalls](common-pitfalls.md) documentation
4. Open an issue on GitHub

