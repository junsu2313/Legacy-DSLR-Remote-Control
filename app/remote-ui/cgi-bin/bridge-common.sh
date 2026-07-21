#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin

BRIDGE_HOST=${BRIDGE_HOST:-127.0.0.1}
BRIDGE_PORT=${BRIDGE_PORT:-8089}
BRIDGE_PIDFILE=${BRIDGE_PIDFILE:-/tmp/d810-bridge.pid}
BRIDGE_START_LOCK=${BRIDGE_START_LOCK:-/tmp/d810-bridge.start.lock}
BRIDGE_RESTART_LOCK=${BRIDGE_RESTART_LOCK:-/tmp/d810-bridge.restart.lock}
WS_HOST=${WS_HOST:-0.0.0.0}
WS_PORT=${WS_PORT:-8091}
WS_PIDFILE=${WS_PIDFILE:-/tmp/d810-ws.pid}
WS_LOG=${WS_LOG:-/tmp/d810-ws.log}
WS_START_LOCK=${WS_START_LOCK:-/tmp/d810-ws.start.lock}
LUA_BIN=${LUA_BIN:-$(command -v /usr/bin/lua 2>/dev/null || command -v lua 2>/dev/null || echo /usr/bin/lua)}
START_STOP_DAEMON_BIN=${START_STOP_DAEMON_BIN:-$(command -v /sbin/start-stop-daemon 2>/dev/null || command -v start-stop-daemon 2>/dev/null || echo /sbin/start-stop-daemon)}
BRIDGE_REQUEST_TIMEOUT=${BRIDGE_REQUEST_TIMEOUT:-5}
if [ -z "$SCRIPT_DIR" ]; then
  SCRIPT_DIR=$(dirname "$0")
fi
case "$SCRIPT_DIR" in
  /*) ;;
  *) SCRIPT_DIR=$(cd "$SCRIPT_DIR" 2>/dev/null && pwd) ;;
esac
if [ ! -f "$SCRIPT_DIR/d810bridge.lua" ] && [ -f /www/cgi-bin/d810bridge.lua ]; then
  SCRIPT_DIR=/www/cgi-bin
fi
BRIDGE_SCRIPT="$SCRIPT_DIR/d810bridge.lua"
WS_SCRIPT="$SCRIPT_DIR/d810ws.lua"
NC_BIN=${NC_BIN:-$(command -v /usr/bin/nc 2>/dev/null || command -v nc 2>/dev/null || echo /usr/bin/nc)}
GPHOTO_BIN=${GPHOTO_BIN:-$(command -v /usr/bin/gphoto2 2>/dev/null || command -v gphoto2 2>/dev/null || echo /usr/bin/gphoto2)}
GPHOTO_DETECT_MODEL=${GPHOTO_DETECT_MODEL:-Nikon DSC D810}
SESSION_HEALTH_SCRIPT=${D810D_SESSION_HEALTH_SCRIPT:-"$SCRIPT_DIR/session-health"}
SESSION_HEALTH_PIDFILE=${D810D_SESSION_HEALTH_PIDFILE:-/tmp/d810-session-health.pid}
SESSION_HEALTH_START_LOCK=${D810D_SESSION_HEALTH_START_LOCK:-/tmp/d810-session-health.start.lock}
STACK_GUARDIAN_SCRIPT=${D810D_STACK_GUARDIAN_SCRIPT:-"$SCRIPT_DIR/stack-guardian"}
STACK_GUARDIAN_PIDFILE=${D810D_STACK_GUARDIAN_PIDFILE:-/tmp/d810-stack-guardian.pid}
STACK_GUARDIAN_START_LOCK=${D810D_STACK_GUARDIAN_START_LOCK:-/tmp/d810-stack-guardian.start.lock}
RUNTIME_GUARDIAN_SCRIPT=${D810D_RUNTIME_GUARDIAN_SCRIPT:-"$SCRIPT_DIR/runtime-guardian"}
RUNTIME_GUARDIAN_PIDFILE=${D810D_RUNTIME_GUARDIAN_PIDFILE:-/tmp/d810-runtime-guardian.pid}
RUNTIME_GUARDIAN_START_LOCK=${D810D_RUNTIME_GUARDIAN_START_LOCK:-/tmp/d810-runtime-guardian.start.lock}
BATTERY_WORKER_SCRIPT=${D810D_BATTERY_WORKER_SCRIPT:-"$SCRIPT_DIR/battery-worker"}
BATTERY_WORKER_PIDFILE=${D810D_BATTERY_WORKER_PIDFILE:-/tmp/d810-battery-worker.pid}
BATTERY_WORKER_START_LOCK=${D810D_BATTERY_WORKER_START_LOCK:-/tmp/d810-battery-worker.start.lock}
BATTERY_WORKER_LOCKDIR=${D810D_BATTERY_WORKER_LOCKDIR:-/tmp/d810-battery-worker.lock}
SESSION_LOG_ROOT=${SESSION_LOG_ROOT:-/root/d810-sessions}
SESSION_SEQ_FILE=${SESSION_SEQ_FILE:-"$SESSION_LOG_ROOT/session.seq"}
if [ -z "$D810D_SESSION_ID" ] && [ -r "$SESSION_SEQ_FILE" ]; then
  D810D_SESSION_ID=$(cat "$SESSION_SEQ_FILE" 2>/dev/null || true)
  case "$D810D_SESSION_ID" in
    ''|*[!0-9]*) D810D_SESSION_ID="" ;;
  esac
  if [ -n "$D810D_SESSION_ID" ]; then
    D810D_SESSION_LABEL=$(printf '%03d_session' "$D810D_SESSION_ID")
    D810D_SESSION_DIR="$SESSION_LOG_ROOT/$D810D_SESSION_LABEL"
    mkdir -p "$D810D_SESSION_DIR" 2>/dev/null || true
    D810D_DEBUG_LOG="$D810D_SESSION_DIR/bridge.log"
    export D810D_SESSION_ID D810D_SESSION_LABEL D810D_SESSION_DIR D810D_DEBUG_LOG
  fi
fi
SESSION_REPAIR_REQUEST=${SESSION_REPAIR_REQUEST:-/tmp/d810-session.repair}
SESSION_LIVE_REQUEST=${SESSION_LIVE_REQUEST:-/tmp/d810-session.live}
DDSERVER_INIT=${DDSERVER_INIT:-/etc/init.d/ddserver}
D810D_PREFER_LEGACY_TRANSPORT=${D810D_PREFER_LEGACY_TRANSPORT:-1}
export D810D_PREFER_LEGACY_TRANSPORT

script_base_name() {
  path=$1
  printf '%s\n' "${path##*/}"
}

now_ms() {
  "$LUA_BIN" -e 'local ok, nixio = pcall(require, "nixio"); if ok and nixio and type(nixio.gettimeofday) == "function" then local s, u = nixio.gettimeofday(); io.write((tonumber(s) or 0) * 1000 + math.floor((tonumber(u) or 0) / 1000)); else io.write(os.time() * 1000); end'
}

bridge_trace_log() {
  msg=$1
  if [ -n "$BRIDGE_LOG" ]; then
    printf '[bridge][%s] %s\n' "$(now_ms)" "$msg" >> "$BRIDGE_LOG"
  fi
}

session_number_from_seq() {
  if [ -r "$SESSION_SEQ_FILE" ]; then
    seq=$(cat "$SESSION_SEQ_FILE" 2>/dev/null)
    case $seq in
      ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$seq"
    return 0
  fi
  return 1
}

session_label_from_number() {
  number=$1
  printf '%03d_session' "${number:-0}"
}

session_log_file_from_seq() {
  number=$(session_number_from_seq 2>/dev/null || true)
  if [ -n "$number" ]; then
    printf '%s/%s/bridge.log' "$SESSION_LOG_ROOT" "$(session_label_from_number "$number")"
    return 0
  fi
  return 1
}

if [ -z "$BRIDGE_LOG" ] || [ "$BRIDGE_LOG" = "/tmp/d810-bridge.log" ] || [ "$BRIDGE_LOG" = "/tmp/d810-bridge-v21.log" ]; then
  seq_log=$(session_log_file_from_seq 2>/dev/null || true)
  if [ -n "$seq_log" ]; then
    BRIDGE_LOG=$seq_log
  else
    BRIDGE_LOG=${BRIDGE_LOG:-/tmp/d810-bridge.log}
  fi
fi

BRIDGE_PATTERN=${BRIDGE_PATTERN:-$(script_base_name "$BRIDGE_SCRIPT") daemon}
WS_PATTERN=${WS_PATTERN:-$(script_base_name "$WS_SCRIPT") daemon}
SESSION_HEALTH_PATTERN=${SESSION_HEALTH_PATTERN:-$(script_base_name "$SESSION_HEALTH_SCRIPT")}
STACK_GUARDIAN_PATTERN=${STACK_GUARDIAN_PATTERN:-$(script_base_name "$STACK_GUARDIAN_SCRIPT")}
RUNTIME_GUARDIAN_PATTERN=${RUNTIME_GUARDIAN_PATTERN:-$(script_base_name "$RUNTIME_GUARDIAN_SCRIPT")}
BATTERY_WORKER_PATTERN=${BATTERY_WORKER_PATTERN:-$(script_base_name "$BATTERY_WORKER_SCRIPT")}

find_pid_by_pattern() {
  pattern=$1
  ps | grep -F "$pattern" | grep -v grep | awk 'NR==1 { print $1 }'
}

pid_alive() {
  pid=$1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

clear_stale_lockdir() {
  lockdir=$1
  [ -n "$lockdir" ] || return 0
  if [ -d "$lockdir" ]; then
    rmdir "$lockdir" 2>/dev/null || true
  fi
}

spawn_daemon() {
  pidfile=$1
  logfile=$2
  shift 2
  if [ -x "$START_STOP_DAEMON_BIN" ]; then
    executable=$1
    shift
    "$START_STOP_DAEMON_BIN" -S -b -m -p "$pidfile" -x "$executable" -- "$@" >>"$logfile" 2>&1
    return $?
  fi
  "$@" </dev/null >>"$logfile" 2>&1 &
  echo $! > "$pidfile"
  return 0
}

resolve_pid() {
  pidfile=$1
  pattern=$2
  pid=""
  if [ -r "$pidfile" ]; then
    pid=$(cat "$pidfile" 2>/dev/null)
    if pid_alive "$pid"; then
      printf '%s\n' "$pid"
      return 0
    fi
  fi
  pid=$(find_pid_by_pattern "$pattern")
  if pid_alive "$pid"; then
    printf '%s\n' "$pid"
    return 0
  fi
  return 1
}

kill_pids_by_pattern() {
  pattern=$1
  for pid in $(ps | grep -F "$pattern" | grep -v grep | awk '{ print $1 }'); do
    kill "$pid" 2>/dev/null || true
  done
}

kill_pidfile_process() {
  pidfile=$1
  [ -r "$pidfile" ] || return 0
  pid=$(cat "$pidfile" 2>/dev/null)
  if pid_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
  fi
}

wait_for_pattern_exit() {
  pattern=$1
  attempts=${2:-20}
  while [ "$attempts" -gt 0 ]; do
    found=$(find_pid_by_pattern "$pattern" 2>/dev/null || true)
    if ! pid_alive "$found"; then
      return 0
    fi
    attempts=$((attempts - 1))
    bridge_short_sleep
  done
  return 1
}

bridge_netcat() {
  "$NC_BIN" "$BRIDGE_HOST" "$BRIDGE_PORT"
}

bridge_ping_daemon() {
  out=$(printf '%s\n' PING | bridge_netcat 2>>"$BRIDGE_LOG")
  printf '%s' "$out" | grep -q '"ok":true'
}

bridge_short_sleep() {
  if command -v usleep >/dev/null 2>&1; then
    usleep 100000
  else
    sleep 1
  fi
}

camera_hardware_detected() {
  out=$(
    if command -v timeout >/dev/null 2>&1; then
      timeout -t "${GPHOTO_DETECT_TIMEOUT:-6}" "$GPHOTO_BIN" --auto-detect 2>/dev/null
    else
      "$GPHOTO_BIN" --auto-detect 2>/dev/null
    fi
  )
  printf '%s' "$out" | grep -Fq "$GPHOTO_DETECT_MODEL" || printf '%s' "$out" | grep -Fq 'usb:'
}

bridge_request() {
  payload=$1
  bridge_trace_log "request -> $payload"
  out=$(printf '%s\n' "$payload" | bridge_netcat 2>>"$BRIDGE_LOG")
  if [ -n "$out" ]; then
    bridge_trace_log "response <- ${out%%$'\n'*}"
  else
    bridge_trace_log "response <- <empty>"
  fi
  printf '%s' "$out"
}

bridge_only_start() {
  if bridge_alive; then
    return 0
  fi
  clear_stale_lockdir "$BRIDGE_START_LOCK"
  if mkdir "$BRIDGE_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$BRIDGE_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    spawn_daemon "$BRIDGE_PIDFILE" "$BRIDGE_LOG" "$LUA_BIN" "$BRIDGE_SCRIPT" daemon
    trap - HUP
    rmdir "$BRIDGE_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi
  i=0
  while [ "$i" -lt 30 ]; do
    if bridge_alive; then
      return 0
    fi
    i=$((i + 1))
    bridge_short_sleep
  done
  return 1
}

bridge_alive() {
  pid=$(resolve_pid "$BRIDGE_PIDFILE" "$BRIDGE_PATTERN" 2>/dev/null || true)
  if [ -z "$pid" ]; then
    return 1
  fi
  bridge_ping_daemon
}

ws_alive() {
  resolve_pid "$WS_PIDFILE" "$WS_PATTERN" >/dev/null 2>&1
}

ws_start() {
  if ws_alive; then
    return 0
  fi

  clear_stale_lockdir "$WS_START_LOCK"

  if mkdir "$WS_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$WS_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    WS_HOST="$WS_HOST" WS_PORT="$WS_PORT" spawn_daemon "$WS_PIDFILE" "$WS_LOG" "$LUA_BIN" "$WS_SCRIPT" daemon
    trap - HUP
    rmdir "$WS_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi

  ws_alive
}

session_health_alive() {
  resolve_pid "$SESSION_HEALTH_PIDFILE" "$SESSION_HEALTH_PATTERN" >/dev/null 2>&1
}

session_health_start() {
  if session_health_alive; then
    return 0
  fi

  clear_stale_lockdir "$SESSION_HEALTH_START_LOCK"

  if mkdir "$SESSION_HEALTH_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$SESSION_HEALTH_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    spawn_daemon "$SESSION_HEALTH_PIDFILE" "$BRIDGE_LOG" /bin/sh "$SESSION_HEALTH_SCRIPT"
    trap - HUP
    rmdir "$SESSION_HEALTH_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi

  session_health_alive
}

stack_guardian_alive() {
  resolve_pid "$STACK_GUARDIAN_PIDFILE" "$STACK_GUARDIAN_PATTERN" >/dev/null 2>&1
}

stack_guardian_start() {
  if stack_guardian_alive; then
    return 0
  fi

  clear_stale_lockdir "$STACK_GUARDIAN_START_LOCK"

  if mkdir "$STACK_GUARDIAN_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$STACK_GUARDIAN_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    spawn_daemon "$STACK_GUARDIAN_PIDFILE" "$BRIDGE_LOG" /bin/sh "$STACK_GUARDIAN_SCRIPT"
    trap - HUP
    rmdir "$STACK_GUARDIAN_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi

  stack_guardian_alive
}

runtime_guardian_alive() {
  resolve_pid "$RUNTIME_GUARDIAN_PIDFILE" "$RUNTIME_GUARDIAN_PATTERN" >/dev/null 2>&1
}

runtime_guardian_start() {
  if runtime_guardian_alive; then
    return 0
  fi
  clear_stale_lockdir "$RUNTIME_GUARDIAN_START_LOCK"
  if mkdir "$RUNTIME_GUARDIAN_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$RUNTIME_GUARDIAN_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    spawn_daemon "$RUNTIME_GUARDIAN_PIDFILE" "$BRIDGE_LOG" /bin/sh "$RUNTIME_GUARDIAN_SCRIPT"
    trap - HUP
    rmdir "$RUNTIME_GUARDIAN_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi
  runtime_guardian_alive
}

battery_worker_alive() {
  resolve_pid "$BATTERY_WORKER_PIDFILE" "$BATTERY_WORKER_PATTERN" >/dev/null 2>&1
}

battery_worker_count() {
  ps | grep -F "$BATTERY_WORKER_PATTERN" | grep -v grep | awk '{ print $1 }' | wc -l | tr -d ' '
}

battery_worker_start() {
  clear_stale_lockdir "$BATTERY_WORKER_START_LOCK"
  worker_count=$(battery_worker_count)
  case "$worker_count" in
    0) ;;
    1) return 0 ;;
    *)
      bridge_trace_log "duplicate battery workers detected count=$worker_count; normalizing"
      battery_worker_stop
      ;;
  esac
  if [ -d "$BATTERY_WORKER_LOCKDIR" ] && ! battery_worker_alive; then
    rm -f "$BATTERY_WORKER_LOCKDIR/pid" 2>/dev/null || true
    rmdir "$BATTERY_WORKER_LOCKDIR" 2>/dev/null || true
  fi
  if mkdir "$BATTERY_WORKER_START_LOCK" 2>/dev/null; then
    trap 'rmdir "$BATTERY_WORKER_START_LOCK" 2>/dev/null' EXIT INT TERM
    trap '' HUP
    spawn_daemon "$BATTERY_WORKER_PIDFILE" "$BRIDGE_LOG" /bin/sh "$BATTERY_WORKER_SCRIPT"
    trap - HUP
    rmdir "$BATTERY_WORKER_START_LOCK" 2>/dev/null
    trap - EXIT INT TERM
  fi

  battery_worker_alive
}

bridge_stop() {
  battery_worker_stop
  kill_pids_by_pattern "$BRIDGE_PATTERN"
  wait_for_pattern_exit "$BRIDGE_PATTERN" 12 || true
  for pid in $(ps | grep -F "$BRIDGE_PATTERN" | grep -v grep | awk '{ print $1 }'); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  rm -f "$BRIDGE_PIDFILE"
  killall -q -f "$BRIDGE_SCRIPT" 2>/dev/null || true
}

ws_stop() {
  kill_pids_by_pattern "$WS_PATTERN"
  rm -f "$WS_PIDFILE"
  killall -q -f "$WS_SCRIPT" 2>/dev/null || true
}

session_health_stop() {
  kill_pids_by_pattern "$SESSION_HEALTH_PATTERN"
  rm -f "$SESSION_HEALTH_PIDFILE"
  killall -q -f "$SESSION_HEALTH_SCRIPT" 2>/dev/null || true
}

stack_guardian_stop() {
  kill_pids_by_pattern "$STACK_GUARDIAN_PATTERN"
  rm -f "$STACK_GUARDIAN_PIDFILE"
  killall -q -f "$STACK_GUARDIAN_SCRIPT" 2>/dev/null || true
}

runtime_guardian_stop() {
  kill_pidfile_process "$RUNTIME_GUARDIAN_PIDFILE"
  kill_pids_by_pattern "$RUNTIME_GUARDIAN_PATTERN"
  wait_for_pattern_exit "$RUNTIME_GUARDIAN_PATTERN" 12 || true
  rm -f "$RUNTIME_GUARDIAN_PIDFILE"
  rmdir "$RUNTIME_GUARDIAN_START_LOCK" 2>/dev/null || true
  killall -q -f "$RUNTIME_GUARDIAN_SCRIPT" 2>/dev/null || true
}

battery_worker_stop() {
  kill_pidfile_process "$BATTERY_WORKER_PIDFILE"
  kill_pids_by_pattern "$BATTERY_WORKER_PATTERN"
  wait_for_pattern_exit "$BATTERY_WORKER_PATTERN" 12 || true
  for pid in $(ps | grep -F "$BATTERY_WORKER_PATTERN" | grep -v grep | awk '{ print $1 }'); do
    kill -KILL "$pid" 2>/dev/null || true
  done
  rm -f "$BATTERY_WORKER_PIDFILE"
  rm -f "$BATTERY_WORKER_LOCKDIR/pid" 2>/dev/null || true
  rmdir "$BATTERY_WORKER_LOCKDIR" 2>/dev/null || true
  rmdir "$BATTERY_WORKER_START_LOCK" 2>/dev/null || true
  killall -q -f "$BATTERY_WORKER_SCRIPT" 2>/dev/null || true
}

purge_runtime_tmp() {
  rm -f \
    /tmp/d810-session.state \
    /tmp/d810-session.mode \
    /tmp/d810-session-v21.state \
    /tmp/d810-session-v21.mode \
    /tmp/d810-live-v21.session \
    /tmp/d810-session.boot \
    /tmp/d810-session-v21.boot \
    /tmp/d810-live.jpg \
    /tmp/d810-live-last-good.jpg \
    /tmp/d810-live.meta \
    /tmp/d810-live-refresh.pid \
    /tmp/d810-live.lock/owner \
    /tmp/d810-live-v21.jpg \
    /tmp/d810-live-v21-last-good.jpg \
    /tmp/d810-live-v21.meta \
    /tmp/d810-live-v21-refresh.pid \
    /tmp/d810-live-v21-refresh.lock/owner \
    /tmp/d810-captured-preview.jpg \
    /tmp/d810-captured-preview.meta \
    /tmp/d810-captured-object.jpg \
    /tmp/d810-captured-object.meta \
    /tmp/d810-battery.cache \
    /tmp/d810-battery.cache.ts \
    /tmp/d810-bridge-debug.log \
    /tmp/gphoto-detect.out
  rmdir /tmp/d810-live.lock 2>/dev/null || true
  rmdir /tmp/d810-live-v21-refresh.lock 2>/dev/null || true
  rmdir /tmp/d810-command.lock 2>/dev/null || true
  rmdir /tmp/d810-bridge.start.lock 2>/dev/null || true
  rmdir /tmp/d810-bridge.restart.lock 2>/dev/null || true
  rmdir /tmp/d810-bridge-v21.start.lock 2>/dev/null || true
  rmdir /tmp/d810-bridge-v21.restart.lock 2>/dev/null || true
  rmdir /tmp/d810-ws.start.lock 2>/dev/null || true
  rmdir /tmp/d810-ws-v21.start.lock 2>/dev/null || true
  rmdir /tmp/d810-session-health.start.lock 2>/dev/null || true
  rmdir /tmp/d810-stack-guardian.start.lock 2>/dev/null || true
  rmdir /tmp/d810-battery-worker.start.lock 2>/dev/null || true
  rmdir /tmp/d810-battery-worker.lock 2>/dev/null || true
  rmdir /tmp/d810-runtime-guardian.start.lock 2>/dev/null || true
}

bridge_restart_stack() {
  if mkdir "$BRIDGE_RESTART_LOCK" 2>/dev/null; then
    (
      trap '' EXIT INT TERM HUP
      ws_stop
      battery_worker_stop
      session_health_stop
      stack_guardian_stop
      runtime_guardian_stop
      bridge_stop
      purge_runtime_tmp
      sleep 1
      if [ -x "$DDSERVER_INIT" ]; then
        "$DDSERVER_INIT" restart >/dev/null 2>&1 || true
      fi
      bridge_start
      rmdir "$BRIDGE_RESTART_LOCK" 2>/dev/null
    ) >/dev/null 2>&1 &
  fi
}

bridge_start() {
  if ! bridge_only_start; then
    return 1
  fi
  ws_start >/dev/null 2>&1 || true
  runtime_guardian_start >/dev/null 2>&1 || true
  return 0
}

if [ "$(basename "$0")" = "bridge-common.sh" ] && [ $# -gt 0 ]; then
  "$@"
fi
