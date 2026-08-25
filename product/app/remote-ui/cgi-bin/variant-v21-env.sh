#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin

SCRIPT_DIR=$(dirname "$0")
case "$SCRIPT_DIR" in
  /*) ;;
  *) SCRIPT_DIR=/www/cgi-bin ;;
esac

export BRIDGE_HOST=127.0.0.1
export BRIDGE_PORT=8189
export D810D_STREAM_HOST=127.0.0.1
export D810D_STREAM_PORT=8190
export D810D_WS_POLL_MS=1
export D810D_TRACE_FRAMES=${D810D_TRACE_FRAMES:-0}
export D810D_BRIDGE_HOST=127.0.0.1
export D810D_BRIDGE_PORT=8189
export D810D_DDSERVER_INIT="$SCRIPT_DIR/project-ddserver-runtime"
export D810D_DDSERVER_PIDFILE=/tmp/d810-project-ddserver.pid
export D810D_DDSERVER_LOG=/tmp/ddserver-runtime.log
export BRIDGE_PIDFILE=/tmp/d810-bridge-v21.pid
export BRIDGE_LOG=/tmp/d810-bridge-v21.log
export BRIDGE_START_LOCK=/tmp/d810-bridge-v21.start.lock
export BRIDGE_RESTART_LOCK=/tmp/d810-bridge-v21.restart.lock
export WS_HOST=0.0.0.0
export WS_PORT=8191
export D810D_WS_HOST=0.0.0.0
export D810D_WS_PORT=8191
export D810D_DISABLE_DIRECT_STREAM=0
export WS_PIDFILE=/tmp/d810-ws-v21.pid
export WS_LOG=/tmp/d810-ws-v21.log
export WS_START_LOCK=/tmp/d810-ws-v21.start.lock
export BRIDGE_SCRIPT="$SCRIPT_DIR/d810bridge.lua"
export WS_SCRIPT="$SCRIPT_DIR/d810ws.lua"
export START_STOP_DAEMON_BIN=/nonexistent/d810-v21-no-ssd
export D810D_PREFER_LEGACY_TRANSPORT=0
export D810D_CAPTURED_OBJECT_TIMEOUT=120
export D810D_CAPTURED_OBJECT_CHUNK_SIZE=524288
export D810D_CAPTURED_NEF_SCAN_LIMIT=512
export D810D_CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT=524288
export D810D_CAPTURED_OBJECT_LIVE_PAUSE_MS=150
export D810D_SESSION_STATE=/tmp/d810-session-v21.state
export D810D_SESSION_MODE=/tmp/d810-session-v21.mode
export D810D_LIVE_SESSION_PATH=/tmp/d810-live-v21.session
export D810D_LIVE_SESSION_ID=1
export D810D_LIVE_SESSION_LABEL=live_session
export D810D_FRAME_PATH=/tmp/d810-live-v21.jpg
export D810D_FRAME_LAST_GOOD=/tmp/d810-live-v21-last-good.jpg
export D810D_FRAME_META=/tmp/d810-live-v21.meta
export D810D_FRAME_REFRESH_PIDFILE=/tmp/d810-live-v21-refresh.pid
export D810D_FRAME_REFRESH_SCRIPT="$SCRIPT_DIR/frame-refresh-v21"
export D810D_FRAME_REFRESH_LOCKDIR=/tmp/d810-live-v21-refresh.lock
export D810D_RUNTIME_GUARDIAN_SCRIPT="$SCRIPT_DIR/runtime-guardian"
export D810D_RUNTIME_GUARDIAN_PIDFILE=/tmp/d810-runtime-guardian.pid
export D810D_RUNTIME_GUARDIAN_START_LOCK=/tmp/d810-runtime-guardian.start.lock
