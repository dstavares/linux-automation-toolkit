
#!/usr/bin/env bash

# Monitor Linux CPU, memory, and root filesystem usage.
# Classify resource utilization using configurable thresholds.
# Exit codes: 0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN.

set -euo pipefail

WARNING_THRESHOLD="${WARNING_THRESHOLD:-75}"
CRITICAL_THRESHOLD="${CRITICAL_THRESHOLD:-90}"
FILESYSTEM="${FILESYSTEM:-/}"

# Validate monitoring thresholds before collecting metrics.
validate_config() {
    if ! [[ "$WARNING_THRESHOLD" =~ ^[0-9]+$ &&
            "$CRITICAL_THRESHOLD" =~ ^[0-9]+$ ]] ||
       (( WARNING_THRESHOLD < 1 ||
          CRITICAL_THRESHOLD > 100 ||
          WARNING_THRESHOLD >= CRITICAL_THRESHOLD )); then
        echo "ERROR: Invalid threshold configuration." >&2
        exit 3
    fi
}

# Read aggregate CPU counters from the Linux proc filesystem.
read_cpu_counters() {
    local cpu user nice system idle iowait irq softirq steal rest

    read -r cpu user nice system idle iowait irq softirq steal rest \
        < /proc/stat

    if [[ "$cpu" != "cpu" ]]; then
        return 1
    fi

    CPU_IDLE=$((idle + iowait))
    CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

# Calculate CPU utilization from two samples.
get_cpu_usage() {
    local idle1 total1 delta_idle delta_total

    read_cpu_counters || return 1
    idle1=$CPU_IDLE
    total1=$CPU_TOTAL

    sleep 1

    read_cpu_counters || return 1

    delta_idle=$((CPU_IDLE - idle1))
    delta_total=$((CPU_TOTAL - total1))

    if (( delta_total <= 0 )); then
        return 1
    fi

    echo $((100 * (delta_total - delta_idle) / delta_total))
}

# Calculate memory utilization using available RAM.
get_memory_usage() {
    free -b | awk '
        /^Mem:/ {
            if ($2 <= 0) exit 1
            printf "%.0f\n", 100 * ($2 - $7) / $2
            found = 1
        }
        END {
            if (!found) exit 1
        }
    '
}

# Retrieve filesystem utilization as a percentage.
get_disk_usage() {
    df -P "$FILESYSTEM" | awk '
        NR == 2 {
            gsub(/%/, "", $5)
            if ($5 !~ /^[0-9]+$/) exit 1
            print $5
            found = 1
        }
        END {
            if (!found) exit 1
        }
    '
}

# Convert a utilization percentage into a health status.
evaluate_status() {
    local usage="$1"

    if (( usage >= CRITICAL_THRESHOLD )); then
        echo "CRITICAL"
    elif (( usage >= WARNING_THRESHOLD )); then
        echo "WARNING"
    else
        echo "OK"
    fi
}

# Print a formatted metric result.
print_metric() {
    printf "%-10s %3s%%  %s\n" "$1" "$2" "$3"
}

# Collect metrics and report the overall health status.
main() {
    validate_config

    local cpu memory disk
    local cpu_status memory_status disk_status

    cpu=$(get_cpu_usage) || {
        echo "ERROR: Unable to collect CPU usage." >&2
        exit 3
    }

    memory=$(get_memory_usage) || {
        echo "ERROR: Unable to collect memory usage." >&2
        exit 3
    }

    disk=$(get_disk_usage) || {
        echo "ERROR: Unable to collect disk usage." >&2
        exit 3
    }

    for value in "$cpu" "$memory" "$disk"; do
        if ! [[ "$value" =~ ^[0-9]+$ ]] ||
           (( value > 100 )); then
            echo "ERROR: Invalid metric value." >&2
            exit 3
        fi
    done

    cpu_status=$(evaluate_status "$cpu")
    memory_status=$(evaluate_status "$memory")
    disk_status=$(evaluate_status "$disk")

    echo "================================"
    echo "      RESOURCE MONITOR"
    echo "================================"
    echo "Host: $(hostname)"
    echo "Filesystem: $FILESYSTEM"
    echo "Warning: ${WARNING_THRESHOLD}%"
    echo "Critical: ${CRITICAL_THRESHOLD}%"
    echo "--------------------------------"

    print_metric "CPU" "$cpu" "$cpu_status"
    print_metric "MEMORY" "$memory" "$memory_status"
    print_metric "DISK" "$disk" "$disk_status"

    echo "--------------------------------"

    if [[ "$cpu_status" == "CRITICAL" ||
          "$memory_status" == "CRITICAL" ||
          "$disk_status" == "CRITICAL" ]]; then
        echo "OVERALL STATUS: CRITICAL"
        exit 2
    elif [[ "$cpu_status" == "WARNING" ||
            "$memory_status" == "WARNING" ||
            "$disk_status" == "WARNING" ]]; then
        echo "OVERALL STATUS: WARNING"
        exit 1
    else
        echo "OVERALL STATUS: OK"
        exit 0
    fi
}

main "$@"
