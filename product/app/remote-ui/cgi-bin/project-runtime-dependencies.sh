#!/bin/sh

# Project-owned runtime dependencies. Nothing here is installed into the
# firmware package database or started from the SFT1200 boot path.
NIXIO_SOURCE=${D810D_NIXIO_SOURCE:-/www/remote-ui/runtime/lua/5.1/nixio.so}
NIXIO_SHA256=${D810D_NIXIO_SHA256:-7f9ec167aa2db69ae6f75bca6d0590b27dc6a689e19be3264697b61fcc2237dd}
NIXIO_RUNTIME_ROOT=${D810D_NIXIO_RUNTIME_ROOT:-/tmp/d810-project-runtime/lua/5.1}
NIXIO_RUNTIME_MODULE="$NIXIO_RUNTIME_ROOT/nixio.so"
NIXIO_LUA_BIN=${D810D_NIXIO_LUA_BIN:-/usr/bin/lua}

project_file_sha256() {
  sha256sum "$1" 2>/dev/null | awk '{ print $1 }'
}

project_nixio_probe() {
  [ -x "$NIXIO_LUA_BIN" ] || return 1
  [ -r "$NIXIO_RUNTIME_MODULE" ] || return 1
  actual_hash=$(project_file_sha256 "$NIXIO_RUNTIME_MODULE")
  [ "$actual_hash" = "$NIXIO_SHA256" ] || return 1
  LUA_CPATH="$NIXIO_RUNTIME_ROOT/?.so;;" \
    "$NIXIO_LUA_BIN" -e 'local n = require("nixio"); assert(type(n.socket) == "function"); assert(type(n.gettimeofday) == "function")' \
    >/dev/null 2>&1
}

project_nixio_prepare() {
  project_nixio_probe && return 0
  [ -r "$NIXIO_SOURCE" ] || return 1
  source_hash=$(project_file_sha256 "$NIXIO_SOURCE")
  [ "$source_hash" = "$NIXIO_SHA256" ] || return 1
  mkdir -p "$NIXIO_RUNTIME_ROOT" || return 1
  tmp_module="$NIXIO_RUNTIME_MODULE.$$"
  cp "$NIXIO_SOURCE" "$tmp_module" || return 1
  chmod 0555 "$tmp_module" || {
    rm -f "$tmp_module"
    return 1
  }
  mv -f "$tmp_module" "$NIXIO_RUNTIME_MODULE" || return 1
  project_nixio_probe
}

project_nixio_cpath() {
  printf '%s' "$NIXIO_RUNTIME_ROOT/?.so;;"
}
