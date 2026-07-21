#!/bin/sh

printf '=== MEMORY_KB ===\n'
awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Shmem|Slab|SReclaimable|SUnreclaim|KernelStack|PageTables):/ { print }' /proc/meminfo

printf '=== TMP_FILES_KB ===\n'
du -sk /tmp 2>/dev/null | awk '{ print "tmpTotalKb=" $1 }'
find /tmp -xdev -type f -exec du -k {} \; 2>/dev/null | sort -nr | head -n 40

printf '=== PROCESSES_RSS_KB ===\n'
process_rss_total=0
for status_path in /proc/[0-9]*/status; do
  rss=$(awk '/^VmRSS:/ { print $2; exit }' "$status_path" 2>/dev/null)
  [ -n "$rss" ] || rss=0
  process_rss_total=$((process_rss_total + rss))
done
printf 'processRssTotalKb=%s\n' "$process_rss_total"
for status_path in /proc/[0-9]*/status; do
  pid=${status_path#/proc/}
  pid=${pid%/status}
  name=$(awk '/^Name:/ { print $2; exit }' "$status_path" 2>/dev/null)
  rss=$(awk '/^VmRSS:/ { print $2; exit }' "$status_path" 2>/dev/null)
  size=$(awk '/^VmSize:/ { print $2; exit }' "$status_path" 2>/dev/null)
  [ -n "$rss" ] || rss=0
  [ -n "$size" ] || size=0
  cmd=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
  [ -n "$cmd" ] || cmd="[$name]"
  printf '%s\t%s\t%s\t%s\n' "$rss" "$size" "$pid" "$cmd"
done | sort -nr | head -n 50
