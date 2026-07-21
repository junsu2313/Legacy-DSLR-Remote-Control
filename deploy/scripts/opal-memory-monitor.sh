#!/bin/sh

INTERVAL=${1:-0.25}
SAMPLES=${2:-240}
OUTPUT=${3:-/tmp/d810-memory-monitor.csv}
BRIDGE_PIDFILE=${BRIDGE_PIDFILE:-/tmp/d810-bridge-v21.pid}
OBJECT_PATH=${D810D_CAPTURED_OBJECT_PATH:-/tmp/d810-captured-object.jpg}
OBJECT_TMP_PATH=${OBJECT_PATH}.tmp

printf 'uptime_s,mem_free_kb,mem_available_kb,buffers_kb,cached_kb,shmem_kb,slab_kb,bridge_rss_kb,object_bytes,tmp_object_bytes\n' > "$OUTPUT"

sample=0
while [ "$sample" -lt "$SAMPLES" ]; do
  uptime_s=0
  read -r uptime_s _ < /proc/uptime
  mem_free_kb=0
  mem_available_kb=0
  buffers_kb=0
  cached_kb=0
  shmem_kb=0
  slab_kb=0
  while read -r key value unit; do
    case "$key" in
      MemFree:) mem_free_kb=$value ;;
      MemAvailable:) mem_available_kb=$value ;;
      Buffers:) buffers_kb=$value ;;
      Cached:) cached_kb=$value ;;
      Shmem:) shmem_kb=$value ;;
      Slab:) slab_kb=$value ;;
    esac
  done < /proc/meminfo

  bridge_rss_kb=0
  if [ -r "$BRIDGE_PIDFILE" ]; then
    bridge_pid=$(cat "$BRIDGE_PIDFILE" 2>/dev/null)
    if [ -r "/proc/$bridge_pid/status" ]; then
      while read -r key value unit; do
        if [ "$key" = "VmRSS:" ]; then
          bridge_rss_kb=$value
          break
        fi
      done < "/proc/$bridge_pid/status"
    fi
  fi

  object_bytes=0
  tmp_object_bytes=0
  [ -e "$OBJECT_PATH" ] && object_bytes=$(stat -c %s "$OBJECT_PATH" 2>/dev/null || printf 0)
  [ -e "$OBJECT_TMP_PATH" ] && tmp_object_bytes=$(stat -c %s "$OBJECT_TMP_PATH" 2>/dev/null || printf 0)

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$uptime_s" "$mem_free_kb" "$mem_available_kb" "$buffers_kb" "$cached_kb" \
    "$shmem_kb" "$slab_kb" "$bridge_rss_kb" "$object_bytes" "$tmp_object_bytes" >> "$OUTPUT"
  sample=$((sample + 1))
  sleep "$INTERVAL"
done
