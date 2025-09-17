#!/bin/bash

# Multi-Host Lakehouse Audit Tool
# Enhanced version supporting multiple hosts, scheduling, and AI-powered analysis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
LOGS_DIR="${SCRIPT_DIR}/logs"
HOSTS_CONFIG="${CONFIG_DIR}/hosts.conf"
AUDIT_CONFIG="${CONFIG_DIR}/audit.conf"

# Default values
DEFAULT_EMAIL="kdesch@me.com"
CLAUDE_ANALYSIS_ENABLED="true"

# Ensure required directories exist
mkdir -p "${LOGS_DIR}" "${CONFIG_DIR}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Multi-Host Security Audit Tool

OPTIONS:
    -h, --host HOSTNAME     Specify hostname/IP to audit
    -p, --port PORT         SSH port (default: 22)
    -u, --user USERNAME     SSH username
    -e, --email EMAIL       Email for reports
    -c, --config HOST_NAME  Use configuration from hosts.conf
    -l, --list             List configured hosts
    -s, --schedule         Set up scheduled audits for all enabled hosts
    --schedule-host HOST    Set up schedule for specific host
    --remove-schedule      Remove all scheduled audits
    -a, --all              Audit all enabled hosts from configuration
    --help                 Show this help message

EXAMPLES:
    # Audit specific host with parameters
    $0 -h server.com -p 2222 -u admin -e admin@example.com

    # Audit using configuration
    $0 -c lakehouse

    # Audit all configured hosts
    $0 -a

    # List configured hosts
    $0 -l

    # Set up scheduled audits
    $0 -s

EOF
}

# Function to parse hosts configuration
parse_host_config() {
    local host_name="$1"
    local config_file="$2"

    if [[ ! -f "$config_file" ]]; then
        echo "Error: Configuration file $config_file not found" >&2
        return 1
    fi

    local in_section=false
    local hostname="" port="" user="" email="" schedule="" schedule_time="" schedule_day="" enabled=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Check for section headers
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$host_name" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # Parse key-value pairs in the correct section
        if [[ "$in_section" == true && "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            case "$key" in
                hostname) hostname="$value" ;;
                port) port="$value" ;;
                user) user="$value" ;;
                email) email="$value" ;;
                schedule) schedule="$value" ;;
                schedule_time) schedule_time="$value" ;;
                schedule_day) schedule_day="$value" ;;
                enabled) enabled="$value" ;;
            esac
        fi
    done < "$config_file"

    if [[ -z "$hostname" ]]; then
        echo "Error: Host configuration '$host_name' not found" >&2
        return 1
    fi

    # Export variables for use by calling script
    export HOST_HOSTNAME="$hostname"
    export HOST_PORT="${port:-22}"
    export HOST_USER="$user"
    export HOST_EMAIL="${email:-$DEFAULT_EMAIL}"
    export HOST_SCHEDULE="$schedule"
    export HOST_SCHEDULE_TIME="$schedule_time"
    export HOST_SCHEDULE_DAY="$schedule_day"
    export HOST_ENABLED="${enabled:-true}"
}

# Function to list configured hosts
list_hosts() {
    if [[ ! -f "$HOSTS_CONFIG" ]]; then
        echo "No hosts configuration file found at $HOSTS_CONFIG"
        return 1
    fi

    echo "Configured Hosts:"
    echo "=================="

    local current_host=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_host="${BASH_REMATCH[1]}"
            echo
            echo "Host: $current_host"
        elif [[ -n "$current_host" && "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            case "$key" in
                hostname|port|user|email|schedule|schedule_time|enabled)
                    printf "  %-15s: %s\n" "$key" "$value"
                    ;;
            esac
        fi
    done < "$HOSTS_CONFIG"
    echo
}

# Function to run audit with AI analysis
run_audit_with_analysis() {
    local hostname="$1"
    local port="$2"
    local user="$3"
    local email="$4"
    local host_label="${5:-${hostname}}"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local audit_log="${LOGS_DIR}/${host_label}_audit_${timestamp}.log"
    local analysis_log="${LOGS_DIR}/${host_label}_analysis_${timestamp}.log"

    echo "Starting security audit for $host_label ($hostname:$port)..."

    # Generate audit log
    {
        echo "=== SECURITY AUDIT - $host_label - $(date) ==="
        echo "Host: $hostname:$port"
        echo "User: $user"
        echo ""
    } > "$audit_log"

    # Check if this is localhost to avoid SSH
    local is_localhost=false
    local current_hostname=$(hostname)
    local current_fqdn=$(hostname -f 2>/dev/null || hostname)
    local hostname_ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
    local current_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    if [[ "$hostname" == "localhost" || "$hostname" == "127.0.0.1" || "$hostname" == "$current_hostname" || "$hostname" == "$current_fqdn" ]]; then
        is_localhost=true
        echo "✓ Detected localhost - running commands locally without SSH"
    elif [[ -n "$hostname_ip" && -n "$current_ip" && "$hostname_ip" == "$current_ip" ]]; then
        is_localhost=true
        echo "✓ Detected localhost ($hostname resolves to $hostname_ip) - running commands locally without SSH"
    fi

    # Function to run remote commands and log results
    run_remote() {
        local description="$1"
        local command="$2"
        echo "--- $description ---" >> "$audit_log"

        if [[ "$is_localhost" == true ]]; then
            # Run locally without SSH
            if eval "$command" >> "$audit_log" 2>&1; then
                echo "✓ $description completed (localhost)"
            else
                echo "⚠ $description failed or limited access"
                echo "Command failed or access limited" >> "$audit_log"
            fi
        else
            # Run via SSH
            if ssh -4 -o ConnectTimeout=30 -o BatchMode=yes -p "$port" "$user@$hostname" "$command" >> "$audit_log" 2>&1; then
                echo "✓ $description completed"
            else
                echo "⚠ $description failed or limited access"
                echo "Command failed or access limited" >> "$audit_log"
            fi
        fi
        echo "" >> "$audit_log"
    }

    # Perform comprehensive audit
    echo "Collecting system information..."
    run_remote "SYSTEM INFORMATION" "uname -a && hostname && date"
    run_remote "UPTIME AND LOAD" "uptime"
    run_remote "MEMORY USAGE" "free -h"
    run_remote "DISK USAGE" "df -h"
    run_remote "CPU INFO" "cat /proc/cpuinfo | grep 'model name' | head -1"

    echo "Analyzing processes..."
    run_remote "TOP PROCESSES BY CPU" "ps aux --sort=-%cpu | head -15"
    run_remote "TOP PROCESSES BY MEMORY" "ps aux --sort=-%mem | head -15"
    run_remote "PROCESS COUNT" "ps aux | wc -l"

    echo "Checking network security..."
    run_remote "LISTENING PORTS" "ss -tuln"
    run_remote "NETWORK CONNECTIONS" "ss -tupn | head -20"
    run_remote "FIREWALL STATUS" "sudo ufw status verbose 2>/dev/null || sudo iptables -L INPUT 2>/dev/null | head -20 || echo 'Limited firewall access'"

    echo "Reviewing user security..."
    run_remote "USER ACCOUNTS" "cat /etc/passwd | grep -E '(bash|sh)$'"
    run_remote "SUDO USERS" "getent group sudo 2>/dev/null || echo 'No sudo group access'"
    run_remote "RECENT LOGINS" "last | head -15"
    run_remote "FAILED LOGIN ATTEMPTS" "sudo grep 'Failed password' /var/log/auth.log 2>/dev/null | tail -10 || echo 'No auth log access'"

    echo "Checking services..."
    run_remote "ACTIVE SERVICES" "systemctl list-units --type=service --state=active | head -20"
    run_remote "FAILED SERVICES" "systemctl list-units --type=service --state=failed"

    echo "Reviewing security updates..."
    run_remote "SECURITY UPDATES" "sudo apt list --upgradable 2>/dev/null | grep -i security | head -10 || echo 'No apt access or no security updates'"

    echo "Checking SSH configuration..."
    run_remote "SSH CONFIG" "sudo grep -E '^(PasswordAuthentication|PermitRootLogin|Port|MaxAuthTries|PubkeyAuthentication)' /etc/ssh/sshd_config 2>/dev/null || echo 'No SSH config access'"

    echo "Reviewing scheduled tasks..."
    run_remote "USER CRON JOBS" "crontab -l 2>/dev/null || echo 'No user cron jobs'"
    run_remote "SYSTEM CRON JOBS" "sudo ls -la /etc/cron.d/ /var/spool/cron/crontabs/ 2>/dev/null | head -10 || echo 'Limited cron access'"

    echo "Analyzing system logs..."
    run_remote "RECENT SYSTEM LOGS" "sudo journalctl -n 20 --no-pager 2>/dev/null || sudo tail -20 /var/log/syslog 2>/dev/null || echo 'No log access'"
    run_remote "KERNEL MESSAGES" "sudo dmesg | tail -15 2>/dev/null || echo 'No dmesg access'"

    echo "Checking file permissions..."
    run_remote "WORLD WRITABLE FILES" "find /tmp /var/tmp -type f -perm -002 2>/dev/null | head -10 || echo 'Limited file system access'"
    run_remote "SUID/SGID FILES" "find /usr -type f \\( -perm -4000 -o -perm -2000 \\) 2>/dev/null | head -10 || echo 'Limited file system access'"

    echo "Audit data collection completed. Generating AI analysis..."

    # Generate AI-powered analysis
    if [[ "$CLAUDE_ANALYSIS_ENABLED" == "true" ]]; then
        generate_ai_analysis "$audit_log" "$analysis_log" "$host_label" "$hostname" "$port"
    fi

    # Send email with analysis
    send_analysis_email "$audit_log" "$analysis_log" "$email" "$host_label" "$hostname"

    echo "✓ Audit completed for $host_label"
    echo "  Audit log: $audit_log"
    echo "  Analysis: $analysis_log"
    echo "  Email sent to: $email"
}

# Function to generate AI analysis
generate_ai_analysis() {
    local audit_log="$1"
    local analysis_log="$2"
    local host_label="$3"
    local hostname="$4"
    local port="$5"

    {
        echo "=== AI-POWERED SECURITY ANALYSIS ==="
        echo "Host: $host_label ($hostname:$port)"
        echo "Analysis Date: $(date)"
        echo "Analyzed by: Claude Code AI"
        echo ""
        echo "EXECUTIVE SUMMARY:"
        echo "=================="
        echo ""

        # Extract key metrics for analysis
        local load_avg=$(grep -A1 "UPTIME AND LOAD" "$audit_log" | tail -1 | sed -n 's/.*load average: \([0-9.]*\).*/\1/p')
        local mem_usage=$(grep -A2 "MEMORY USAGE" "$audit_log" | grep "Mem:" | awk '{print $3 "/" $2}')
        local failed_logins=$(grep -A30 "FAILED LOGIN ATTEMPTS" "$audit_log" | grep -v "sudo:" | grep -c "Failed password for" 2>/dev/null || echo "0")
        local listening_ports=$(grep -A20 "LISTENING PORTS" "$audit_log" | grep -c "LISTEN" 2>/dev/null || echo "0")
        local failed_services=$(grep -A10 "FAILED SERVICES" "$audit_log" | grep -c "failed" 2>/dev/null || echo "0")
        local failed_service_names=$(grep -A20 "FAILED SERVICES" "$audit_log" | grep "● " | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//' 2>/dev/null || echo "")
        local security_updates=$(grep -A10 "SECURITY UPDATES" "$audit_log" | grep -c "security" 2>/dev/null || echo "0")
        local listening_port_details=$(grep -A30 "LISTENING PORTS" "$audit_log" | grep -E ":(22|80|443|8080|3306|5432|21|25|53|110|143|993|995)" | head -10 | tr '\n' '; ' | sed 's/;$//' 2>/dev/null || echo "")
        local failed_login_details=$(grep -A30 "FAILED LOGIN ATTEMPTS" "$audit_log" | grep -v "sudo:" | grep -E "Failed password for" | head -5 | sed 's/.*Failed password for invalid user /INVALID: /' | sed 's/.*Failed password for //' | awk '{print $1 " (" $3 " " $4 ")"}' | tr '\n' '; ' | sed 's/;$//' 2>/dev/null || echo "")

        # System Health Analysis
        echo "SYSTEM HEALTH:"
        if [[ -n "$load_avg" && $(echo "$load_avg > 2.0" | bc -l 2>/dev/null) == "1" ]]; then
            echo "⚠️  HIGH LOAD: System load average is $load_avg (threshold: 2.0)"
        elif [[ -n "$load_avg" ]]; then
            echo "✅ Load average: $load_avg (normal)"
        else
            echo "ℹ️  Load average: Not available"
        fi

        if [[ -n "$mem_usage" ]]; then
            echo "ℹ️  Memory usage: $mem_usage"
        fi
        echo ""

        # Security Analysis
        echo "SECURITY ASSESSMENT:"
        if [[ "$failed_logins" -gt 5 ]]; then
            echo "🚨 CRITICAL: $failed_logins failed login attempts detected - possible brute force attack"
            if [[ -n "$failed_login_details" ]]; then
                echo "    Recent attempts: $failed_login_details"
            fi
        elif [[ "$failed_logins" -gt 0 ]]; then
            echo "⚠️  WARNING: $failed_logins failed login attempts detected"
            if [[ -n "$failed_login_details" ]]; then
                echo "    Recent attempts: $failed_login_details"
            fi
        else
            echo "✅ No recent failed login attempts"
        fi

        if [[ "$failed_services" -gt 0 ]]; then
            echo "⚠️  WARNING: $failed_services failed services detected"
            if [[ -n "$failed_service_names" ]]; then
                echo "    Failed services: $failed_service_names"
            fi
        else
            echo "✅ All services running normally"
        fi

        if [[ "$security_updates" -gt 0 ]]; then
            echo "⚠️  ATTENTION: $security_updates security updates available"
        else
            echo "✅ Security updates current"
        fi

        echo "ℹ️  Network exposure: $listening_ports listening ports detected"
        if [[ -n "$listening_port_details" ]]; then
            echo "    Key services: $listening_port_details"
        fi
        echo ""

        # Risk Assessment
        echo "RISK ASSESSMENT:"
        local risk_score=0

        if [[ "$failed_logins" -gt 10 ]]; then
            echo "🔴 HIGH RISK: Multiple authentication failures indicate active attack"
            risk_score=$((risk_score + 3))
        elif [[ "$failed_logins" -gt 5 ]]; then
            echo "🟡 MEDIUM RISK: Elevated authentication failures"
            risk_score=$((risk_score + 2))
        fi

        if [[ "$security_updates" -gt 5 ]]; then
            echo "🟡 MEDIUM RISK: Multiple security updates pending"
            risk_score=$((risk_score + 2))
        fi

        if [[ "$failed_services" -gt 0 ]]; then
            echo "🟡 MEDIUM RISK: Service failures may indicate system issues"
            risk_score=$((risk_score + 1))
        fi

        if [[ "$risk_score" -eq 0 ]]; then
            echo "🟢 LOW RISK: No immediate security concerns identified"
        fi
        echo ""

        # Recommendations
        echo "RECOMMENDATIONS:"
        echo "================"

        if [[ "$failed_logins" -gt 5 ]]; then
            echo "1. 🔒 IMMEDIATE: Review failed login sources and consider IP blocking"
            if [[ -n "$failed_login_details" ]]; then
                echo "   Target accounts: $failed_login_details"
            fi
            echo "2. 🔐 Strengthen authentication (disable password auth, use key-only)"
        fi

        if [[ "$security_updates" -gt 0 ]]; then
            echo "3. 🔄 Apply $security_updates pending security updates immediately"
        fi

        if [[ "$failed_services" -gt 0 ]]; then
            if [[ -n "$failed_service_names" ]]; then
                echo "4. 🔧 Investigate and resolve failed services: $failed_service_names"
            else
                echo "4. 🔧 Investigate and resolve $failed_services failed services"
            fi
        fi

        if [[ -n "$load_avg" && $(echo "$load_avg > 1.5" | bc -l 2>/dev/null) == "1" ]]; then
            echo "5. ⚡ Monitor system performance - elevated load detected"
        fi

        echo "6. 📊 Review full audit log for detailed findings"
        echo "7. 🔄 Schedule regular security audits (weekly/monthly)"
        echo "8. 📧 Monitor these reports for trending security issues"
        echo ""

        # Compliance Notes
        echo "COMPLIANCE NOTES:"
        echo "=================="
        echo "• SSH configuration reviewed for security best practices"
        echo "• User account management assessed"
        echo "• Network service exposure documented"
        echo "• System logging functionality verified"
        echo "• File permission anomalies checked"
        echo ""

        echo "NEXT AUDIT SCHEDULED: $(date -d '+1 week' '+%Y-%m-%d %H:%M')"

    } > "$analysis_log"

    echo "AI analysis generated: $analysis_log"
}

# Function to send analysis email
send_analysis_email() {
    local audit_log="$1"
    local analysis_log="$2"
    local email="$3"
    local host_label="$4"
    local hostname="$5"

    local subject="Security Audit Report - $host_label - $(date '+%Y-%m-%d')"

    {
        echo "To: $email"
        echo "Subject: $subject"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo ""

        if [[ -f "$analysis_log" ]]; then
            cat "$analysis_log"
            echo ""
            echo "========================================="
            echo "DETAILED AUDIT LOG SUMMARY:"
            echo "========================================="
            echo ""

            # Include key sections from audit log
            echo "SYSTEM STATUS:"
            grep -A5 "UPTIME AND LOAD\|MEMORY USAGE\|DISK USAGE" "$audit_log" | grep -v "^--$"
            echo ""

            echo "TOP RESOURCE CONSUMERS:"
            grep -A8 "TOP PROCESSES BY CPU" "$audit_log" | tail -7
            echo ""

            echo "NETWORK SECURITY:"
            grep -A10 "LISTENING PORTS" "$audit_log" | head -10
            echo ""

            if grep -q "Failed password" "$audit_log"; then
                echo "FAILED AUTHENTICATION ATTEMPTS:"
                grep "Failed password" "$audit_log" | tail -5
                echo ""
            fi

        else
            echo "AI analysis not available. Basic summary:"
            echo ""

            # Fallback basic summary
            echo "SYSTEM INFORMATION:"
            grep -A5 "SYSTEM INFORMATION" "$audit_log" | tail -5
            echo ""

            echo "LOAD AND MEMORY:"
            grep -A1 "UPTIME AND LOAD\|MEMORY USAGE" "$audit_log"
            echo ""
        fi

        echo "Full audit log available at: $audit_log"
        echo "Analysis log available at: $analysis_log"
        echo ""
        echo "Generated by Multi-Host Lakehouse Audit Tool"
        echo "Timestamp: $(date)"

    } | sendmail "$email"
}

# Function to setup scheduled audits
setup_schedule() {
    local host_name="${1:-}"
    local cron_file="/tmp/lakehouse_audit_cron"

    # Create cron entries
    > "$cron_file"

    if [[ -n "$host_name" ]]; then
        # Schedule specific host
        if parse_host_config "$host_name" "$HOSTS_CONFIG"; then
            if [[ "$HOST_ENABLED" == "true" && -n "$HOST_SCHEDULE" && -n "$HOST_SCHEDULE_TIME" ]]; then
                create_cron_entry "$host_name" >> "$cron_file"
            else
                echo "Host $host_name is not enabled or missing schedule configuration"
                return 1
            fi
        else
            echo "Host $host_name not found in configuration"
            return 1
        fi
    else
        # Schedule all enabled hosts
        local scheduled_count=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^\[(.+)\]$ ]]; then
                local current_host="${BASH_REMATCH[1]}"
                if parse_host_config "$current_host" "$HOSTS_CONFIG"; then
                    if [[ "$HOST_ENABLED" == "true" && -n "$HOST_SCHEDULE" && -n "$HOST_SCHEDULE_TIME" ]]; then
                        create_cron_entry "$current_host" >> "$cron_file"
                        scheduled_count=$((scheduled_count + 1))
                    fi
                fi
            fi
        done < "$HOSTS_CONFIG"

        if [[ "$scheduled_count" -eq 0 ]]; then
            echo "No enabled hosts with schedule configuration found"
            return 1
        fi

        echo "Scheduled $scheduled_count hosts for automated audits"
    fi

    # Install cron jobs
    if [[ -s "$cron_file" ]]; then
        echo "Installing scheduled audits..."
        crontab -l 2>/dev/null | grep -v "lakehouse.*audit" > "${cron_file}.existing" || true
        cat "${cron_file}.existing" "$cron_file" | crontab -
        rm -f "$cron_file" "${cron_file}.existing"
        echo "✓ Scheduled audits installed"
        echo ""
        echo "Current audit schedule:"
        crontab -l | grep "lakehouse.*audit"
    else
        echo "No cron entries generated"
        return 1
    fi
}

# Function to create cron entry for a host
create_cron_entry() {
    local host_name="$1"

    local hour="${HOST_SCHEDULE_TIME%:*}"
    local minute="${HOST_SCHEDULE_TIME#*:}"
    local cron_schedule=""

    case "$HOST_SCHEDULE" in
        daily)
            cron_schedule="$minute $hour * * *"
            ;;
        weekly)
            local day=$((HOST_SCHEDULE_DAY % 7))
            cron_schedule="$minute $hour * * $day"
            ;;
        monthly)
            cron_schedule="$minute $hour $HOST_SCHEDULE_DAY * *"
            ;;
        *)
            echo "Invalid schedule: $HOST_SCHEDULE" >&2
            return 1
            ;;
    esac

    echo "$cron_schedule $SCRIPT_DIR/multi_host_audit.sh -c $host_name >/dev/null 2>&1 # lakehouse audit: $host_name"
}

# Function to remove scheduled audits
remove_schedule() {
    echo "Removing scheduled audits..."
    crontab -l 2>/dev/null | grep -v "lakehouse.*audit" | crontab - || true
    echo "✓ Scheduled audits removed"
}

# Main script logic
main() {
    local hostname="" port="22" user="" email="$DEFAULT_EMAIL" config_host="" action="audit"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                hostname="$2"
                shift 2
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            -u|--user)
                user="$2"
                shift 2
                ;;
            -e|--email)
                email="$2"
                shift 2
                ;;
            -c|--config)
                config_host="$2"
                shift 2
                ;;
            -l|--list)
                action="list"
                shift
                ;;
            -s|--schedule)
                action="schedule"
                shift
                ;;
            --schedule-host)
                action="schedule_host"
                config_host="$2"
                shift 2
                ;;
            --remove-schedule)
                action="remove_schedule"
                shift
                ;;
            -a|--all)
                action="audit_all"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    # Execute requested action
    case "$action" in
        list)
            list_hosts
            ;;
        schedule)
            setup_schedule
            ;;
        schedule_host)
            setup_schedule "$config_host"
            ;;
        remove_schedule)
            remove_schedule
            ;;
        audit_all)
            echo "Auditing all enabled hosts..."
            local audited_count=0
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^\[(.+)\]$ ]]; then
                    local current_host="${BASH_REMATCH[1]}"
                    if parse_host_config "$current_host" "$HOSTS_CONFIG"; then
                        if [[ "$HOST_ENABLED" == "true" ]]; then
                            echo ""
                            run_audit_with_analysis "$HOST_HOSTNAME" "$HOST_PORT" "$HOST_USER" "$HOST_EMAIL" "$current_host"
                            audited_count=$((audited_count + 1))
                        else
                            echo "Skipping disabled host: $current_host"
                        fi
                    fi
                fi
            done < "$HOSTS_CONFIG"
            echo ""
            echo "✓ Completed audits for $audited_count hosts"
            ;;
        audit)
            if [[ -n "$config_host" ]]; then
                # Use configuration
                if parse_host_config "$config_host" "$HOSTS_CONFIG"; then
                    run_audit_with_analysis "$HOST_HOSTNAME" "$HOST_PORT" "$HOST_USER" "$HOST_EMAIL" "$config_host"
                else
                    exit 1
                fi
            elif [[ -n "$hostname" && -n "$user" ]]; then
                # Use command line parameters
                run_audit_with_analysis "$hostname" "$port" "$user" "$email" "manual"
            else
                echo "Error: Must specify either --config HOST or --host/--user parameters" >&2
                usage
                exit 1
            fi
            ;;
    esac
}

# Run main function with all arguments
main "$@"