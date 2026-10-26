#!/bin/bash
# Measures how much CPU and memory a running ISLe8 uses, including its MediaRemote bridge.
# CPU is the CPU time used during the window divided by its length, so short spikes count.
# Usage: scripts/measure.sh [seconds]
set -euo pipefail

seconds=${1:-30}
app_pid=$(pgrep -x ISLe8 | head -1 || true)
if [ -z "$app_pid" ]; then
    echo "ISLe8 is not running." >&2
    exit 1
fi
bridge_pid=$(pgrep -P "$app_pid" -x perl | head -1 || true)

# Prints a process's total CPU time in seconds ("[[dd-]hh:]mm:ss.cc" from ps).
cpu_seconds() {
    ps -o time= -p "$1" 2>/dev/null | awk '{
        n = split($1, parts, ":"); total = 0
        for (i = 1; i <= n; i++) total = total * 60 + parts[i]
        print total
    }'
}

rss_mb() {
    ps -o rss= -p "$1" 2>/dev/null | awk '{ printf "%.1f", $1 / 1024 }'
}

report() {
    local name=$1 pid=$2 start=$3
    local end
    end=$(cpu_seconds "$pid")
    awk -v name="$name" -v start="$start" -v end="$end" -v seconds="$seconds" -v rss="$(rss_mb "$pid")" \
        'BEGIN { printf "%-8s CPU %.2f%%   memory %s MB\n", name, (end - start) / seconds * 100, rss }'
}

app_start=$(cpu_seconds "$app_pid")
bridge_start=""
[ -n "$bridge_pid" ] && bridge_start=$(cpu_seconds "$bridge_pid")

echo "Measuring for $seconds s…"
sleep "$seconds"

report "ISLe8" "$app_pid" "$app_start"
if [ -n "$bridge_pid" ]; then
    report "bridge" "$bridge_pid" "$bridge_start"
fi
