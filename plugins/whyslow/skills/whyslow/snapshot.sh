#!/usr/bin/env bash
# Read-only snapshot of why a machine feels slow. macOS first, Linux fallback.
# Takes ~10s (two CPU samples and a short disk I/O sample). Never changes anything.
# Usage: snapshot.sh [seconds-to-sample, default 5]
set -u
S=${1:-5}
sec() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
os=$(uname -s)

sec "machine"
if [ "$os" = Darwin ]; then
  sw_vers 2>/dev/null | tr '\n' ' '; echo
  echo "cpu: $(sysctl -n machdep.cpu.brand_string)  cores: $(sysctl -n hw.ncpu)  ram_gb: $(( $(sysctl -n hw.memsize) / 1073741824 ))"
else
  grep PRETTY_NAME /etc/os-release 2>/dev/null
  echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)  cores: $(nproc)  ram_gb: $(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1048576 ))"
fi
echo "uptime:$(uptime)"

sec "top cpu (sampled over ${S}s)"
if [ "$os" = Darwin ]; then
  # first sample of top -l is meaningless for %CPU; keep the second
  top -l 2 -s "$S" -o cpu -n 15 -stats pid,command,cpu,mem,state,time 2>/dev/null \
    | awk '/^Processes:/{n++} n==2' | sed -n '1,30p'
else
  top -b -n 2 -d "$S" -o %CPU 2>/dev/null | awk '/^top -/{n++} n==2' | sed -n '1,25p'
fi

sec "top memory"
if [ "$os" = Darwin ]; then ps -Amo pid,rss,pcpu,etime,comm | head -16
else ps -eo pid,rss,pcpu,etime,comm --sort=-rss | head -16; fi

sec "process groups by total memory (rss MB, count, name)"
ps -Ao rss=,comm= | awk '{r=$1; $1=""; n=$0; sub(/^ +/,"",n); sub(/.*\//,"",n); m[n]+=r; c[n]++}
  END{for(k in m) printf "%7d MB %4d  %s\n", m[k]/1024, c[k], k}' | sort -rn | head -12

sec "memory pressure / swap"
if [ "$os" = Darwin ]; then
  memory_pressure 2>/dev/null | grep -i 'free percentage'
  sysctl vm.swapusage
  vm_stat | grep -E 'Pages (free|active|inactive|wired|occupied by compressor)|Swapins|Swapouts|Compressions|Decompressions'
else
  free -h; grep -E 'pswpin|pswpout' /proc/vmstat
fi

sec "disk space"
df -h / /System/Volumes/Data 2>/dev/null | awk '!seen[$0]++'

sec "disk i/o (${S}s)"
if [ "$os" = Darwin ]; then iostat -d -w "$S" -c 2 2>/dev/null | sed -n '1,2p;$p'
elif have iostat; then iostat -dx "$S" 2 | tail -n +1 | awk 'NR>1' | tail -15
else cat /proc/loadavg; fi

sec "thermal / power"
if [ "$os" = Darwin ]; then
  pmset -g therm 2>/dev/null
  pmset -g batt 2>/dev/null
  pmset -g 2>/dev/null | grep -Ei 'lowpowermode|powermode'
else
  for z in /sys/class/thermal/thermal_zone*/temp; do [ -r "$z" ] && echo "$z $(( $(cat "$z") / 1000 ))C"; done 2>/dev/null
  cat /sys/class/power_supply/*/status 2>/dev/null
fi

if [ "$os" = Darwin ]; then
  sec "known background hogs"
  ps -Ao pcpu,rss,etime,comm | grep -Ei 'mds|mdworker|backupd|photoanalysisd|bird|cloudd|softwareupdate|kernel_task|WindowServer|com.apple.Virtualization|Docker|qemu|syspolicyd|XprotectService|fileproviderd|Spotlight|antivirus|falcon|crowdstrike|sentinel|jamf|zscaler' | grep -v grep | sort -rn | head -15
  tmutil currentphase 2>/dev/null | sed 's/^/time machine: /'
  sec "process counts"
  echo "processes: $(ps -A | wc -l | tr -d ' ')"
  ps -Ao comm | awk -F/ '{print $NF}' | sort | uniq -c | sort -rn | head -8
  sec "login items / launch agents"
  ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null | grep -v '^$' | grep -vc ':$' | sed 's/^/third-party launch plists: /'
  sec "recent hangs / crashes (last 2 days)"
  find /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports -mtime -2 -type f 2>/dev/null \
    | sed 's#.*/##' | sed -E 's/[-_][0-9]{4}-.*//' | sort | uniq -c | sort -rn | head -10
else
  sec "process counts"
  echo "processes: $(ps -e | wc -l)"
  sec "failed units"
  have systemctl && systemctl --failed --no-legend 2>/dev/null | head
fi
echo
echo "== done"
