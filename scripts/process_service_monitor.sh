
#!/usr/bin/env bash

# Monitor systemd services, running processes, and Linux uptime.
# Exit codes: 0=OK, 2=CRITICAL, 3=UNKNOWN.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/config/services.conf}"
TOP_PROCESSES="${TOP_PROCESSES:-5}"

overall_status="OK"
checked_services=0

# Print an error message and terminate with UNKNOWN status.
fail_unknown() {
    echo "UNKNOWN: $1" >&2
    exit 3
}

# Validate configuration and required system commands.
validate_environment() {
    local command_name

    for command_name in systemctl ps uptime awk head; do
        command -v "$command_name" >/dev/null 2>&1 ||
            fail_unknown "Required command not found: $command_name"
    done

    [[ -r "$CONFIG_FILE" ]] ||
        fail_unknown "Cannot read configuration: $CONFIG_FILE"

    [[ "$TOP_PROCESSES" =~ ^[1-9][0-9]*$ ]] ||
        fail_unknown "TOP_PROCESSES must be a positive integer"

    (( TOP_PROCESSES <= 50 )) ||
        fail_unknown "TOP_PROCESSES must not exceed 50"

    [[ -d /run/systemd/system ]] ||
        fail_unknown "systemd is not running"
}

# Validate service names to prevent malformed input.
validate_service_name() {
    local service="$1"

    [[ "$service" =~ ^[a-zA-Z0-9_.@-]+\.service$ ]]
}

# Check a systemd service and update overall health.
check_service() {
    local service="$1"
    local state

    if ! validate_service_name "$service"; then
        fail_unknown "Invalid service name: $service"
    fi

    if ! systemctl cat "$service" >/dev/null 2>&1; then
        fail_unknown "Service unit not found: $service"
    fi

    state=$(systemctl is-active "$service" 2>/dev/null) ||
        state="${state:-unknown}"

    case "$state" in
        active)
            printf "%-28s %s\n" "$service" "OK (active)"
            ;;
        inactive|failed|activating|deactivating)
            printf "%-28s %s\n" "$service" "CRITICAL ($state)"
            overall_status="CRITICAL"
            ;;
        *)
            fail_unknown "Unexpected state for $service: $state"
            ;;
    esac
}

# Read the service configuration file.
check_services() {
    local service

    echo "[SERVICE HEALTH]"

    while IFS= read -r service || [[ -n "$service" ]]; do
        service="${service%$'\r'}"

        [[ -z "$service" || "$service" =~ ^[[:space:]]*# ]] &&
            continue

        checked_services=$((checked_services + 1))
        check_service "$service"
    done < "$CONFIG_FILE"

    (( checked_services > 0 )) ||
        fail_unknown "No services configured"

    echo ""
}

# Display the processes with the highest CPU utilization.
show_top_cpu_processes() {
    echo "[TOP CPU PROCESSES]"

    ps -eo pid,comm,%cpu,%mem --sort=-%cpu |
        awk -v limit="$TOP_PROCESSES" 'NR <= limit + 1'

    echo ""
}

# Display the processes with the highest memory utilization.
show_top_memory_processes() {
    echo "[TOP MEMORY PROCESSES]"

    ps -eo pid,comm,%cpu,%mem --sort=-%mem |
        awk -v limit="$TOP_PROCESSES" 'NR <= limit + 1'

    echo ""
}

# Display the current system uptime.
show_uptime() {
    echo "[SYSTEM UPTIME]"
    uptime -p
    echo ""
}

# Execute all monitoring checks.
main() {
    validate_environment

    echo "======================================"
    echo "     PROCESS & SERVICE MONITOR"
    echo "======================================"
    echo "Host: $(hostname)"
    echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "--------------------------------------"

    check_services
    show_top_cpu_processes
    show_top_memory_processes
    show_uptime

    echo "--------------------------------------"
    echo "Services checked: $checked_services"
    echo "OVERALL STATUS: $overall_status"

    if [[ "$overall_status" == "CRITICAL" ]]; then
        exit 2
    fi

    exit 0
}

main "$@"
