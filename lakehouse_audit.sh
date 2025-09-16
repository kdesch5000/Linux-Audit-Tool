#!/bin/bash

# Lakehouse Security Audit Script
# Connects to lakehouse.ooguy.com and performs comprehensive security analysis

REMOTE_HOST="lakehouse.ooguy.com"
REMOTE_PORT="15069"
REMOTE_USER="kdesch"
EMAIL="kdesch@me.com"
AUDIT_LOG="/tmp/lakehouse_audit_$(date +%Y%m%d_%H%M%S).log"

echo "=== LAKEHOUSE SECURITY AUDIT - $(date) ===" > "$AUDIT_LOG"
echo "" >> "$AUDIT_LOG"

# Function to run remote commands and log results
run_remote() {
    local description="$1"
    local command="$2"
    echo "--- $description ---" >> "$AUDIT_LOG"
    ssh -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "$command" >> "$AUDIT_LOG" 2>&1
    echo "" >> "$AUDIT_LOG"
}

echo "Starting security audit of $REMOTE_HOST..."

# System Information
run_remote "SYSTEM INFORMATION" "uname -a && hostname && date"
run_remote "UPTIME AND LOAD" "uptime"
run_remote "MEMORY USAGE" "free -h"
run_remote "DISK USAGE" "df -h"
run_remote "CPU INFO" "cat /proc/cpuinfo | grep 'model name' | head -1"

# Process Analysis
run_remote "TOP PROCESSES BY CPU" "ps aux --sort=-%cpu | head -10"
run_remote "TOP PROCESSES BY MEMORY" "ps aux --sort=-%mem | head -10"
run_remote "PROCESS COUNT" "ps aux | wc -l"

# Network Security
run_remote "LISTENING PORTS" "ss -tuln"
run_remote "NETWORK CONNECTIONS" "ss -tupn | head -20"
run_remote "FIREWALL STATUS" "sudo ufw status verbose 2>/dev/null || iptables -L 2>/dev/null || echo 'No firewall info available'"

# User and Security Analysis
run_remote "USER ACCOUNTS" "cat /etc/passwd | grep -E '(bash|sh)$'"
run_remote "SUDO USERS" "grep -E '^sudo|^admin|^wheel' /etc/group 2>/dev/null || echo 'No sudo group info'"
run_remote "RECENT LOGINS" "last | head -10"
run_remote "FAILED LOGIN ATTEMPTS" "grep 'Failed password' /var/log/auth.log 2>/dev/null | tail -10 || echo 'No auth log access'"

# System Services
run_remote "ACTIVE SERVICES" "systemctl list-units --type=service --state=active | head -20"
run_remote "FAILED SERVICES" "systemctl list-units --type=service --state=failed"

# Security Updates
run_remote "SECURITY UPDATES" "apt list --upgradable 2>/dev/null | grep -i security || echo 'No apt access or no security updates'"

# SSH Configuration
run_remote "SSH CONFIG" "grep -E '^(PasswordAuthentication|PermitRootLogin|Port|MaxAuthTries)' /etc/ssh/sshd_config 2>/dev/null || echo 'No SSH config access'"

# Cron Jobs
run_remote "USER CRON JOBS" "crontab -l 2>/dev/null || echo 'No user cron jobs'"
run_remote "SYSTEM CRON JOBS" "ls -la /etc/cron* 2>/dev/null | head -20 || echo 'Limited cron access'"

# Log Analysis
run_remote "RECENT SYSTEM LOGS" "tail -20 /var/log/syslog 2>/dev/null || journalctl -n 20 2>/dev/null || echo 'No log access'"
run_remote "KERNEL MESSAGES" "dmesg | tail -10 2>/dev/null || echo 'No dmesg access'"

# File Permissions Check
run_remote "WORLD WRITABLE FILES" "find /tmp -type f -perm -002 2>/dev/null | head -10 || echo 'Limited file system access'"

echo "Audit completed. Results saved to $AUDIT_LOG"

# Analyze results and create summary
{
    echo "Subject: Lakehouse Security Audit Results - $(date +%Y-%m-%d)"
    echo "To: $EMAIL"
    echo ""
    echo "LAKEHOUSE SECURITY AUDIT SUMMARY"
    echo "================================="
    echo "Date: $(date)"
    echo "Host: $REMOTE_HOST:$REMOTE_PORT"
    echo ""
    echo "SYSTEM STATUS:"

    # Extract key metrics from log
    if grep -q "load average" "$AUDIT_LOG"; then
        echo "- Load Average: $(grep 'load average' "$AUDIT_LOG" | tail -1 | sed 's/.*load average: //')"
    fi

    if grep -q "Mem:" "$AUDIT_LOG"; then
        echo "- Memory: $(grep -A1 'MEMORY USAGE' "$AUDIT_LOG" | tail -1)"
    fi

    if grep -q "Filesystem" "$AUDIT_LOG"; then
        echo "- Disk Usage:"
        grep -A10 'DISK USAGE' "$AUDIT_LOG" | grep -v "DISK USAGE" | grep -v "^$" | head -5
    fi

    echo ""
    echo "SECURITY FINDINGS:"

    # Check for failed logins
    if grep -q "Failed password" "$AUDIT_LOG"; then
        echo "⚠️  ALERT: Failed login attempts detected:"
        grep "Failed password" "$AUDIT_LOG" | tail -3
    else
        echo "✅ No recent failed login attempts"
    fi

    # Check for failed services
    if grep -A5 'FAILED SERVICES' "$AUDIT_LOG" | grep -q "failed"; then
        echo "⚠️  WARNING: Failed services detected:"
        grep -A10 'FAILED SERVICES' "$AUDIT_LOG" | grep "failed"
    else
        echo "✅ All services running normally"
    fi

    # Check for listening ports
    if grep -q ":22\|:80\|:443\|:3389" "$AUDIT_LOG"; then
        echo "ℹ️  Common ports detected in listening services"
    fi

    echo ""
    echo "RECOMMENDATIONS:"
    echo "1. Review full audit log at: $AUDIT_LOG"
    echo "2. Apply any available security updates"
    echo "3. Monitor failed login attempts"
    echo "4. Verify all running services are necessary"
    echo ""
    echo "Full audit log attached/available on system."

} | sendmail "$EMAIL"

echo "Summary emailed to $EMAIL"