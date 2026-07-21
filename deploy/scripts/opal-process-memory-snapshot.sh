#!/bin/sh

SNAPSHOT="/tmp/opal-process-memory.$$.tsv"
trap 'rm -f "$SNAPSHOT"' EXIT INT TERM

printf 'rss_kb\tvm_size_kb\tpid\tname\n' > "$SNAPSHOT"
for status_path in /proc/[0-9]*/status; do
  pid=${status_path#/proc/}
  pid=${pid%/status}
  name=""
  rss_kb=0
  vm_size_kb=0
  while read -r key value unit; do
    case "$key" in
      Name:) name=$value ;;
      VmRSS:) rss_kb=$value ;;
      VmSize:) vm_size_kb=$value ;;
    esac
  done < "$status_path" 2>/dev/null || continue
  [ -n "$name" ] || name="unknown"
  printf '%s\t%s\t%s\t%s\n' "$rss_kb" "$vm_size_kb" "$pid" "$name" >> "$SNAPSHOT"
done

printf 'process_rss_total_kb\t'
awk 'NR > 1 { total += $1 } END { print total + 0 }' "$SNAPSHOT"
printf 'mem_total_kb\t'
awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo
printf 'mem_available_kb\t'
awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo
printf 'rss_kb\tvm_size_kb\tpid\tname\n'
tail -n +2 "$SNAPSHOT" | sort -nr -k1,1
