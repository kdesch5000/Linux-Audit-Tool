# Linux Audit Tool

A comprehensive remote Linux security audit system that supports multiple hosts with intelligent scheduling and AI-powered analysis.

## ✨ Features

- **🖥️ Multi-Host Support**: Audit multiple servers from a single configuration
- **⏰ Intelligent Scheduling**: Automated daily, weekly, or monthly audit runs
- **🤖 AI-Powered Analysis**: Claude Code integration for intelligent threat assessment
- **📊 Risk Assessment**: Automated security scoring and prioritized recommendations
- **📧 Smart Email Reports**: Separate analysis for each host with actionable insights
- **🎛️ Command-Line Interface**: Flexible operation modes and configuration management

## Core Security Features

- **System Analysis**: Hardware info, uptime, memory, disk usage, performance metrics
- **Process Monitoring**: CPU and memory usage analysis with anomaly detection
- **Network Security**: Port scanning, connection analysis, firewall configuration review
- **User Security**: Account analysis, authentication attempts, privilege escalation monitoring
- **Service Management**: Active/failed services monitoring with dependency analysis
- **Security Updates**: Available security patches detection with prioritization
- **SSH Configuration**: SSH security settings review and hardening recommendations
- **Log Analysis**: System logs and kernel messages review with threat correlation
- **File Permissions**: World-writable files and SUID/SGID binary detection
- **Compliance Reporting**: Security framework alignment and audit trail management

## Quick Start

### Installation

1. Clone the repository:
```bash
git clone https://github.com/kdesch5000/Linux-Audit-Tool.git
cd Linux-Audit-Tool
```

2. Set up configuration:
```bash
cp config/hosts.conf.example config/hosts.conf
cp config/audit.conf.example config/audit.conf
```

3. Edit `config/hosts.conf` with your server details:
```bash
nano config/hosts.conf
```

4. Make scripts executable:
```bash
chmod +x multi_host_audit.sh schedule_manager.sh lakehouse_audit.sh
```

### Single Host Audit
```bash
# Audit specific host with parameters
./multi_host_audit.sh -h server.example.com -p 22 -u admin -e admin@example.com

# Audit using saved configuration
./multi_host_audit.sh -c server1
```

### Multi-Host Operations
```bash
# List configured hosts
./multi_host_audit.sh -l

# Audit all enabled hosts
./multi_host_audit.sh -a

# Set up automated scheduling
./multi_host_audit.sh -s
```

### Schedule Management
```bash
# Check current schedules
./schedule_manager.sh status

# Install all configured schedules
./schedule_manager.sh install-all

# Test audit for specific host
./schedule_manager.sh test server1
```

## Configuration

### Multi-Host Configuration (`config/hosts.conf`)

Define multiple hosts in the configuration file:

```ini
[server1]
hostname=server1.example.com
port=22
user=admin
email=admin@example.com
schedule=weekly
schedule_time=16:01
schedule_day=2
enabled=true

[database_server]
hostname=db.example.com
port=22
user=dbadmin
email=admin@example.com
schedule=weekly
schedule_time=16:03
schedule_day=2
enabled=true
```

### Scheduling Options

- **`schedule`**: `daily`, `weekly`, or `monthly`
- **`schedule_time`**: Time in HH:MM format (24-hour)
- **`schedule_day`**:
  - Weekly: 1-7 (1=Monday, 7=Sunday)
  - Monthly: 1-31 (day of month)
- **`enabled`**: `true` or `false`

### AI Analysis Configuration

The system includes Claude Code AI integration for intelligent security analysis:

- **Risk Assessment**: Automated security scoring
- **Threat Correlation**: Pattern recognition across audit data
- **Prioritized Recommendations**: Action items ranked by severity
- **Compliance Mapping**: Framework alignment suggestions

## Output

- **Detailed Log**: `logs/{host}_audit_YYYYMMDD_HHMMSS.log`
- **AI Analysis**: `logs/{host}_analysis_YYYYMMDD_HHMMSS.log`
- **Email Reports**: Automated AI-powered summaries

## Security Analysis

The tool performs comprehensive security checks:

### System Health
- Load averages and system performance
- Memory and disk space utilization
- Running processes and resource usage

### Network Security
- Open/listening ports inventory
- Active network connections
- Firewall configuration status

### Access Control
- User accounts with shell access
- Sudo/admin group membership
- Recent login history
- Failed authentication attempts

### Service Management
- Active system services
- Failed/broken services
- Unnecessary services detection

### Configuration Audit
- SSH security settings
- Scheduled tasks (cron jobs)
- File permission issues

## Prerequisites

- SSH access to target servers
- `sendmail` configured for email reports
- Appropriate permissions for security analysis commands
- Linux/Unix systems (tested on Ubuntu, Debian, CentOS, RHEL)

## Sample AI Analysis Output

```
=== AI-POWERED SECURITY ANALYSIS ===
Host: server1 (server1.example.com:22)

EXECUTIVE SUMMARY:
SYSTEM HEALTH:
✅ Load average: 0.67 (normal)
✅ Memory usage: 491Mi/3.7Gi (13% - excellent)
✅ Uptime: 27 days (very stable)

SECURITY ASSESSMENT:
⚠️  WARNING: 1 failed login attempts detected
✅ All services running normally
✅ Security updates current

RISK ASSESSMENT:
🟢 LOW RISK: No immediate security concerns

RECOMMENDATIONS:
1. Monitor failed login patterns
2. Apply available security updates
3. Review service configurations
4. Schedule regular audits
```

## File Structure

```
Linux-Audit-Tool/
├── multi_host_audit.sh        # Main multi-host audit engine
├── schedule_manager.sh         # Schedule management tool
├── lakehouse_audit.sh         # Legacy single-host script
├── README.md                   # This documentation
├── CHANGELOG.md               # Version history
├── config/
│   ├── hosts.conf.example     # Multi-host configuration template
│   └── audit.conf.example     # Audit scope configuration template
└── logs/                      # Audit log storage (created at runtime)
```

## Automation

To run automated audits, the tool integrates with cron:

```bash
# Set up all scheduled audits from configuration
./multi_host_audit.sh --schedule

# Manual cron entry example (Tuesday 4:01 PM)
01 16 * * 2 /path/to/Linux-Audit-Tool/multi_host_audit.sh -c server1
```

## API Endpoints

The system provides REST-like command-line interface:

### Core Operations
- `--help` - Show usage information
- `--list` - List configured hosts
- `--all` - Audit all enabled hosts
- `--config HOST` - Audit specific configured host
- `--host HOST --user USER` - Audit with direct parameters

### Schedule Management
- `--schedule` - Install all configured schedules
- `--schedule-host HOST` - Install schedule for specific host
- `--remove-schedule` - Remove all scheduled audits

## Troubleshooting

### SSH Connection Issues
- Verify SSH key authentication is set up
- Check firewall allows connection on specified port
- Confirm username and hostname are correct
- For IPv6 issues, the tool forces IPv4 connections

### Email Delivery Issues
- Verify `sendmail` is installed and configured
- Check email address is valid
- Review system mail logs for delivery errors

### Permission Errors
- Some commands require sudo access on remote server
- Script gracefully handles permission denials
- Review audit log for "access denied" messages

## Security Considerations

- **SSH Keys**: Use key-based authentication (password auth discouraged)
- **Network Security**: Consider running audits from secure management network
- **Log Storage**: Audit logs may contain sensitive system information
- **Email Security**: Use encrypted email transport where possible
- **Access Control**: Limit who can run audits and access results

## Contributing

Contributions are welcome! Please focus on:
- Enhanced security detection capabilities
- Support for additional Linux distributions
- Improved AI analysis algorithms
- Better reporting and visualization
- Performance optimizations

## License

MIT License - See LICENSE file for details

## Support

For issues, feature requests, or contributions:
- GitHub Issues: https://github.com/kdesch5000/Linux-Audit-Tool/issues
- Documentation: See README.md and example configuration files

---

🤖 Generated with [Claude Code](https://claude.ai/code)