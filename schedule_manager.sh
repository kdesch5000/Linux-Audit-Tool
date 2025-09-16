#!/bin/bash

# Schedule Manager for Multi-Host Lakehouse Audit Tool
# Provides easy management of scheduled audit jobs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MULTI_HOST_AUDIT="${SCRIPT_DIR}/multi_host_audit.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Schedule Manager for Multi-Host Lakehouse Audit Tool

COMMANDS:
    status          Show current scheduled audits
    add HOST        Add/update schedule for specific host
    remove HOST     Remove schedule for specific host
    remove-all      Remove all scheduled audits
    install-all     Install schedules for all enabled hosts
    test HOST       Test audit for specific host (no email)
    logs            Show recent audit logs

OPTIONS:
    -h, --help      Show this help message

EXAMPLES:
    # Show current schedules
    $0 status

    # Install all configured schedules
    $0 install-all

    # Add schedule for specific host
    $0 add lakehouse

    # Remove specific host schedule
    $0 remove lakehouse

    # Test audit without sending email
    $0 test lakehouse

    # View recent logs
    $0 logs

EOF
}

# Function to show current scheduled audits
show_status() {
    echo -e "${BLUE}=== SCHEDULED AUDIT STATUS ===${NC}"
    echo ""

    local cron_entries=$(crontab -l 2>/dev/null | grep "lakehouse.*audit" || true)

    if [[ -z "$cron_entries" ]]; then
        echo -e "${YELLOW}No scheduled audits found${NC}"
        return 0
    fi

    echo -e "${GREEN}Active Schedules:${NC}"
    echo "=================="

    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local schedule_part=$(echo "$line" | awk '{print $1, $2, $3, $4, $5}')
            local host_part=$(echo "$line" | sed 's/.*lakehouse audit: //')

            # Convert cron schedule to human readable
            local human_schedule=$(convert_cron_to_human "$schedule_part")

            printf "%-20s: %s\n" "$host_part" "$human_schedule"
        fi
    done <<< "$cron_entries"

    echo ""
    echo -e "${BLUE}Total scheduled audits:${NC} $(echo "$cron_entries" | wc -l)"
}

# Function to convert cron schedule to human readable format
convert_cron_to_human() {
    local cron="$1"
    local minute=$(echo "$cron" | awk '{print $1}')
    local hour=$(echo "$cron" | awk '{print $2}')
    local day=$(echo "$cron" | awk '{print $3}')
    local month=$(echo "$cron" | awk '{print $4}')
    local weekday=$(echo "$cron" | awk '{print $5}')

    local time_str=$(printf "%02d:%02d" "$hour" "$minute")

    if [[ "$day" != "*" && "$month" != "*" && "$weekday" == "*" ]]; then
        echo "Monthly on day $day at $time_str"
    elif [[ "$day" == "*" && "$month" == "*" && "$weekday" != "*" ]]; then
        local day_names=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
        local weekday_name=${day_names[$weekday]}
        echo "Weekly on $weekday_name at $time_str"
    elif [[ "$day" == "*" && "$month" == "*" && "$weekday" == "*" ]]; then
        echo "Daily at $time_str"
    else
        echo "Custom: $cron"
    fi
}

# Function to add/update schedule for host
add_schedule() {
    local host="$1"

    echo -e "${BLUE}Adding schedule for host: $host${NC}"

    if "$MULTI_HOST_AUDIT" --schedule-host "$host"; then
        echo -e "${GREEN}✓ Schedule added successfully for $host${NC}"
    else
        echo -e "${RED}✗ Failed to add schedule for $host${NC}"
        return 1
    fi
}

# Function to remove schedule for specific host
remove_schedule() {
    local host="$1"

    echo -e "${YELLOW}Removing schedule for host: $host${NC}"

    # Remove specific host from cron
    local temp_cron="/tmp/lakehouse_cron_temp"
    crontab -l 2>/dev/null | grep -v "lakehouse audit: $host" > "$temp_cron" || true

    if crontab "$temp_cron"; then
        echo -e "${GREEN}✓ Schedule removed for $host${NC}"
    else
        echo -e "${RED}✗ Failed to remove schedule for $host${NC}"
    fi

    rm -f "$temp_cron"
}

# Function to remove all schedules
remove_all_schedules() {
    echo -e "${YELLOW}Removing all scheduled audits...${NC}"

    if "$MULTI_HOST_AUDIT" --remove-schedule; then
        echo -e "${GREEN}✓ All schedules removed${NC}"
    else
        echo -e "${RED}✗ Failed to remove schedules${NC}"
        return 1
    fi
}

# Function to install all schedules
install_all_schedules() {
    echo -e "${BLUE}Installing schedules for all enabled hosts...${NC}"

    if "$MULTI_HOST_AUDIT" --schedule; then
        echo -e "${GREEN}✓ All schedules installed${NC}"
        echo ""
        show_status
    else
        echo -e "${RED}✗ Failed to install schedules${NC}"
        return 1
    fi
}

# Function to test audit for host
test_audit() {
    local host="$1"

    echo -e "${BLUE}Running test audit for host: $host${NC}"
    echo -e "${YELLOW}Note: This will perform actual audit but email will be sent${NC}"
    echo ""

    if "$MULTI_HOST_AUDIT" --config "$host"; then
        echo ""
        echo -e "${GREEN}✓ Test audit completed for $host${NC}"
    else
        echo -e "${RED}✗ Test audit failed for $host${NC}"
        return 1
    fi
}

# Function to show recent logs
show_logs() {
    local logs_dir="${SCRIPT_DIR}/logs"

    echo -e "${BLUE}=== RECENT AUDIT LOGS ===${NC}"
    echo ""

    if [[ ! -d "$logs_dir" ]]; then
        echo -e "${YELLOW}No logs directory found${NC}"
        return 0
    fi

    local log_files=$(find "$logs_dir" -name "*_audit_*.log" -mtime -7 | sort -r | head -10)

    if [[ -z "$log_files" ]]; then
        echo -e "${YELLOW}No recent audit logs found (last 7 days)${NC}"
        return 0
    fi

    echo -e "${GREEN}Recent Audit Logs (last 7 days):${NC}"
    echo "=================================="

    while IFS= read -r log_file; do
        if [[ -n "$log_file" ]]; then
            local file_name=$(basename "$log_file")
            local file_size=$(du -h "$log_file" | awk '{print $1}')
            local file_date=$(stat -c "%y" "$log_file" | cut -d' ' -f1)
            local host_name=$(echo "$file_name" | sed 's/_audit_.*/./')

            printf "%-20s %-12s %-8s %s\n" "$host_name" "$file_date" "$file_size" "$log_file"
        fi
    done <<< "$log_files"

    echo ""
    echo -e "${BLUE}Analysis logs:${NC}"
    local analysis_files=$(find "$logs_dir" -name "*_analysis_*.log" -mtime -7 | sort -r | head -5)

    if [[ -n "$analysis_files" ]]; then
        while IFS= read -r analysis_file; do
            if [[ -n "$analysis_file" ]]; then
                local file_name=$(basename "$analysis_file")
                local file_date=$(stat -c "%y" "$analysis_file" | cut -d' ' -f1)
                local host_name=$(echo "$file_name" | sed 's/_analysis_.*/./')

                printf "%-20s %-12s %s\n" "$host_name (AI)" "$file_date" "$analysis_file"
            fi
        done <<< "$analysis_files"
    else
        echo "No recent analysis logs found"
    fi
}

# Function to show host configuration status
show_host_config() {
    echo -e "${BLUE}=== HOST CONFIGURATION STATUS ===${NC}"
    echo ""
    "$MULTI_HOST_AUDIT" --list
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    case "$1" in
        status)
            show_status
            ;;
        add)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: Host name required${NC}" >&2
                usage
                exit 1
            fi
            add_schedule "$2"
            ;;
        remove)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: Host name required${NC}" >&2
                usage
                exit 1
            fi
            remove_schedule "$2"
            ;;
        remove-all)
            remove_all_schedules
            ;;
        install-all)
            install_all_schedules
            ;;
        test)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: Host name required${NC}" >&2
                usage
                exit 1
            fi
            test_audit "$2"
            ;;
        logs)
            show_logs
            ;;
        config)
            show_host_config
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
}

# Check if multi_host_audit.sh exists
if [[ ! -f "$MULTI_HOST_AUDIT" ]]; then
    echo -e "${RED}Error: multi_host_audit.sh not found at $MULTI_HOST_AUDIT${NC}" >&2
    exit 1
fi

# Run main function
main "$@"