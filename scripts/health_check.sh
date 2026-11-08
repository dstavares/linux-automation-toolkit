#!/usr/bin/env bash

# Display basic Linux server health information.
# This script is the first component of the automation toolkit.

set -euo pipefail

echo "================================"
echo "      SERVER HEALTH CHECK"
echo "================================"

echo ""
echo "[HOSTNAME]"
hostname

echo ""
echo "[UPTIME]"
uptime

echo ""
echo "[MEMORY USAGE]"
free -h

echo ""
echo "[DISK USAGE]"
df -h

echo ""
echo "[TOP CPU PROCESSES]"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

echo ""
echo "Health check completed."
