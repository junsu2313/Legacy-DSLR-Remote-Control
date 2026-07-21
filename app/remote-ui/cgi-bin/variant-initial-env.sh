#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin

SCRIPT_DIR=$(dirname "$0")
case "$SCRIPT_DIR" in
  /*) ;;
  *) SCRIPT_DIR=/www/cgi-bin ;;
esac

export BRIDGE_HOST=127.0.0.1
export BRIDGE_PORT=8189
export D810D_BRIDGE_HOST=127.0.0.1
export D810D_BRIDGE_PORT=8189
export BRIDGE_PIDFILE=/tmp/d810-bridge-v21.pid
export BRIDGE_LOG=/tmp/d810-bridge-v21.log
export BRIDGE_START_LOCK=/tmp/d810-bridge-v21.start.lock
export BRIDGE_RESTART_LOCK=/tmp/d810-bridge-v21.restart.lock
export WS_HOST=0.0.0.0
export WS_PORT=8191
export D810D_WS_HOST=0.0.0.0
export D810D_WS_PORT=8191
export WS_PIDFILE=/tmp/d810-ws-v21.pid
export WS_LOG=/tmp/d810-ws-v21.log
export WS_START_LOCK=/tmp/d810-ws-v21.start.lock
export BRIDGE_SCRIPT="$SCRIPT_DIR/d810bridge.lua"
export WS_SCRIPT="$SCRIPT_DIR/d810ws.lua"
export D810D_PREFER_LEGACY_TRANSPORT=0
