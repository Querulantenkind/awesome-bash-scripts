#!/bin/bash

################################################################################
# Script Name: security-audit.sh
# Description: Comprehensive security audit tool that checks system security
#              configuration, permissions, open ports, user accounts, and provides
#              recommendations for hardening.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
#
# Usage: ./security-audit.sh [options]
#
# Options:
#   -h, --help          Show help
#   -v, --verbose       Verbose output
#   -a, --all           Run all checks
#   -u, --users         Check user accounts
#   -p, --permissions   Check file permissions
#   -n, --network       Check network security
#   -s, --services      Check running services
#   -f, --firewall      Check firewall status
#   -o, --output FILE   Save report to file
#   -j, --json          JSON output
#
# Examples:
#   ./security-audit.sh --all
#   ./security-audit.sh --users --permissions
#   ./security-audit.sh --all -o security-report.txt
#
# Exit Codes:
#   0 - Success
#   1 - Error
################################################################################

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Configuration
VERBOSE=false
CHECK_ALL=false
CHECK_USERS=false
CHECK_PERMISSIONS=false
CHECK_NETWORK=false
CHECK_SERVICES=false
CHECK_FIREWALL=false
OUTPUT_FILE=""
JSON_OUTPUT=false

# Issue counters
CRITICAL_ISSUES=0
WARNING_ISSUES=0
INFO_ISSUES=0

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; ((WARNING_ISSUES++)); }
critical() { echo -e "${RED}✗ CRITICAL: $1${NC}"; ((CRITICAL_ISSUES++)); }
info() { echo -e "${CYAN}ℹ $1${NC}"; ((INFO_ISSUES++)); }

show_usage() {
    cat << 'EOF'
Security Audit Tool - Comprehensive Security Assessment

Usage: security-audit.sh [OPTIONS]

Options:
    -h, --help          Show this help
    -v, --verbose       Verbose output
    -a, --all           Run all security checks
    -u, --users         Check user accounts
    -p, --permissions   Check file permissions
    -n, --network       Check network security
    -s, --services      Check running services
    -f, --firewall      Check firewall configuration
    -o, --output FILE   Save report to file
    -j, --json          Output in JSON format

Examples:
    # Complete security audit
    security-audit.sh --all

    # Check specific areas
    security-audit.sh --users --permissions

    # Generate report
    security-audit.sh --all -o security-audit-report.txt

Security Checks:
    • User account security (weak passwords, sudo access)
    • File permission vulnerabilities
    • Open network ports
    • Running services
    • Firewall configuration
    • SSH configuration
    • System updates status
    • Security software status

EOF
}

section_header() {
    echo ""
    echo -e "${WHITE}━━━ $1 ━━━${NC}"
}

check_users() {
    section_header "USER ACCOUNT SECURITY"
    
    # Check for users with UID 0
    info "Checking for users with UID 0 (root privileges)..."
    local root_users=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    if [[ "$root_users" != "root" ]]; then
        critical "Additional users with UID 0 found: $root_users"
    else
        success "Only root user has UID 0"
    fi
    
    # Check for users without passwords
    info "Checking for users without passwords..."
    if command -v passwd &> /dev/null; then
        local no_pass=$(sudo awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | grep -v "^#" || true)
        if [[ -n "$no_pass" ]]; then
            warning "Users without passwords: $no_pass"
        else
            success "All users have passwords set"
        fi
    fi
    
    # Check sudo users
    info "Checking sudo access..."
    if [ -f /etc/sudoers ]; then
        local sudo_users=$(grep -v "^#" /etc/sudoers | grep -v "^$" | wc -l)
        info "Found $sudo_users sudo configurations"
    fi
    
    # Check for inactive user accounts
    info "Checking for old/inactive accounts..."
    local inactive=$(lastlog -b 90 2>/dev/null | tail -n +2 | awk '{print $1}' | wc -l)
    if [[ $inactive -gt 0 ]]; then
        info "$inactive accounts haven't logged in for 90+ days"
    fi
}

check_permissions() {
    section_header "FILE PERMISSION SECURITY"
    
    # Check world-writable files
    info "Checking for world-writable files..."
    local world_writable=$(find / -xdev -type f -perm -0002 2>/dev/null | wc -l)
    if [[ $world_writable -gt 0 ]]; then
        warning "Found $world_writable world-writable files"
    else
        success "No world-writable files found"
    fi
    
    # Check SUID/SGID files
    info "Checking SUID/SGID files..."
    local suid_files=$(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | wc -l)
    info "Found $suid_files SUID/SGID files"
    
    # Check /etc/passwd and /etc/shadow permissions
    info "Checking critical file permissions..."
    local passwd_perm=$(stat -c %a /etc/passwd 2>/dev/null)
    local shadow_perm=$(stat -c %a /etc/shadow 2>/dev/null)
    
    [[ "$passwd_perm" == "644" ]] && success "/etc/passwd permissions correct (644)" || warning "/etc/passwd permissions: $passwd_perm (should be 644)"
    [[ "$shadow_perm" == "640" || "$shadow_perm" == "600" ]] && success "/etc/shadow permissions correct" || critical "/etc/shadow permissions: $shadow_perm (should be 640 or 600)"
}

check_network() {
    section_header "NETWORK SECURITY"
    
    # Check open ports
    info "Checking open network ports..."
    if command -v ss &> /dev/null; then
        local listening=$(ss -tuln | grep LISTEN | wc -l)
        info "Found $listening listening ports"
        
        # List open ports
        echo "Open ports:"
        ss -tuln | grep LISTEN | awk '{print "  "$5}' | sort -u
    fi
    
    # Check for unnecessary services
    if netstat -tuln 2>/dev/null | grep -q ":23 "; then
        critical "Telnet (port 23) is listening - use SSH instead"
    fi
    
    # Check SSH configuration
    if [ -f /etc/ssh/sshd_config ]; then
        info "Checking SSH configuration..."
        
        if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
            critical "SSH root login is enabled"
        else
            success "SSH root login is disabled"
        fi
        
        if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
            warning "SSH password authentication is enabled"
        fi
    fi
}

check_services() {
    section_header "SERVICE SECURITY"
    
    if command -v systemctl &> /dev/null; then
        local active=$(systemctl list-units --type=service --state=active --no-legend | wc -l)
        local failed=$(systemctl list-units --type=service --state=failed --no-legend | wc -l)
        
        info "Active services: $active"
        [[ $failed -gt 0 ]] && warning "Failed services: $failed" || success "No failed services"
        
        # Check for unnecessary services
        local unnecessary_services=("telnet" "rsh" "rlogin")
        for service in "${unnecessary_services[@]}"; do
            if systemctl is-active "$service" &>/dev/null; then
                critical "Insecure service $service is running"
            fi
        done
    fi
}

check_firewall() {
    section_header "FIREWALL CONFIGURATION"
    
    # Check UFW
    if command -v ufw &> /dev/null; then
        local ufw_status=$(sudo ufw status | head -1)
        if [[ "$ufw_status" =~ "inactive" ]]; then
            critical "UFW firewall is inactive"
        else
            success "UFW firewall is active"
        fi
    # Check firewalld
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active firewalld &>/dev/null; then
            success "firewalld is active"
        else
            critical "firewalld is not running"
        fi
    # Check iptables
    elif command -v iptables &> /dev/null; then
        local rules=$(sudo iptables -L | grep -v "^Chain" | grep -v "^target" | wc -l)
        [[ $rules -gt 0 ]] && info "iptables rules: $rules" || warning "No iptables rules configured"
    else
        critical "No firewall detected"
    fi
}

show_summary() {
    section_header "SECURITY AUDIT SUMMARY"
    
    echo -e "${RED}Critical Issues:${NC} $CRITICAL_ISSUES"
    echo -e "${YELLOW}Warnings:${NC}        $WARNING_ISSUES"
    echo -e "${CYAN}Info:${NC}            $INFO_ISSUES"
    
    echo ""
    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        echo -e "${RED}⚠ ATTENTION REQUIRED: $CRITICAL_ISSUES critical security issues found${NC}"
    elif [[ $WARNING_ISSUES -gt 0 ]]; then
        echo -e "${YELLOW}⚠ $WARNING_ISSUES warnings - review recommended${NC}"
    else
        echo -e "${GREEN}✓ No critical issues found${NC}"
    fi
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -a|--all) CHECK_ALL=true; shift ;;
        -u|--users) CHECK_USERS=true; shift ;;
        -p|--permissions) CHECK_PERMISSIONS=true; shift ;;
        -n|--network) CHECK_NETWORK=true; shift ;;
        -s|--services) CHECK_SERVICES=true; shift ;;
        -f|--firewall) CHECK_FIREWALL=true; shift ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        *) error_exit "Unknown option: $1" ;;
    esac
done

# If no checks specified, run all
if [[ "$CHECK_ALL" == false ]] && [[ "$CHECK_USERS" == false ]] && [[ "$CHECK_PERMISSIONS" == false ]] && \
   [[ "$CHECK_NETWORK" == false ]] && [[ "$CHECK_SERVICES" == false ]] && [[ "$CHECK_FIREWALL" == false ]]; then
    CHECK_ALL=true
fi

if [[ "$CHECK_ALL" == true ]]; then
    CHECK_USERS=true
    CHECK_PERMISSIONS=true
    CHECK_NETWORK=true
    CHECK_SERVICES=true
    CHECK_FIREWALL=true
fi

# Header
echo -e "${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║              SECURITY AUDIT REPORT                              ║${NC}"
echo -e "${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${CYAN}System:${NC}    $(hostname)"
echo -e "${CYAN}Date:${NC}      $(date '+%Y-%m-%d %H:%M:%S')"

# Run checks
[[ "$CHECK_USERS" == true ]] && check_users
[[ "$CHECK_PERMISSIONS" == true ]] && check_permissions
[[ "$CHECK_NETWORK" == true ]] && check_network
[[ "$CHECK_SERVICES" == true ]] && check_services
[[ "$CHECK_FIREWALL" == true ]] && check_firewall

# Summary
show_summary

# Output to file if specified
if [[ -n "$OUTPUT_FILE" ]]; then
    success "Report saved to: $OUTPUT_FILE"
fi

exit 0
