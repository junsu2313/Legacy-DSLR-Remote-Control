#!/usr/bin/lua

local now_ms
local socket
local nixio_mod
do
  local ok_nixio, nixio = pcall(require, "nixio")
  if ok_nixio then
    nixio_mod = nixio
    local function method(obj, names)
      for _, name in ipairs(names) do
        if type(obj[name]) == "function" then
          return obj[name]
        end
      end
      return nil
    end

    local function wrap_client(tcp)
      local client = {}
      local pending = ""

      local function wait_deadline(timeout)
        timeout = tonumber(timeout) or 0
        if timeout <= 0 then
          return nil
        end
        return now_ms() + math.floor(timeout * 1000)
      end

      function client:readfull(length, _timeout)
        local recv = method(tcp, { "recv", "receive", "read" })
        if not recv then
          return nil, "socket has no receive method"
        end
        local deadline = wait_deadline(_timeout)
        local chunks = {}
        local remaining = length
        while remaining > 0 do
          local chunk, err, partial
          if #pending > 0 then
            chunk = pending
            pending = ""
          else
            chunk, err, partial = recv(tcp, remaining)
            chunk = chunk or partial
          end
          if chunk and #chunk > 0 then
            if #chunk > remaining then
              chunks[#chunks + 1] = chunk:sub(1, remaining)
              pending = chunk:sub(remaining + 1)
              remaining = 0
            else
              chunks[#chunks + 1] = chunk
              remaining = remaining - #chunk
            end
          else
            return nil, err or "socket closed"
          end
          if deadline and now_ms() >= deadline and remaining > 0 then
            return nil, "timeout"
          end
        end
        return table.concat(chunks)
      end

      function client:readuntil(_delim)
        local recv = method(tcp, { "recv", "receive", "read" })
        if not recv then
          return nil, "socket has no receive method"
        end
        local deadline = wait_deadline(5)
        local out = {}
        while true do
          local chunk, err, partial
          if #pending > 0 then
            chunk = pending:sub(1, 1)
            pending = pending:sub(2)
          else
            chunk, err, partial = recv(tcp, 1)
            chunk = chunk or partial
            if chunk and #chunk > 1 then
              pending = chunk:sub(2)
              chunk = chunk:sub(1, 1)
            end
          end
          if chunk and #chunk > 0 then
            if chunk == "\n" then
              return table.concat(out)
            end
            out[#out + 1] = chunk
          else
            if #out > 0 then
              return table.concat(out)
            end
            return nil, err or "closed"
          end
          if deadline and now_ms() >= deadline then
            if #out > 0 then
              return table.concat(out)
            end
            return nil, "timeout"
          end
        end
      end

      function client:write(data)
        local send = method(tcp, { "send", "write" })
        if not send then
          return nil, "socket has no send method"
        end
        local sent = 0
        while sent < #data do
          -- The first send can use the original immutable Lua string directly.
          -- Slice only after a genuine partial write instead of copying every
          -- JPEG once before it reaches the socket.
          local chunk = sent == 0 and data or data:sub(sent + 1)
          local ok, err = send(tcp, chunk)
          if ok == nil or ok == false or ok == 0 then
            return nil, err or "socket closed"
          end
          sent = sent + (tonumber(ok) or (#data - sent))
        end
        return true
      end

      function client:close()
        pcall(function()
          tcp:close()
        end)
      end

      return client
    end

    socket = {}

    function socket.connect_tcp(host, port)
      local tcp = nixio.socket("inet", "stream")
      if not tcp then
        return nil, "unable to create tcp socket"
      end
      local connect = method(tcp, { "connect" })
      if not connect then
        return nil, "socket has no connect method"
      end
      local ok, conn_err = connect(tcp, host, port)
      if not ok then
        pcall(function()
          tcp:close()
        end)
        return nil, conn_err
      end
      pcall(function()
        tcp:setblocking(true)
      end)
      pcall(function()
        tcp:setopt("tcp", "nodelay", 1)
      end)
      return wrap_client(tcp)
    end

    function socket.listen_tcp(host, port, _opts)
      local server = nixio.socket("inet", "stream")
      if not server then
        return nil, "unable to create tcp socket"
      end
      if _opts and _opts.reuseaddr and type(server.setopt) == "function" then
        pcall(function()
          server:setopt("socket", "reuseaddr", 1)
        end)
      end
      local bind = method(server, { "bind" })
      local listen = method(server, { "listen" })
      if not bind or not listen then
        pcall(function()
          server:close()
        end)
        return nil, "socket missing bind/listen methods"
      end
      local ok, err = bind(server, host, port)
      if not ok then
        pcall(function()
          server:close()
        end)
        return nil, err
      end
      local ok_listen, listen_err = listen(server, 16)
      if not ok_listen then
        pcall(function()
          server:close()
        end)
        return nil, listen_err
      end
      pcall(function()
        server:setblocking(false)
      end)

      local wrapper = {}

      function wrapper:accept()
        local accept = method(server, { "accept" })
        if not accept then
          return nil
        end
        local ok_accept, tcp = pcall(accept, server)
        if not ok_accept then
          return nil
        end
        if not tcp then
          return nil
        end
        if _opts and _opts.tcp_nodelay and type(tcp.setopt) == "function" then
          pcall(function()
            tcp:setopt("tcp", "nodelay", 1)
          end)
        end
        if _opts and _opts.nonblocking_clients and type(tcp.setblocking) == "function" then
          pcall(function()
            tcp:setblocking(false)
          end)
        end
        return wrap_client(tcp)
      end

      function wrapper:close()
        pcall(function()
          server:close()
        end)
      end

      return wrapper
    end
  else
    local ok_eco, eco_socket = pcall(require, "eco.socket")
    if ok_eco then
      socket = eco_socket
    else
      error("neither nixio nor eco.socket is available")
    end
  end
end

local DDSERVER_HOST = os.getenv("D810D_DDSERVER_HOST") or "127.0.0.1"
local DDSERVER_PORT = tonumber(os.getenv("D810D_DDSERVER_PORT") or "4757")
local BRIDGE_HOST = os.getenv("D810D_BRIDGE_HOST") or "127.0.0.1"
local BRIDGE_PORT = tonumber(os.getenv("D810D_BRIDGE_PORT") or "8089")
local STREAM_HOST = os.getenv("D810D_STREAM_HOST") or "127.0.0.1"
local STREAM_PORT = tonumber(os.getenv("D810D_STREAM_PORT") or "8190")
local SESSION_DIR = os.getenv("D810D_SESSION_DIR") or ""
function session_path(name, fallback)
  if SESSION_DIR ~= "" then
    return SESSION_DIR .. "/" .. name
  end
  return fallback
end
local FRAME_PATH = os.getenv("D810D_FRAME_PATH") or "/tmp/d810-live.jpg"
local FRAME_LAST_GOOD = os.getenv("D810D_FRAME_LAST_GOOD") or "/tmp/d810-live-last-good.jpg"
local CAPTURED_PREVIEW_PATH = os.getenv("D810D_CAPTURED_PREVIEW_PATH") or "/tmp/d810-captured-preview.jpg"
local CAPTURED_OBJECT_PATH = os.getenv("D810D_CAPTURED_OBJECT_PATH") or "/tmp/d810-captured-object.jpg"
local SESSION_STATE = os.getenv("D810D_SESSION_STATE") or session_path("state.txt", "/tmp/d810-session.state")
local READINESS_STATS_PATH = os.getenv("D810D_READINESS_STATS_PATH") or "/root/d810-readiness.stats"
local SESSION_MODE = os.getenv("D810D_SESSION_MODE") or session_path("mode.txt", "/tmp/d810-session.mode")
local SESSION_BOOT = os.getenv("D810D_SESSION_BOOT") or session_path("boot.txt", "/tmp/d810-session.boot")
local SESSION_ID = tonumber(os.getenv("D810D_SESSION_ID") or "") or nil
local SESSION_LABEL = os.getenv("D810D_SESSION_LABEL") or ""
local LIVE_SESSION_PATH = os.getenv("D810D_LIVE_SESSION_PATH") or "/tmp/d810-live-v21.session"
local FIXED_LIVE_SESSION_ID = tonumber(os.getenv("D810D_LIVE_SESSION_ID") or "") or nil
local FIXED_LIVE_SESSION_LABEL = os.getenv("D810D_LIVE_SESSION_LABEL") or ""
local LIVE_SESSION_ID = nil
local LIVE_SESSION_LABEL = ""
local BRIDGE_TIMEOUT = tonumber(os.getenv("D810D_BRIDGE_TIMEOUT") or "10")
local DEBUG_LOG = os.getenv("D810D_DEBUG_LOG") or session_path("bridge.log", "/tmp/d810-bridge-debug.log")
local BRIDGE_LOG_PATH = os.getenv("BRIDGE_LOG") or ""
SESSION_LOG_STATE = {
  path = DEBUG_LOG,
  rotate_bytes = tonumber(os.getenv("D810D_SESSION_LOG_ROTATE_BYTES") or "3145728") or 3145728,
  check_count = 0,
}
GLOBAL_LOG_STATE = {
  path = os.getenv("D810D_GLOBAL_LOG") or "/root/d810-camera-events.log",
  rotate_bytes = tonumber(os.getenv("D810D_GLOBAL_LOG_ROTATE_BYTES") or "2097152") or 2097152,
  check_count = 0,
}
local FRAME_META = os.getenv("D810D_FRAME_META") or session_path("frame.meta", "/tmp/d810-live.meta")
local CAPTURED_PREVIEW_META = os.getenv("D810D_CAPTURED_PREVIEW_META") or session_path("captured-preview.meta", "/tmp/d810-captured-preview.meta")
local CAPTURED_OBJECT_META = os.getenv("D810D_CAPTURED_OBJECT_META") or session_path("captured-object.meta", "/tmp/d810-captured-object.meta")
local FRAME_REFRESH_PIDFILE = os.getenv("D810D_FRAME_REFRESH_PIDFILE") or "/tmp/d810-live-refresh.pid"
local FRAME_CAPTURE_LOCK = os.getenv("D810D_FRAME_CAPTURE_LOCK") or "/tmp/d810-live.lock"
local COMMAND_ACTION_LOCK = os.getenv("D810D_COMMAND_ACTION_LOCK") or "/tmp/d810-command.lock"
local BRIDGE_PIDFILE = os.getenv("BRIDGE_PIDFILE") or "/tmp/d810-bridge.pid"
local BRIDGE_HEALTH_PATH = os.getenv("D810D_BRIDGE_HEALTH_PATH") or "/tmp/d810-bridge-v21.health"
local BRIDGE_HEALTH_INTERVAL_MS = tonumber(os.getenv("D810D_BRIDGE_HEALTH_INTERVAL_MS") or "1000") or 1000
local BRIDGE_HEALTH_TTL_SEC = tonumber(os.getenv("D810D_BRIDGE_HEALTH_TTL_SEC") or "3") or 3
local WS_PIDFILE = os.getenv("WS_PIDFILE") or "/tmp/d810-ws.pid"
local SESSION_HEALTH_PIDFILE = os.getenv("D810D_SESSION_HEALTH_PIDFILE") or "/tmp/d810-session-health.pid"
local STACK_GUARDIAN_PIDFILE = os.getenv("D810D_STACK_GUARDIAN_PIDFILE") or "/tmp/d810-stack-guardian.pid"
local BATTERY_WORKER_PIDFILE = os.getenv("D810D_BATTERY_WORKER_PIDFILE") or "/tmp/d810-battery-worker.pid"
local BATTERY_WORKER_LOCKDIR = os.getenv("D810D_BATTERY_WORKER_LOCKDIR") or "/tmp/d810-battery-worker.lock"
local BRIDGE_START_LOCK = os.getenv("BRIDGE_START_LOCK") or "/tmp/d810-bridge.start.lock"
local BRIDGE_RESTART_LOCK = os.getenv("BRIDGE_RESTART_LOCK") or "/tmp/d810-bridge.restart.lock"
local WS_START_LOCK = os.getenv("WS_START_LOCK") or "/tmp/d810-ws.start.lock"
local SESSION_HEALTH_START_LOCK = os.getenv("D810D_SESSION_HEALTH_START_LOCK") or "/tmp/d810-session-health.start.lock"
local STACK_GUARDIAN_START_LOCK = os.getenv("D810D_STACK_GUARDIAN_START_LOCK") or "/tmp/d810-stack-guardian.start.lock"
local BATTERY_WORKER_START_LOCK = os.getenv("D810D_BATTERY_WORKER_START_LOCK") or "/tmp/d810-battery-worker.start.lock"
local NC_BIN = os.getenv("D810D_NC") or "/usr/bin/nc"
local TIMEOUT_BIN = os.getenv("D810D_TIMEOUT") or "/usr/bin/timeout"
local TRANSPORT_SCRIPT = os.getenv("D810D_TRANSPORT_SCRIPT") or "/www/cgi-bin/d810d.lua"
local GPHOTO_BIN = os.getenv("D810D_GPHOTO_BIN") or "/usr/bin/gphoto2"
local GPHOTO_DETECT_TIMEOUT = tonumber(os.getenv("D810D_GPHOTO_DETECT_TIMEOUT") or "6") or 6
local GPHOTO_DETECT_MODEL = os.getenv("D810D_GPHOTO_DETECT_MODEL") or "Nikon DSC D810"
local PROBE_CACHE_TTL_MS = tonumber(os.getenv("D810D_PROBE_CACHE_TTL_MS") or "2500") or 2500
local STATUS_ACTION_TIMEOUT = tonumber(os.getenv("D810D_STATUS_ACTION_TIMEOUT") or "3") or 3
local STATUS_GPHOTO_TIMEOUT = tonumber(os.getenv("D810D_STATUS_GPHOTO_TIMEOUT") or "3") or 3
local DDSERVER_INIT = os.getenv("D810D_DDSERVER_INIT") or "/www/cgi-bin/project-ddserver-runtime"
local DDSERVER_RECOVER_TIMEOUT = tonumber(os.getenv("D810D_DDSERVER_RECOVER_TIMEOUT") or "10") or 10
local FRAME_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_FRAME_LOCK_TIMEOUT_MS") or "220") or 220
local FRAME_LOCK_WAIT_MS = tonumber(os.getenv("D810D_FRAME_LOCK_WAIT_MS") or "120") or 120
local COMMAND_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_COMMAND_LOCK_TIMEOUT_MS") or "1200") or 1200
local FRAME_COMMAND_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_FRAME_COMMAND_LOCK_TIMEOUT_MS") or "80") or 80
local LOCK_STALE_MS = tonumber(os.getenv("D810D_LOCK_STALE_MS") or "4000") or 4000
local FRAME_STABLE_AGE_MS = tonumber(os.getenv("D810D_FRAME_STABLE_AGE_MS") or "0") or 0
local STATUS_CACHE_TTL_MS = tonumber(os.getenv("D810D_STATUS_CACHE_TTL_MS") or "350") or 350
local CAPABILITY_CERTIFICATION_TTL_MS = tonumber(os.getenv("D810D_CAPABILITY_CERTIFICATION_TTL_MS") or "0") or 0
-- Battery is a camera-originated PTP measurement.  Do not let a stale
-- session value masquerade as the current camera state.
local BATTERY_CACHE_TTL_MS = tonumber(os.getenv("D810D_BATTERY_CACHE_TTL_MS") or "0") or 0
local LIVE_VIEW_LOW_BATTERY_THRESHOLD = tonumber(os.getenv("D810D_LIVE_VIEW_LOW_BATTERY_THRESHOLD") or "20") or 20
local CONNECT_RETRY_DELAY_MS = tonumber(os.getenv("D810D_CONNECT_RETRY_DELAY_MS") or "3000") or 3000
local SESSION_STALE_MS = tonumber(os.getenv("D810D_SESSION_STALE_MS") or "1500") or 1500
local TRACE_FRAMES = tostring(os.getenv("D810D_TRACE_FRAMES") or "0") == "1"
TRACE_TRANSPORT = tostring(os.getenv("D810D_TRACE_TRANSPORT") or "0") == "1"
MAX_TRANSPORT_PACKET_BYTES = tonumber(os.getenv("D810D_MAX_TRANSPORT_PACKET_BYTES") or "67108864") or 67108864
local FRAME_HEALTH_STALE_MS = tonumber(os.getenv("D810D_FRAME_HEALTH_STALE_MS") or "800") or 800
local FRAME_LAST_GOOD_GRACE_MS = tonumber(os.getenv("D810D_FRAME_LAST_GOOD_GRACE_MS") or "2500") or 2500
LIVE_FRAME_CACHE_INTERVAL_MS = tonumber(os.getenv("D810D_LIVE_FRAME_CACHE_INTERVAL_MS") or "1000") or 1000
LIVE_LAST_GOOD_INTERVAL_MS = tonumber(os.getenv("D810D_LIVE_LAST_GOOD_INTERVAL_MS") or "5000") or 5000
FAST_LIVE_VIEW_9203 = tostring(os.getenv("D810D_FAST_LIVE_VIEW_9203") or "1") ~= "0"
local LIVE_VIEW_WARMUP_MS = tonumber(os.getenv("D810D_LIVE_VIEW_WARMUP_MS") or "220") or 220
LIVE_VIEW_START_RETRY_COUNT = tonumber(os.getenv("D810D_LIVE_VIEW_START_RETRY_COUNT") or "10") or 10
LIVE_VIEW_START_RETRY_MS = tonumber(os.getenv("D810D_LIVE_VIEW_START_RETRY_MS") or "150") or 150
LIVE_VIEW_BUSY_SETTLE_MS = tonumber(os.getenv("D810D_LIVE_VIEW_BUSY_SETTLE_MS") or "5000") or 5000
LIVE_FIRST_FRAME_RETRY_COUNT = tonumber(os.getenv("D810D_LIVE_FIRST_FRAME_RETRY_COUNT") or "20") or 20
LIVE_FIRST_FRAME_RETRY_MS = tonumber(os.getenv("D810D_LIVE_FIRST_FRAME_RETRY_MS") or "100") or 100
LIVE_FRAME_FAILURE_BACKOFF_BASE_MS = tonumber(os.getenv("D810D_LIVE_FRAME_FAILURE_BACKOFF_BASE_MS") or "25") or 25
LIVE_FRAME_FAILURE_BACKOFF_MAX_MS = tonumber(os.getenv("D810D_LIVE_FRAME_FAILURE_BACKOFF_MAX_MS") or "500") or 500
LIVE_FRAME_TRANSPORT_RECOVER_THRESHOLD = tonumber(os.getenv("D810D_LIVE_FRAME_TRANSPORT_RECOVER_THRESHOLD") or "3") or 3
LIVE_FRAME_TRANSPORT_RECOVER_COOLDOWN_MS = tonumber(os.getenv("D810D_LIVE_FRAME_TRANSPORT_RECOVER_COOLDOWN_MS") or "3000") or 3000
local IDLE_PURGE_MS = tonumber(os.getenv("D810D_IDLE_PURGE_MS") or "600000") or 600000
local BACKEND_NAME = os.getenv("D810D_BACKEND_NAME") or "session-backend"
local FRAME_REFRESH_SCRIPT = os.getenv("D810D_FRAME_REFRESH_SCRIPT")
  or (tostring(arg and arg[0] or ""):gsub("d810bridge%.lua$", "frame-refresh"))
  or "/www/cgi-bin/frame-refresh"

local CONTAINER_COMMAND = 0x0001
local CONTAINER_DATA = 0x0002
local CONTAINER_RESPONSE = 0x0003

local CMD_GET_DEVICES = 0x0002
local CMD_CONNECT_DEVICE = 0x0001
local CMD_OPEN_SESSION = 0x1002
local CMD_GET_STORAGE_IDS = 0x1004
local CMD_GET_STORAGE_INFO = 0x1005
local CMD_GET_OBJECT_HANDLES = 0x1007
local CMD_GET_OBJECT_INFO = 0x1008
local CMD_GET_OBJECT = 0x1009
local CMD_GET_THUMB = 0x100A
local CMD_GET_PARTIAL_OBJECT = 0x101B
local CMD_GET_DEVICE_PROP_DESC = 0x1014
local CMD_GET_DEVICE_PROP_VALUE = 0x1015
local CMD_SET_DEVICE_PROP_VALUE = 0x1016
local RESP_OK = 0x2001
local RESP_GENERAL_ERROR = 0x2002
local RESP_SESSION_NOT_OPEN = 0x2003
local RESP_DEVICE_BUSY = 0x2019
local RESP_SESSION_ALREADY_OPEN = 0x201E

local NIKON_DEVICE_READY = 0x90C8
local NIKON_AF_DRIVE = 0x90C1
local NIKON_START_LIVE_VIEW = 0x9201
local NIKON_END_LIVE_VIEW = 0x9202
local NIKON_GET_LIVE_VIEW_IMAGE = 0x9203
local NIKON_SHUTTER = 0x9207
local NIKON_CHANGE_CAMERA_MODE = 0x90C2
CAPTURE_EVENT = {
  GET = 0x90C7,
  OBJECT_ADDED = 0x4002,
  CAPTURE_COMPLETE = 0x400D,
  OBJECT_ADDED_IN_SDRAM = 0xC101,
  CAPTURE_COMPLETE_IN_SDRAM = 0xC102,
}

local PROP_LIVE_VIEW_STATUS = 0xD1A2
local PROP_LIVE_VIEW_SELECTOR = 0xD1A6
local PROP_RECORDING_MEDIA = 0xD10B
local PROP_BATTERY_LEVEL = 0x5001
local PROP_IMAGE_SIZE = 0x5003
local PROP_COMPRESSION_SETTING = 0x5004
PROP_FNUMBER = 0x5007
PROP_EXPOSURE_TIME = 0x500D
PROP_EXPOSURE_PROGRAM_MODE = 0x500E
PROP_EXPOSURE_INDEX = 0x500F
local PROP_EXPOSURE_ISO_STATUS = 0xD1AA
PROP_STILL_CAPTURE_MODE = 0x5013
PROP_AUTO_ISO = 0xD054
PROP_AF_MODE_SELECT = 0xD161
local EVENT_DEVICE_PROP_CHANGED = 0x4006
local COMPRESSION_RAW_WITH_FINE_JPEG = 7
local PREVIEW_JPEG_IMAGE_SIZE = "3680x2456"
local MTP_NOT_LIVE_VIEW = 0xA00B
NIKON_OUT_OF_FOCUS = 0xA002
NIKON_INVALID_STATUS = 0xA003
local OBJECT_FORMAT_ASSOCIATION = 0x3001
local OBJECT_FORMAT_UNDEFINED = 0x3000
local OBJECT_FORMAT_EXIF_JPEG = 0x3801
local OBJECT_FORMAT_JFIF = 0x3808
local OBJECT_FORMAT_JPEG_UNKNOWN = 0x3800
local PTP_ALL_STORAGES = 0xFFFFFFFF
local PTP_ALL_OBJECT_FORMATS = 0x00000000
local PTP_ROOT_PARENT = 0xFFFFFFFF
local CAPTURED_JPEG_SCAN_LIMIT = tonumber(os.getenv("D810D_CAPTURED_JPEG_SCAN_LIMIT") or "24") or 24
CAPTURED_BROWSER_LIST_LIMIT = tonumber(os.getenv("D810D_CAPTURED_BROWSER_LIST_LIMIT") or "1000") or 1000
CAPTURED_BROWSER_SCAN_LIMIT = tonumber(os.getenv("D810D_CAPTURED_BROWSER_SCAN_LIMIT") or "4096") or 4096
local CAPTURED_NEF_SCAN_LIMIT = tonumber(os.getenv("D810D_CAPTURED_NEF_SCAN_LIMIT") or "512") or 512
local CAPTURED_NEF_MIN_BYTES = tonumber(os.getenv("D810D_CAPTURED_NEF_MIN_BYTES") or "4194304") or 4194304
local CAPTURED_OBJECT_TIMEOUT = tonumber(os.getenv("D810D_CAPTURED_OBJECT_TIMEOUT") or "120") or 120
local CAPTURED_OBJECT_CHUNK_SIZE = tonumber(os.getenv("D810D_CAPTURED_OBJECT_CHUNK_SIZE") or "524288") or 524288
local CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT = tonumber(os.getenv("D810D_CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT") or "4194304") or 4194304
CAPTURED_OBJECT_LIVE_PAUSE_MS = tonumber(os.getenv("D810D_CAPTURED_OBJECT_LIVE_PAUSE_MS") or "150") or 150

local function fail(status, message)
  error({ status = status, message = message }, 0)
end

function error_text(err)
  if type(err) == "table" then
    return tostring(err.message or err.status or "structured error")
  end
  return tostring(err or "unknown")
end

function rethrow(err, fallback_status)
  if type(err) == "table" then
    fail(err.status or fallback_status or "transport_error", err.message or "structured error")
  end
  fail(fallback_status or "transport_error", tostring(err or "unknown error"))
end

local function le_u16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le_u32(n)
  local b1 = n % 256
  n = math.floor(n / 256)
  local b2 = n % 256
  n = math.floor(n / 256)
  local b3 = n % 256
  n = math.floor(n / 256)
  local b4 = n % 256
  return string.char(b1, b2, b3, b4)
end

local function encode_ptp_string(value)
  value = tostring(value or "")
  if value == "" then
    return string.char(0)
  end
  local out = { string.char(#value + 1) }
  for i = 1, #value do
    out[#out + 1] = string.char(value:byte(i), 0)
  end
  out[#out + 1] = string.char(0, 0)
  return table.concat(out)
end

local function u16(s, i)
  local b1, b2 = s:byte(i, i + 1)
  if not b1 then
    return 0
  end
  return b1 + (b2 or 0) * 256
end

local function u32(s, i)
  local b1, b2, b3, b4 = s:byte(i, i + 3)
  if not b1 then
    return 0
  end
  return b1 + (b2 or 0) * 256 + (b3 or 0) * 65536 + (b4 or 0) * 16777216
end

local function u64(s, i)
  return u32(s, i) + u32(s, i + 4) * 4294967296
end

local function pack_container(ctype, code, payload, transaction_id)
  payload = payload or ""
  transaction_id = transaction_id or 0
  local body = le_u32(12 + #payload)
    .. string.char(ctype, 0)
    .. le_u16(code)
    .. le_u32(transaction_id)
    .. payload
  return le_u32(#body + 4) .. body
end

local function json_escape(text)
  text = tostring(text or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\r", "\\r")
  text = text:gsub("\n", "\\n")
  text = text:gsub("\t", "\\t")
  return text
end

local function bytes_to_hex(data, limit)
  if type(data) ~= "string" then
    return ""
  end
  limit = math.min(limit or #data, #data)
  local out = {}
  for i = 1, limit do
    out[#out + 1] = string.format("%02x", data:byte(i))
  end
  return table.concat(out, " ")
end

local session_label_from_id, current_session_id, current_session_label

local function json_object(parts)
  local out = {}
  local data = parts or {}
  table.insert(out, string.format('"ok":%s', data.ok and "true" or "false"))
  for k, v in pairs(data) do
    if k ~= "ok" then
      if type(v) == "boolean" then
        table.insert(out, string.format('"%s":%s', k, v and "true" or "false"))
      elseif type(v) == "number" then
        table.insert(out, string.format('"%s":%s', k, tostring(v)))
      elseif v ~= nil then
        table.insert(out, string.format('"%s":"%s"', k, json_escape(v)))
      end
    end
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local function response_ok(status, extra)
  extra = extra or {}
  extra.sessionId = extra.sessionId or current_session_id()
  extra.sessionLabel = extra.sessionLabel or current_session_label()
  extra.ok = true
  extra.status = status
  return json_object(extra)
end

local function response_error(status, message)
  return json_object({
    sessionId = current_session_id(),
    sessionLabel = current_session_label(),
    ok = false,
    status = status,
    message = message or "",
  })
end

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_prop_code_list(text)
  local codes = {}
  text = trim(text or "")
  if text == "" then
    return codes
  end
  for token in text:gmatch("[^,%s]+") do
    local value = tonumber(token)
    if not value then
      value = tonumber(token:gsub("^0[xX]", ""), 16)
    end
    if value then
      codes[#codes + 1] = value
    end
  end
  return codes
end

function now_ms()
  if nixio_mod and type(nixio_mod.gettimeofday) == "function" then
    local sec, usec = nixio_mod.gettimeofday()
    return (tonumber(sec) or 0) * 1000 + math.floor((tonumber(usec) or 0) / 1000)
  end
  return (tonumber(os.time()) or 0) * 1000
end

local function write_meta_file(path, fields)
  local temp_path = path .. ".tmp"
  local handle = io.open(temp_path, "wb")
  if not handle then
    return false
  end
  for k, v in pairs(fields or {}) do
    handle:write(string.format("%s=%s\n", tostring(k), tostring(v)))
  end
  handle:close()
  local renamed = os.rename(temp_path, path)
  if not renamed then
    pcall(function() os.remove(temp_path) end)
  end
  return renamed and true or false
end

local function write_meta(fields)
  return write_meta_file(FRAME_META, fields)
end

local function read_state_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local fields = {}
  for line in handle:lines() do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      fields[key] = value
    end
  end
  handle:close()
  return fields
end

local function write_state_file(path, fields)
  return write_meta_file(path, fields)
end

local function read_mode_file(path)
  local state = read_state_file(path)
  if type(state) ~= "table" then
    return nil
  end
  local mode = tostring(state.mode or "")
  if mode == "live" or mode == "ready" then
    return mode
  end
  return nil
end

local function write_mode_file(path, mode)
  return write_state_file(path, {
    mode = tostring(mode or "idle"),
  })
end

local function read_meta_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local fields = {}
  for line in handle:lines() do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      fields[key] = value
    end
  end
  handle:close()
  return fields
end

session_label_from_id = function(session_id)
  local id = tonumber(session_id)
  if not id then
    return SESSION_LABEL ~= "" and SESSION_LABEL or "000_session"
  end
  return string.format("%03d_session", math.max(0, id))
end

current_session_id = function()
  return tonumber(SESSION_ID) or nil
end

current_session_label = function()
  if tonumber(SESSION_ID) then
    return session_label_from_id(SESSION_ID)
  end
  if SESSION_LABEL ~= "" then
    return SESSION_LABEL
  end
  return "000_session"
end

local function read_live_session()
  local state = read_state_file(LIVE_SESSION_PATH)
  if type(state) ~= "table" then
    return nil, ""
  end
  local id = tonumber(state.sessionId or "")
  return id, state.sessionLabel or (id and session_label_from_id(id) or "")
end

local function ensure_live_session()
  if FIXED_LIVE_SESSION_ID then
    LIVE_SESSION_ID = FIXED_LIVE_SESSION_ID
    LIVE_SESSION_LABEL = FIXED_LIVE_SESSION_LABEL ~= ""
      and FIXED_LIVE_SESSION_LABEL
      or session_label_from_id(FIXED_LIVE_SESSION_ID)
    write_state_file(LIVE_SESSION_PATH, {
      sessionId = tostring(LIVE_SESSION_ID),
      sessionLabel = LIVE_SESSION_LABEL,
    })
    return LIVE_SESSION_ID, LIVE_SESSION_LABEL
  end
  if not LIVE_SESSION_ID then
    LIVE_SESSION_ID, LIVE_SESSION_LABEL = read_live_session()
  end
  if not LIVE_SESSION_ID then
    LIVE_SESSION_ID = current_session_id()
    LIVE_SESSION_LABEL = session_label_from_id(LIVE_SESSION_ID)
    write_state_file(LIVE_SESSION_PATH, {
      sessionId = tostring(LIVE_SESSION_ID or ""),
      sessionLabel = LIVE_SESSION_LABEL,
    })
  end
  return LIVE_SESSION_ID, LIVE_SESSION_LABEL
end

local function clear_live_session()
  LIVE_SESSION_ID = nil
  LIVE_SESSION_LABEL = ""
  pcall(function() os.remove(LIVE_SESSION_PATH) end)
end

local function debug_log(message)
  local line = string.format("[d810bridge][%s] %s\n", current_session_label(), tostring(message))
  io.stderr:write(line)
  if DEBUG_LOG ~= "" and DEBUG_LOG ~= BRIDGE_LOG_PATH then
    SESSION_LOG_STATE.check_count = SESSION_LOG_STATE.check_count + 1
    local handle = io.open(DEBUG_LOG, "a+")
    if handle then
      if SESSION_LOG_STATE.check_count == 1 or SESSION_LOG_STATE.check_count % 128 == 0 then
        local size = handle:seek("end") or 0
        if size >= SESSION_LOG_STATE.rotate_bytes then
          handle:close()
          os.remove(DEBUG_LOG .. ".1")
          os.rename(DEBUG_LOG, DEBUG_LOG .. ".1")
          handle = io.open(DEBUG_LOG, "a")
        end
      end
      handle:write(line)
      handle:close()
    end
  end
  if GLOBAL_LOG_STATE.path ~= "" then
    GLOBAL_LOG_STATE.check_count = GLOBAL_LOG_STATE.check_count + 1
    local handle = io.open(GLOBAL_LOG_STATE.path, "a+")
    if handle then
      if GLOBAL_LOG_STATE.check_count == 1 or GLOBAL_LOG_STATE.check_count % 128 == 0 then
        local size = handle:seek("end") or 0
        if size >= GLOBAL_LOG_STATE.rotate_bytes then
          handle:close()
          os.remove(GLOBAL_LOG_STATE.path .. ".2")
          os.rename(GLOBAL_LOG_STATE.path .. ".1", GLOBAL_LOG_STATE.path .. ".2")
          os.rename(GLOBAL_LOG_STATE.path, GLOBAL_LOG_STATE.path .. ".1")
          handle = io.open(GLOBAL_LOG_STATE.path, "a")
        end
      end
      if handle then
        handle:write(line)
        handle:close()
      end
    end
  end
end

function now_us()
  if nixio_mod and type(nixio_mod.gettimeofday) == "function" then
    local sec, usec = nixio_mod.gettimeofday()
    return (tonumber(sec) or 0) * 1000000 + (tonumber(usec) or 0)
  end
  return math.floor(os.clock() * 1000000)
end

local function is_jpeg_blob(data)
  return type(data) == "string"
    and #data >= 4
    and data:byte(1) == 0xFF
    and data:byte(2) == 0xD8
    and data:byte(#data - 1) == 0xFF
    and data:byte(#data) == 0xD9
end

local function extract_jpeg_blob(payload)
  if type(payload) ~= "string" or #payload == 0 then
    return nil, "empty payload"
  end

  if is_jpeg_blob(payload) then
    return payload
  end

  local soi = payload:find("\255\216", 1, true)
  if not soi then
    return nil, "jpeg start marker not found"
  end

  local eoi
  local search_from = soi + 2
  while search_from <= #payload do
    local pos = payload:find("\255\217", search_from, true)
    if not pos then
      break
    end
    eoi = pos
    search_from = pos + 2
  end
  if not eoi then
    return nil, "jpeg end marker not found"
  end

  local candidate = payload:sub(soi, eoi + 1)
  if not is_jpeg_blob(candidate) then
    return nil, "jpeg markers found but candidate was invalid"
  end
  return candidate
end

local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
  if type(data) ~= "string" or #data == 0 then
    return ""
  end

  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1)
    local c = data:byte(i + 2)
    local pad = 0
    if not b then
      b = 0
      pad = pad + 1
    end
    if not c then
      c = 0
      pad = pad + 1
    end

    local n = a * 65536 + b * 256 + c
    local c1 = math.floor(n / 262144) % 64 + 1
    local c2 = math.floor(n / 4096) % 64 + 1
    local c3 = math.floor(n / 64) % 64 + 1
    local c4 = n % 64 + 1

    out[#out + 1] = base64_chars:sub(c1, c1)
    out[#out + 1] = base64_chars:sub(c2, c2)
    out[#out + 1] = pad >= 2 and "=" or base64_chars:sub(c3, c3)
    out[#out + 1] = pad >= 1 and "=" or base64_chars:sub(c4, c4)

    i = i + 3
  end

  return table.concat(out)
end

local function write_file(path, data)
  local handle = assert(io.open(path, "wb"))
  handle:write(data)
  handle:close()
end

local function path_has_size(path)
  local handle = io.open(path, "rb")
  if not handle then
    return false
  end
  local size = handle:seek("end") or 0
  handle:close()
  return size > 0
end

local function sleep_ms(ms)
  ms = math.max(0, tonumber(ms) or 0)
  if ms <= 0 then
    return
  end
  if nixio and type(nixio.nanosleep) == "function" then
    local sec = math.floor(ms / 1000)
    local nsec = (ms - sec * 1000) * 1000000
    nixio.nanosleep(sec, nsec)
    return
  end
  os.execute(string.format("sleep %.3f", ms / 1000))
end

local shell_quote

function read_lock_owner(path)
  local handle = io.open(path .. "/owner", "rb")
  if not handle then
    return nil
  end
  local raw = trim(handle:read("*a") or "")
  handle:close()
  local stamp = tonumber(raw)
  if not stamp or stamp <= 0 then
    return nil
  end
  return stamp
end

function clear_lock_if_stale(path, stale_ms)
  local owner_at = read_lock_owner(path)
  if owner_at and (now_ms() - owner_at) < (tonumber(stale_ms) or LOCK_STALE_MS) then
    return false
  end
  pcall(function()
    os.remove(path .. "/owner")
  end)
  os.execute(string.format("rmdir %s >/dev/null 2>&1", shell_quote(path)))
  return true
end

function acquire_lock(path, timeout_ms)
  local started = now_ms()
  while now_ms() - started < timeout_ms do
    local ok = os.execute(string.format("mkdir %s >/dev/null 2>&1", shell_quote(path)))
    if ok == true or ok == 0 then
      local stamp = io.open(path .. "/owner", "wb")
      if stamp then
        stamp:write(tostring(now_ms()))
        stamp:close()
      end
      return true
    end
    clear_lock_if_stale(path, LOCK_STALE_MS)
    sleep_ms(50)
  end
  return false
end

function release_lock(path)
  pcall(function()
    os.remove(path .. "/owner")
  end)
  os.execute(string.format("rmdir %s >/dev/null 2>&1", shell_quote(path)))
end

function session_condition_from_backend(backend_state, command_busy, transport_ready, live_view_active)
  if command_busy then
    return "Busy"
  end
  if not transport_ready and not live_view_active then
    return "Preparing"
  end
  backend_state = tostring(backend_state or "idle")
  if backend_state == "recovering" or backend_state == "degraded" then
    return "Preparing"
  end
  if backend_state == "live" or backend_state == "ready" then
    return "Ready"
  end
  return "Preparing"
end

function command_lock_busy()
  local owner_at = read_lock_owner(COMMAND_ACTION_LOCK)
  if not owner_at then
    return false
  end
  if (now_ms() - owner_at) > LOCK_STALE_MS then
    clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
    return false
  end
  return true
end

shell_quote = function(text)
  text = tostring(text or "")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

function tmpname(prefix)
  local suffix = tostring(os.time()) .. "." .. tostring(math.floor(os.clock() * 1000000))
  return "/tmp/" .. tostring(prefix or "d810d") .. "." .. suffix
end

function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil, "open_failed"
  end
  local data = handle:read("*a")
  handle:close()
  return data
end

function read_prefixed_blob(data, offset)
  if offset + 3 > #data then
    return nil, offset
  end
  local length = u32(data, offset)
  if length < 4 then
    return nil, #data + 1
  end
  local body_start = offset + 4
  local body_end = offset + length - 1
  if body_end > #data then
    return nil, #data + 1
  end
  return data:sub(body_start, body_end), body_end + 1
end

function parse_container_blob(body)
  if #body < 12 then
    return nil
  end
  return {
    length = u32(body, 1),
    ctype = body:byte(5) or 0,
    code = u16(body, 7),
    txid = u32(body, 9),
    payload = body:sub(13),
  }
end

function parse_stream_blob(data)
  local offset = 1
  local blocks = {}
  local _, next_offset = read_prefixed_blob(data, offset)
  offset = next_offset or (#data + 1)
  while offset <= #data do
    local body
    body, offset = read_prefixed_blob(data, offset)
    if not body then
      break
    end
    local container = parse_container_blob(body)
    if container and container.ctype ~= 0x0004 then
      blocks[#blocks + 1] = container
    end
  end
  return blocks
end

local function file_exists(path)
  local handle = io.open(path, "rb")
  if handle then
    handle:close()
    return true
  end
  return false
end

local function read_cstring(payload, offset)
  if offset > #payload then
    return "", offset
  end
  local end_pos = payload:find("\0", offset, true)
  if not end_pos then
    return payload:sub(offset), #payload + 1
  end
  return payload:sub(offset, end_pos - 1), end_pos + 1
end

local function json_field(text, key)
  if type(text) ~= "string" then
    return nil
  end
  return text:match('"' .. key .. '":"([^"]*)"')
end

local function json_number_field(text, key)
  if type(text) ~= "string" then
    return nil
  end
  return tonumber(text:match('"' .. key .. '":([%-%d]+)'))
end

local function json_bool_field(text, key)
  if type(text) ~= "string" then
    return nil
  end
  local value = text:match('"' .. key .. '":(%a+)')
  if value == "true" then
    return true
  end
  if value == "false" then
    return false
  end
  return nil
end

local function read_ptp_string(payload, offset)
  if offset > #payload then
    return "", offset
  end
  local chars = payload:byte(offset) or 0
  offset = offset + 1
  if chars == 0 then
    return "", offset
  end
  local out = {}
  for index = 1, chars - 1 do
    local base = offset + (index - 1) * 2
    out[#out + 1] = string.char(payload:byte(base) or 0)
  end
  return table.concat(out), offset + chars * 2
end

local function parse_u32_array(payload)
  if type(payload) ~= "string" or #payload < 4 then
    return {}
  end
  local count = u32(payload, 1)
  local values = {}
  local offset = 5
  for _ = 1, count do
    if offset + 3 > #payload then
      break
    end
    values[#values + 1] = u32(payload, offset)
    offset = offset + 4
  end
  return values
end

local function is_jpeg_format(format_code)
  return format_code == OBJECT_FORMAT_EXIF_JPEG
    or format_code == OBJECT_FORMAT_JFIF
    or format_code == OBJECT_FORMAT_JPEG_UNKNOWN
end

local function select_device(devices)
  if #devices == 0 then
    return nil
  end
  for _, device in ipairs(devices) do
    local haystack = string.lower((device.vendor_name or "") .. " " .. (device.product_name or ""))
    if haystack:find("d810", 1, true) then
      return device
    end
  end
  return devices[1]
end

local function parse_u16(value, default)
  if value == nil or value == "" then
    return default
  end
  local num = tonumber(value)
  if num then
    return num
  end
  local hex = tostring(value):gsub("^0x", "")
  return tonumber(hex, 16) or default
end

local function fallback_local_device()
  return {
    vendor_id = parse_u16(os.getenv("D810D_VENDOR_ID"), 0x04B0),
    product_id = parse_u16(os.getenv("D810D_PRODUCT_ID"), 0x0436),
    vendor_name = os.getenv("D810D_VENDOR_NAME") or "NIKON",
    product_name = os.getenv("D810D_PRODUCT_NAME") or "NIKON DSC D810",
  }
end

local DdServerWire = {}
DdServerWire.__index = DdServerWire

-- Module: transport (bridge contract 1).
function DdServerWire.new(host, port, timeout)
  local prefer_legacy = os.getenv("D810D_PREFER_LEGACY_TRANSPORT")
  local legacy_transport_only = prefer_legacy == "1" or prefer_legacy == "true" or prefer_legacy == "legacy"
  return setmetatable({
    host = host,
    port = port,
    timeout = timeout or 10,
    sock = nil,
    rx_buffer = "",
    active_device = nil,
    session_id = 1,
    session_open = false,
    mode = "batch",
    protocol_ready = false,
    transport_ready = false,
    hardware_detected = false,
    legacy_transport_only = legacy_transport_only,
    last_probe = nil,
    last_probe_at = 0,
    live_view_active = false,
    last_af_success_at = 0,
    af_started_at = 0,
  }, DdServerWire)
end

function DdServerWire:close()
  if self.sock then
    pcall(function()
      self.sock:close()
    end)
  end
  self.sock = nil
  self.rx_buffer = ""
  self.protocol_ready = false
  self.session_open = false
  self.transport_ready = false
  self.live_view_active = false
  self.last_probe = nil
  self.last_probe_at = 0
  self.last_af_success_at = 0
  self.af_started_at = 0
end

function DdServerWire:enable_legacy_transport_only(reason)
  self:close()
  self.legacy_transport_only = true
  self.hardware_detected = true
  debug_log("legacy transport only enabled: " .. error_text(reason))
end

function DdServerWire:connect()
  self:close()
  debug_log(string.format("connect ddserver transport %s:%d mode=%s", self.host, self.port, self.mode))
  local sock, err = socket.connect_tcp(self.host, self.port)
  if not sock then
    fail("transport_error", err or "unable to connect to ddserver")
  end
  self.sock = sock
  self.rx_buffer = ""
  self:read_welcome()
  self.protocol_ready = true
  self.mode = "persistent"
  -- A transient ddserver outage may have enabled process-based fallback.
  -- Once the persistent socket is healthy again, never keep routing frames
  -- through d810d.lua; that path creates one helper process per frame.
  self.legacy_transport_only = false
  return true
end

function DdServerWire:graceful_close()
  if self.sock and self.session_open and not self.legacy_transport_only then
    local previous_timeout = self.timeout
    self.timeout = math.min(2, tonumber(previous_timeout) or 2)
    local ok, err = pcall(function()
      local _, response_code = self:execute(0x1003) -- PTP CloseSession
      if response_code ~= RESP_OK and response_code ~= RESP_SESSION_NOT_OPEN then
        fail("transport_error", string.format("close session failed 0x%04x", response_code or 0))
      end
    end)
    self.timeout = previous_timeout
    if not ok then
      debug_log("graceful close session failed: " .. error_text(err))
    end
  end
  self:close()
end

function DdServerWire:run_batch(request)
  local req = tmpname("d810d-req")
  local resp = tmpname("d810d-resp")
  write_file(req, request)
  local command = string.format(
    "%s -t %d %s %s %d < %s > %s 2>/dev/null",
    shell_quote(TIMEOUT_BIN),
    math.max(1, tonumber(self.timeout) or 10),
    shell_quote(NC_BIN),
    shell_quote(self.host),
    tonumber(self.port) or 4757,
    shell_quote(req),
    shell_quote(resp)
  )
  local ok = os.execute(command)
  local data = read_file(resp) or ""
  pcall(function()
    os.remove(req)
    os.remove(resp)
  end)
  if (ok ~= true and ok ~= 0) or data == "" then
    fail("transport_error", "ddserver batch request failed")
  end
  return data
end

function DdServerWire:run_transport_action(mode, timeout_override)
  local timeout_sec = timeout_override ~= nil
    and math.max(1, tonumber(timeout_override) or 1)
    or math.max(30, tonumber(self.timeout) or 10)
  local out_path = tmpname()
  local cmd = string.format(
    "%s -t %d %s %s %s > %s 2>/dev/null",
    shell_quote(TIMEOUT_BIN),
    timeout_sec,
    shell_quote("/usr/bin/lua"),
    shell_quote(TRANSPORT_SCRIPT),
    shell_quote(tostring(mode or "status")),
    shell_quote(out_path)
  )
  local ok = os.execute(cmd)
  local output = read_file(out_path) or ""
  debug_log(string.format("transport action %s cmd=%s exit=%s output=%s", tostring(mode), tostring(cmd), tostring(ok), tostring(output:sub(1, 180))))
  if output:find('"ok":true', 1, true) then
    return output
  end
  if ok ~= true and ok ~= 0 then
    fail("transport_error", "transport action failed: " .. tostring(mode))
  end
  return output
end

function DdServerWire:detect_camera_hardware(timeout_override)
  local timeout_sec = math.max(1, tonumber(timeout_override) or tonumber(GPHOTO_DETECT_TIMEOUT) or 6)
  local out_path = "/tmp/gphoto-detect.out"
  local cmd = string.format(
    "%s -t %d %s --auto-detect > %s 2>/dev/null",
    shell_quote(TIMEOUT_BIN),
    timeout_sec,
    shell_quote(GPHOTO_BIN),
    shell_quote(out_path)
  )
  local ok = os.execute(cmd)
  local output = read_file(out_path) or ""
  local detected = false
  if ok == true or ok == 0 then
    detected = output:find(GPHOTO_DETECT_MODEL, 1, true) ~= nil
      or output:find("usb:", 1, true) ~= nil
  end
  self.hardware_detected = detected
  return detected, output
end

function DdServerWire:probe_camera_state(options)
  local include_hardware = true
  local force_probe = false
  if type(options) == "table" then
    if options.includeHardware == false then
      include_hardware = false
    end
    force_probe = options.force == true
  elseif options == false then
    include_hardware = false
  end
  local now = now_ms()
  if not force_probe and self.last_probe and self.last_probe_at > 0 and (now - self.last_probe_at) <= PROBE_CACHE_TTL_MS then
    return self.last_probe
  end
  local transport_ready = false
  local live_view = false
  local battery = nil
  local status_name = "transport_error"
  local status_message = ""

  if self.session_open and self.sock then
    transport_ready = true
    local ok_live, live_payload = pcall(function()
      return self:get_device_prop_value(PROP_LIVE_VIEW_STATUS)
    end)
    if ok_live and type(live_payload) == "string" then
      live_view = #live_payload > 0 and live_payload:byte(1) == 1
      status_name = live_view and "liveview_on" or "ready"
    else
      transport_ready = false
      status_name = "transport_error"
      status_message = type(live_payload) == "table" and (live_payload.message or live_payload.status) or tostring(live_payload or "")
    end
  else
    status_message = "camera hardware scan"
  end
  local hardware_detected = self.hardware_detected == true
  if include_hardware then
    hardware_detected = self:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
  end
  if self.legacy_transport_only and hardware_detected then
    local ok_legacy, legacy_output = pcall(function()
      return self:run_transport_action("status", STATUS_ACTION_TIMEOUT)
    end)
    transport_ready = ok_legacy and type(legacy_output) == "string"
      and legacy_output:find('"ok":true', 1, true) ~= nil
    if transport_ready then
      live_view = json_bool_field(legacy_output, "liveView") == true
      status_name = live_view and "liveview_on" or "ready"
    else
      status_name = "transport_error"
      status_message = ok_legacy and "legacy camera status probe failed" or error_text(legacy_output)
    end
  end
  if battery == nil and self.last_power and self.last_power.batteryPercent ~= nil then
    battery = tonumber(self.last_power.batteryPercent)
  end
  local camera_detected = transport_ready or hardware_detected
  local battery_sampled = false
  if transport_ready and not self.legacy_transport_only then
    battery_sampled = true
    local ok_battery, battery_value = pcall(function()
      return self:get_battery_percent()
    end)
    if ok_battery and type(battery_value) == "number" then
      battery = battery_value
    end
  end
  self.transport_ready = transport_ready
  if include_hardware then
    self.hardware_detected = hardware_detected
  end
  self.last_probe = {
    cameraDetected = camera_detected,
    transportReady = transport_ready,
    hardwareDetected = hardware_detected,
    liveView = live_view,
    batteryPercent = battery,
    batterySampled = battery_sampled,
    batterySource = battery_sampled and "ptp" or nil,
    batteryMeasuredAtMs = battery_sampled and now_ms() or 0,
    status = status_name,
    message = status_message,
  }
  self.last_probe_at = now
  return self.last_probe
end

function DdServerWire:clear_probe_cache()
  self.last_probe = nil
  self.last_probe_at = 0
end

function DdServerWire:reset_transport_service()
  if not file_exists(DDSERVER_INIT) then
    return false, "ddserver init script missing"
  end
  self:clear_probe_cache()
  local cmd = string.format(
    "%s -t %d %s restart >/dev/null 2>&1",
    shell_quote(TIMEOUT_BIN),
    math.max(2, tonumber(DDSERVER_RECOVER_TIMEOUT) or 10),
    shell_quote(DDSERVER_INIT)
  )
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then
    return false, "ddserver restart failed"
  end
  sleep_ms(900)
  self:clear_probe_cache()
  return true
end

function DdServerWire:ensure_transport_ready(allow_reset)
  local probe = self:probe_camera_state()
  if probe.transportReady then
    return probe
  end
  if not probe.hardwareDetected then
    fail("camera_missing", probe.message ~= "" and probe.message or "camera is not detected")
  end
  fail("transport_error", "camera transport unavailable")
end

function DdServerWire:request_blocks(command_packets)
  if not self.active_device then
    fail("camera_missing", "no active device")
  end
  if not self.session_open then
    fail("transport_error", "ddserver session is not open")
  end
  for _, packet in ipairs(command_packets or {}) do
    local written, err = self.sock:write(packet)
    if not written then
      fail("transport_error", err or "ddserver write failed")
    end
  end
  return self:read_response_blocks(1)
end

function DdServerWire:execute(code, params, payload)
  params = params or {}
  payload = payload or ""
  local param_bytes = {}
  for _, param in ipairs(params) do
    param_bytes[#param_bytes + 1] = le_u32(tonumber(param) or 0)
  end
  local ok_blocks, blocks_or_err = pcall(function()
    local command_packet = pack_container(CONTAINER_COMMAND, code, table.concat(param_bytes))
    local packets = { command_packet }
    if #payload > 0 then
      local command_container = command_packet:sub(5)
      local data_container = pack_container(CONTAINER_DATA, code, payload):sub(5)
      packets = { le_u32(4 + #command_container + #data_container) .. command_container .. data_container }
    end
    return self:request_blocks(packets)
  end)
  if not ok_blocks then
    fail("transport_error", tostring(blocks_or_err or "ddserver execute failed"))
  end
  local blocks = blocks_or_err
  local response_code = RESP_OK
  local data_payload = nil
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      data_payload = block.payload
    elseif block.ctype == CONTAINER_RESPONSE then
      response_code = block.code
    end
  end
  if response_code == RESP_SESSION_NOT_OPEN then
    fail("transport_error", string.format("ddserver session lost around 0x%04x", code))
  end
  return data_payload, response_code, CONTAINER_RESPONSE
end

function DdServerWire:execute_live_view_image(wait_hook)
  if not self.active_device then
    fail("camera_missing", "no active device")
  end
  if not self.session_open then
    fail("transport_error", "ddserver session is not open")
  end

  local request_started_us = now_us()
  local written, write_err = self.sock:write(pack_container(
    CONTAINER_COMMAND,
    NIKON_GET_LIVE_VIEW_IMAGE,
    ""
  ))
  if not written then
    fail("transport_error", write_err or "ddserver live-view write failed")
  end
  local request_written_us = now_us()
  local wait_hook_us = 0
  if type(wait_hook) == "function" then
    local wait_hook_started_us = now_us()
    local hook_ok, hook_err = pcall(wait_hook)
    wait_hook_us = math.max(0, now_us() - wait_hook_started_us)
    if not hook_ok then
      debug_log("live-view wait hook failed: " .. tostring(hook_err))
    end
  end
  local first_packet_us = 0
  local frame = nil
  local response_code = nil
  local packets_read = 0
  local parse_started_us = 0

  while response_code == nil and packets_read < 4 do
    local packet = self:read_prefixed_packet()
    packets_read = packets_read + 1
    if first_packet_us == 0 then
      first_packet_us = now_us()
      parse_started_us = first_packet_us
    end
    local offset = 1
    while offset + 11 <= #packet do
      local length = u32(packet, offset)
      if length < 12 or offset + length - 1 > #packet then
        fail("transport_error", "invalid ddserver live-view container")
      end
      local ctype = packet:byte(offset + 4) or 0
      local code = u16(packet, offset + 6)
      local payload_start = offset + 12
      local payload_end = offset + length - 1

      if ctype == CONTAINER_DATA and code == NIKON_GET_LIVE_VIEW_IMAGE then
        local jpeg_start = payload_start + 384
        if jpeg_start + 3 <= payload_end
          and packet:byte(jpeg_start) == 0xFF
          and packet:byte(jpeg_start + 1) == 0xD8
          and packet:byte(payload_end - 1) == 0xFF
          and packet:byte(payload_end) == 0xD9 then
          frame = packet:sub(jpeg_start, payload_end)
        else
          local payload = packet:sub(payload_start, payload_end)
          local extracted, extract_err = extract_jpeg_blob(payload:sub(385))
          if extracted then
            frame = extracted
          else
            -- Nikon can send an empty DATA container followed by the actual
            -- response code while Live View is still changing state. Keep
            -- parsing so NotLiveView is not masked as a JPEG parse error.
            debug_log("live-view data pending: " .. tostring(extract_err or "unknown"))
          end
        end
      elseif ctype == CONTAINER_RESPONSE then
        response_code = code
      end
      offset = offset + length
    end
  end

  local done_us = now_us()
  self.last_live_transport_metrics = {
    commandWriteUs = request_written_us - request_started_us,
    firstPacketUs = first_packet_us > 0 and (first_packet_us - request_started_us) or 0,
    socketReadUs = first_packet_us > 0 and (first_packet_us - request_written_us) or 0,
    parseUs = parse_started_us > 0 and (done_us - parse_started_us) or 0,
    wireTotalUs = done_us - request_started_us,
    waitHookUs = wait_hook_us,
    transportPackets = packets_read,
  }
  if response_code == RESP_SESSION_NOT_OPEN then
    fail("transport_error", "ddserver session lost around live-view request")
  end
  return frame, response_code or RESP_OK
end

function DdServerWire:read_welcome()
  local body = self:read_prefixed_packet()
  if not body or #body < 4 then
    fail("transport_error", "ddserver welcome packet missing")
  end
  local major = u16(body, 1)
  local minor = u16(body, 3)
  local name = trim((body:sub(5):gsub("%z+$", "")))
  debug_log(string.format("ddserver welcome %d.%d %s", major or 0, minor or 0, name or ""))
  return {
    major = major,
    minor = minor,
    name = name,
  }
end

function DdServerWire:read_exact(length)
  if not self.sock then
    fail("camera_missing", "ddserver socket is not connected")
  end
  if TRACE_TRANSPORT then
    debug_log(string.format("read_exact %d", length))
  end
  local data, err = self.sock:readfull(length, self.timeout)
  if not data then
    local detail = error_text(err)
    debug_log(string.format("read_exact failed: %s", detail))
    fail("transport_error", detail ~= "unknown" and detail or "ddserver closed the connection")
  end
  if TRACE_TRANSPORT then
    debug_log(string.format("read_exact got %d", #data))
  end
  return data
end

function DdServerWire:read_prefixed_block()
  return self:read_prefixed_packet()
end

function DdServerWire:read_prefixed_packet()
  local prefix = self:read_exact(4)
  local length = u32(prefix, 1)
  if length < 4 or length > MAX_TRANSPORT_PACKET_BYTES then
    fail("transport_error", string.format("invalid packet length %d", length))
  end
  return self:read_exact(length - 4)
end

function DdServerWire:read_container()
  while #self.rx_buffer < 4 do
    self.rx_buffer = self.rx_buffer .. self:read_prefixed_packet()
  end
  local length = u32(self.rx_buffer, 1)
  debug_log(string.format("read_container length=%d", length))
  if length < 12 then
    fail("transport_error", string.format("container length too short %d", length))
  end
  while #self.rx_buffer < length do
    self.rx_buffer = self.rx_buffer .. self:read_prefixed_packet()
  end
  local body = self.rx_buffer:sub(1, length)
  self.rx_buffer = self.rx_buffer:sub(length + 1)
  local container = parse_container_blob(body)
  if not container then
    fail("transport_error", "invalid ddserver container")
  end
  debug_log(string.format("read_container type=%d code=0x%04x txid=%d body=%d rest=%d", container.ctype, container.code, container.txid, container.length, #self.rx_buffer))
  return container.ctype, container.code, container.txid, container.payload
end

function DdServerWire:write_container(ctype, code, payload, transaction_id)
  if not self.sock then
    fail("camera_missing", "ddserver socket is not connected")
  end
  local body = pack_container(ctype, code, payload, transaction_id)
  debug_log(string.format("write_container type=%d code=0x%04x bytes=%d", ctype, code, #body))
  local written, err = self.sock:write(body)
  if not written then
    local detail = error_text(err)
    debug_log(string.format("write_container failed: %s", detail))
    fail("transport_error", detail ~= "unknown" and detail or "ddserver write failed")
  end
end

function DdServerWire:read_response_blocks(expected_responses)
  expected_responses = math.max(1, tonumber(expected_responses) or 1)
  local blocks = {}
  local responses = 0
  while responses < expected_responses do
    local ctype, code, txid, payload = self:read_container()
    if ctype ~= 0x0004 then
      blocks[#blocks + 1] = {
        ctype = ctype,
        code = code,
        txid = txid,
        payload = payload,
      }
      if ctype == CONTAINER_RESPONSE then
        responses = responses + 1
      end
    end
  end
  if #self.rx_buffer > 0 and #self.rx_buffer < 4 then
    debug_log(string.format("discarding trailing ddserver bytes: %d", #self.rx_buffer))
    self.rx_buffer = ""
  end
  return blocks
end

function DdServerWire:open_active_device_session()
  if not self.active_device then
    fail("camera_missing", "no active device for session open")
  end
  self:write_container(CONTAINER_COMMAND, CMD_CONNECT_DEVICE, le_u32(self.active_device.vendor_id) .. le_u32(self.active_device.product_id))
  local connect_code = nil
  local connect_blocks = self:read_response_blocks(1)
  for _, block in ipairs(connect_blocks) do
    if block.ctype == CONTAINER_RESPONSE then connect_code = block.code end
  end
  if connect_code ~= RESP_OK and connect_code ~= RESP_GENERAL_ERROR then
    fail("camera_missing", string.format("ddserver rejected device connect 0x%04x", connect_code or 0))
  end
  sleep_ms(150)
  self:write_container(CONTAINER_COMMAND, CMD_OPEN_SESSION, le_u32(self.session_id))
  local session_code = nil
  local session_blocks = self:read_response_blocks(1)
  for _, block in ipairs(session_blocks) do
    if block.ctype == CONTAINER_RESPONSE then session_code = block.code end
  end
  if session_code ~= RESP_OK and session_code ~= RESP_SESSION_ALREADY_OPEN then
    fail("camera_missing", string.format("ddserver rejected open session 0x%04x", session_code or 0))
  end
  self.session_open = true
  self.transport_ready = true
  self.hardware_detected = true
  return true
end

function DdServerWire:rehydrate_session()
  if not self.active_device then
    fail("camera_missing", "no remembered device for ddserver rehydrate")
  end
  debug_log(string.format("rehydrate session backend for %04x:%04x", self.active_device.vendor_id, self.active_device.product_id))
  self:connect()
  self:open_active_device_session()
end

function DdServerWire:read_device_list()
  local ok_blocks, blocks_or_err = pcall(function()
    self:write_container(CONTAINER_COMMAND, CMD_GET_DEVICES)
    return self:read_response_blocks(1)
  end)
  if not ok_blocks then
    return {}
  end
  local blocks = blocks_or_err
  local payload, response_code = nil, RESP_OK
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      payload = block.payload
    elseif block.ctype == CONTAINER_RESPONSE then
      response_code = block.code
    end
  end
  if response_code ~= RESP_OK or not payload or #payload < 2 then
    return {}
  end
  local count = u16(payload, 1)
  local offset = 3
  local devices = {}
  for _ = 1, count do
    if offset + 3 > #payload then
      break
    end
    local vendor_id = u16(payload, offset)
    local product_id = u16(payload, offset + 2)
    offset = offset + 4
    local vendor_name
    vendor_name, offset = read_cstring(payload, offset)
    local product_name
    product_name, offset = read_cstring(payload, offset)
    devices[#devices + 1] = {
      vendor_id = vendor_id,
      product_id = product_id,
      vendor_name = vendor_name,
      product_name = product_name,
    }
  end
  return devices
end

function DdServerWire:connect_device(device)
  local previous = self.active_device
  self.active_device = device
  local connect_ok, connect_err = pcall(function()
    return self:open_active_device_session()
  end)
  if not connect_ok then
    self.active_device = previous
    fail("camera_missing", error_text(connect_err or "device connect failed"))
  end
  return true
end

function DdServerWire:device_ready()
  local _, response_code = self:execute(NIKON_DEVICE_READY)
  return response_code
end

function DdServerWire:wait_device_ready(timeout_ms, poll_ms)
  local deadline = now_ms() + (tonumber(timeout_ms) or 4000)
  repeat
    local response_code = self:device_ready()
    if response_code == RESP_OK then return response_code end
    if response_code == NIKON_OUT_OF_FOCUS then
      fail("focus_failed", "camera could not acquire focus")
    end
    if response_code ~= RESP_DEVICE_BUSY then
      fail("camera_error", string.format("camera ready failed 0x%04x", response_code or 0))
    end
    sleep_ms(tonumber(poll_ms) or 10)
  until now_ms() >= deadline
  fail("camera_busy", "camera remained busy")
end

function DdServerWire:get_device_prop_value(prop_code)
  local payload, response_code = self:execute(CMD_GET_DEVICE_PROP_VALUE, { prop_code })
  if response_code ~= RESP_OK then
    return nil
  end
  return payload
end

function DdServerWire:get_device_prop_desc(prop_code)
  local payload, response_code = self:execute(CMD_GET_DEVICE_PROP_DESC, { prop_code })
  if response_code ~= RESP_OK then
    return nil
  end
  return payload
end

function DdServerWire:get_events()
  local payload, response_code = self:execute(CAPTURE_EVENT.GET)
  if response_code == RESP_DEVICE_BUSY then
    return {}, response_code
  end
  if response_code ~= RESP_OK or type(payload) ~= "string" or #payload < 2 then
    return {}, response_code
  end
  local events = {}
  local count = math.min(u16(payload, 1), math.floor((#payload - 2) / 6))
  for index = 0, count - 1 do
    local offset = 3 + index * 6
    events[#events + 1] = {
      code = u16(payload, offset),
      parameter = u32(payload, offset + 2),
    }
  end
  return events, response_code
end

function DdServerWire:get_battery_percent()
  if self.legacy_transport_only then
    local probe = self:probe_camera_state()
    return probe.batteryPercent
  end
  local payload = self:get_device_prop_value(PROP_BATTERY_LEVEL)
  if payload ~= nil and #payload > 0 then
    return payload:byte(1)
  end
  return nil
end

function DdServerWire:get_battery_percent_gphoto()
  return nil
end

-- Module: liveview (bridge contract 1-7).
-- Legacy entry points remain here for fallback compatibility only.
function DdServerWire:start_live_view_legacy()
  local output = self:run_transport_action("live-start")
  if json_bool_field(output, "ok") == false then
    fail(json_field(output, "status") or "transport_error", json_field(output, "message") or "live-start failed")
  end
  self.transport_ready = true
  self.live_view_active = true
end

function DdServerWire:stop_live_view_legacy()
  local output = self:run_transport_action("live-stop")
  if json_bool_field(output, "ok") == false then
    fail(json_field(output, "status") or "transport_error", json_field(output, "message") or "live-stop failed")
  end
  self.live_view_active = false
end

function DdServerWire:af_drive_legacy()
  local output = self:run_transport_action("af")
  if json_bool_field(output, "ok") == false then
    fail(json_field(output, "status") or "transport_error", json_field(output, "message") or "af failed")
  end
  local response_code = json_number_field(output, "responseCode")
  if response_code ~= RESP_OK then
    fail("transport_error", string.format("af response missing or failed 0x%04x", response_code or 0))
  end
  return response_code
end

function DdServerWire:shutter_legacy()
  local output = self:run_transport_action("shutter")
  if json_bool_field(output, "ok") == false then
    fail(json_field(output, "status") or "transport_error", json_field(output, "message") or "shutter failed")
  end
end

function DdServerWire:live_view_enabled_legacy()
  local probe = self:probe_camera_state()
  return probe.liveView == true
end

function DdServerWire:live_view_frame_legacy()
  local output = self:run_transport_action("frame")
  local handle = io.open(FRAME_PATH, "rb")
  if handle then
    local blob = handle:read("*a")
    handle:close()
    local extracted = is_jpeg_blob(blob) and blob or select(1, extract_jpeg_blob(blob))
    if extracted and #extracted > 0 then
      self.live_view_active = true
      return extracted
    end
  end
  if json_field(output, "status") == "not_live_view" then
    fail("not_live_view", "camera is not in live view")
  end
  fail("capture_failed", "live view frame unavailable")
end

function DdServerWire:use_legacy_live_view_start(reason)
  debug_log("live-start fallback to legacy transport: " .. tostring(reason or "unknown"))
  self:close()
  self:start_live_view_legacy()
  self:clear_probe_cache()
  sleep_ms(220)
  local ok_rehydrate, rehydrate_err = pcall(function()
    self:rehydrate_session()
  end)
  if not ok_rehydrate then
    debug_log("live-start fallback rehydrate skipped: " .. tostring(type(rehydrate_err) == "table" and (rehydrate_err.message or rehydrate_err.status) or rehydrate_err))
  end
  self.transport_ready = true
  self.live_view_active = true
end

function DdServerWire:use_legacy_live_view_frame(reason)
  debug_log("live-frame fallback to legacy transport: " .. tostring(reason or "unknown"))
  local ok_frame, frame_or_err = pcall(function()
    return self:live_view_frame_legacy()
  end)
  if not ok_frame then
    error(frame_or_err, 0)
  end
  self.transport_ready = true
  self.live_view_active = true
  return frame_or_err
end

-- Legacy direct-ddserver parsing path is kept below for non-core transport work.
function DdServerWire:read_device_list_legacy()
  local response = self:run_batch(pack_container(CONTAINER_COMMAND, CMD_GET_DEVICES))
  local blocks = parse_stream_blob(response)
  local payload, response_code = nil, RESP_OK
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      payload = block.payload
    elseif block.ctype == CONTAINER_RESPONSE then
      response_code = block.code
    end
  end
  if not payload then
    fail("camera_missing", string.format("ddserver returned response 0x%04x without device data", response_code or 0))
  end
  if #payload < 2 then
    fail("transport_error", "device list payload too short")
  end
  local count = u16(payload, 1)
  local offset = 3
  local devices = {}
  for _ = 1, count do
    if offset + 3 > #payload then
      break
    end
    local vendor_id = u16(payload, offset)
    local product_id = u16(payload, offset + 2)
    offset = offset + 4
    local vendor_name
    vendor_name, offset = read_cstring(payload, offset)
    local product_name
    product_name, offset = read_cstring(payload, offset)
    table.insert(devices, {
      vendor_id = vendor_id,
      product_id = product_id,
      vendor_name = vendor_name,
      product_name = product_name,
    })
  end
  return devices
end

function DdServerWire:connect_device_legacy(device)
  local previous = self.active_device
  self.active_device = device
  local blocks = self:request_blocks({})
  local connect_code = nil
  local session_code = nil
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_RESPONSE then
      if not connect_code then
        connect_code = block.code
      else
        session_code = block.code
      end
    end
  end
  if connect_code ~= RESP_OK and connect_code ~= RESP_GENERAL_ERROR then
    self.active_device = previous
    fail("camera_missing", string.format("ddserver rejected device connect 0x%04x", connect_code or 0))
  end
  if session_code ~= RESP_OK and session_code ~= RESP_SESSION_ALREADY_OPEN then
    self.active_device = previous
    fail("camera_missing", string.format("ddserver rejected open session 0x%04x", session_code or 0))
  end
  self.session_open = true
end

function DdServerWire:set_device_prop_value(prop_code, payload)
  local _, response_code = self:execute(CMD_SET_DEVICE_PROP_VALUE, { prop_code }, payload or "")
  if response_code ~= RESP_OK then
    if response_code == RESP_DEVICE_BUSY then
      fail("camera_busy", string.format("camera busy while setting prop 0x%04x", prop_code or 0))
    end
    if response_code == RESP_SESSION_NOT_OPEN then
      fail("transport_error", string.format("camera session lost while setting prop 0x%04x", prop_code or 0))
    end
    fail("camera_error", string.format("ddserver rejected set prop 0x%04x with 0x%04x", prop_code or 0, response_code or 0))
  end
end

-- Diagnostic only: release or acquire Nikon's remote control mode without
-- changing exposure settings. This lets us test whether camera-body controls
-- are suppressed while the remote live-view session is active.
function DdServerWire:set_control_mode(value)
  value = tonumber(value)
  if value ~= 0 and value ~= 1 then
    fail("invalid_control_mode", "expected 0 or 1")
  end
  local _, response_code = self:execute(NIKON_CHANGE_CAMERA_MODE, { value })
  if response_code ~= RESP_OK then
    if response_code == RESP_DEVICE_BUSY then
      fail("camera_busy", string.format("camera busy while setting control mode %d", value))
    end
    fail("camera_error", string.format("control mode failed 0x%04x", response_code or 0))
  end
  return response_code
end

function DdServerWire:get_storage_ids()
  local payload, response_code = self:execute(CMD_GET_STORAGE_IDS)
  if response_code ~= RESP_OK then
    fail("camera_missing", string.format("ddserver rejected get storage ids 0x%04x", response_code or 0))
  end
  return parse_u32_array(payload)
end

function DdServerWire:get_storage_info(storage_id)
  local payload, response_code = self:execute(CMD_GET_STORAGE_INFO, { storage_id })
  if response_code ~= RESP_OK or not payload or #payload < 26 then
    fail("camera_missing", string.format("ddserver rejected get storage info 0x%04x", response_code or 0))
  end
  return {
    storageId = storage_id,
    storageType = u16(payload, 1),
    filesystemType = u16(payload, 3),
    accessCapability = u16(payload, 5),
    maxCapacity = u64(payload, 7),
    freeSpaceBytes = u64(payload, 15),
    freeSpaceImages = u32(payload, 23),
  }
end

function DdServerWire:get_object_handles(storage_id, format_code, parent_handle)
  local payload, response_code = self:execute(CMD_GET_OBJECT_HANDLES, {
    storage_id or PTP_ALL_STORAGES,
    format_code or PTP_ALL_OBJECT_FORMATS,
    parent_handle or PTP_ROOT_PARENT,
  })
  if response_code ~= RESP_OK then
    fail("camera_missing", string.format("ddserver rejected get object handles 0x%04x", response_code or 0))
  end
  local handles = parse_u32_array(payload)
  debug_log(string.format(
    "object handles storage=%d format=0x%04x parent=%d payloadBytes=%d declared=%d parsed=%d",
    tonumber(storage_id) or PTP_ALL_STORAGES,
    tonumber(format_code) or PTP_ALL_OBJECT_FORMATS,
    tonumber(parent_handle) or PTP_ROOT_PARENT,
    type(payload) == "string" and #payload or 0,
    type(payload) == "string" and u32(payload, 1) or 0,
    #handles
  ))
  return handles
end

function DdServerWire:get_object_info(handle)
  local payload, response_code = self:execute(CMD_GET_OBJECT_INFO, { handle })
  if response_code ~= RESP_OK then
    fail("camera_missing", string.format("ddserver rejected get object info 0x%04x for handle %d", response_code or 0, tonumber(handle) or 0))
  end
  local filename = read_ptp_string(payload, 53)
  return {
    handle = tonumber(handle) or 0,
    storageId = u32(payload, 1),
    formatCode = u16(payload, 5),
    compressedSize = u32(payload, 9),
    thumbFormatCode = u16(payload, 13),
    thumbCompressedSize = u32(payload, 15),
    thumbWidth = u32(payload, 19),
    thumbHeight = u32(payload, 23),
    parentObject = u32(payload, 39),
    filename = filename or "",
  }
end

function DdServerWire:get_object(handle)
  local payload, response_code = self:execute(CMD_GET_OBJECT, { handle })
  if response_code ~= RESP_OK then
    fail("camera_missing", string.format("ddserver rejected get object 0x%04x for handle %d", response_code or 0, tonumber(handle) or 0))
  end
  return payload or ""
end

function DdServerWire:get_partial_object(handle, offset, max_bytes)
  local payload, response_code = self:execute(CMD_GET_PARTIAL_OBJECT, {
    handle,
    offset or 0,
    max_bytes or CAPTURED_OBJECT_CHUNK_SIZE,
  })
  if response_code ~= RESP_OK then
    fail("capture_failed", string.format(
      "ddserver rejected partial object 0x%04x for handle %d offset %d",
      response_code or 0,
      tonumber(handle) or 0,
      tonumber(offset) or 0
    ))
  end
  return payload or ""
end

function DdServerWire:get_thumb(handle)
  local payload, response_code = self:execute(CMD_GET_THUMB, { handle })
  if response_code ~= RESP_OK then
    fail("camera_missing", string.format("ddserver rejected get thumb 0x%04x for handle %d", response_code or 0, tonumber(handle) or 0))
  end
  return payload or ""
end

function DdServerWire:refresh_live_view_zoom_ratio()
  -- D810 live view becomes unstable if we immediately mirror D1A3 back with 0x1016.
  -- Read the property once for observability, but do not write it during live-view entry.
  local payload = self:get_device_prop_value(0xD1A3)
  if type(payload) ~= "string" or #payload == 0 then
    debug_log("live view zoom ratio not available; skipping refresh")
    return false
  end
  debug_log(string.format("live view zoom ratio available (%d bytes); skipping write-back", #payload))
  return true
end

function DdServerWire:set_capture_in_sdram(enabled)
  local payload = enabled and string.char(1) or string.char(0)
  local ok, err = pcall(function()
    self:set_device_prop_value(PROP_RECORDING_MEDIA, payload)
  end)
  if not ok then
    debug_log(string.format("capture in sdram update failed: %s", tostring(err)))
    return false
  end
  return true
end

function DdServerWire:prime_live_view_state()
  local function soft(label, fn)
    local ok, err = pcall(fn)
    if not ok then
      debug_log(string.format("%s failed: %s", label, tostring(err)))
    end
  end
  soft("device_ready", function()
    self:device_ready()
  end)
  -- libgphoto prepares Nikon live view by selecting SDRAM recording first.
  -- Keep an explicit opt-out for diagnostics, but make the stable path the
  -- default so StartLiveView is not rejected with Nikon InvalidStatus (A004).
  if os.getenv("D810D_ENABLE_CAPTURE_IN_SDRAM") ~= "0" then
    soft("capture_in_sdram", function()
      self:set_capture_in_sdram(true)
    end)
  end
  soft("live_view_selector", function()
    self:get_device_prop_value(PROP_LIVE_VIEW_SELECTOR)
  end)
  soft("live_view_status", function()
    self:get_device_prop_value(PROP_LIVE_VIEW_STATUS)
  end)
  soft("live_view_zoom_ratio", function()
    self:get_device_prop_value(0xD1A3)
  end)
end

function DdServerWire:start_live_view()
  if self.legacy_transport_only or not self.session_open then
    return self:start_live_view_legacy()
  end
  local start_response = nil
  local ok, err = pcall(function()
    self:prime_live_view_state()
    local current = self:get_device_prop_value(PROP_LIVE_VIEW_STATUS)
    if current ~= nil and #current > 0 and current:byte(1) == 1 then
      start_response = RESP_OK
      return
    end
    for attempt = 1, LIVE_VIEW_START_RETRY_COUNT do
      local ready_response = self:device_ready()
      if ready_response == RESP_OK then
        local _, response_code = self:execute(NIKON_START_LIVE_VIEW)
        start_response = response_code
        if response_code == RESP_OK then
          return
        end
        if response_code == RESP_DEVICE_BUSY then
          -- Nikon documents DeviceBusy here as an asynchronous start: do not
          -- resend StartLiveView while the first transition is still running.
          local settle_deadline = now_ms() + LIVE_VIEW_BUSY_SETTLE_MS
          repeat
            local settle_response = self:device_ready()
            if settle_response == RESP_OK then
              start_response = RESP_OK
              return
            end
            if settle_response ~= RESP_DEVICE_BUSY then
              fail("liveview_start_failed", string.format("camera live start settle response 0x%04x", settle_response or 0))
            end
            sleep_ms(20)
          until now_ms() >= settle_deadline
          fail("camera_busy", "camera live start did not settle")
        elseif response_code == 0xA004 then
          debug_log("live start returned Nikon InvalidStatus; re-priming SDRAM state")
          self:set_capture_in_sdram(true)
        else
          fail("liveview_start_failed", string.format("camera live start response 0x%04x", response_code or 0))
        end
      elseif ready_response ~= RESP_DEVICE_BUSY then
        fail("liveview_start_failed", string.format("camera ready response 0x%04x", ready_response or 0))
      end
      sleep_ms(LIVE_VIEW_START_RETRY_MS)
    end
    fail("liveview_start_failed", string.format("camera remained busy after live start retries 0x%04x", start_response or 0))
  end)
  if not ok then
    error(err or "transport_error", 0)
  end
  self.live_view_active = true
  self:refresh_live_view_zoom_ratio()
  if LIVE_VIEW_WARMUP_MS > 0 then
    sleep_ms(LIVE_VIEW_WARMUP_MS)
  end
end

function DdServerWire:stop_live_view()
  if self.legacy_transport_only or not self.session_open then
    return self:stop_live_view_legacy()
  end
  local response_code = nil
  for attempt = 1, 10 do
    local ready_response = self:device_ready()
    if ready_response == RESP_OK then
      local _, end_response = self:execute(NIKON_END_LIVE_VIEW)
      response_code = end_response
      if end_response == RESP_OK then
        self:device_ready()
        self.transport_ready = true
        self.live_view_active = false
        return
      end
      if end_response ~= RESP_DEVICE_BUSY then
        fail("transport_error", string.format("live-stop failed 0x%04x", end_response or 0))
      end
    elseif ready_response ~= RESP_DEVICE_BUSY then
      fail("transport_error", string.format("camera ready before live-stop failed 0x%04x", ready_response or 0))
    else
      response_code = ready_response
    end
    sleep_ms(120)
  end
  fail("camera_busy", string.format("live-stop remained busy after retries 0x%04x", response_code or 0))
end

-- KILL is an out-of-band recovery primitive.  After the old PTP socket is
-- discarded, send EndLiveView directly on the newly opened session without
-- waiting for DeviceReady; DeviceReady may itself report 0x2019 while the
-- camera is holding a stale Live View transaction.
function DdServerWire:force_end_live_view()
  if self.legacy_transport_only or not self.session_open then
    return false, "ptp session is not open"
  end
  local last_response = nil
  for attempt = 1, 3 do
    local ok, response_code = pcall(function()
      local _, code = self:execute(NIKON_END_LIVE_VIEW)
      return code
    end)
    if ok then
      last_response = response_code
      if response_code == RESP_OK then
        self.live_view_active = false
        pcall(function() self:device_ready() end)
        return true, response_code
      end
    else
      last_response = response_code
    end
    debug_log(string.format("kill EndLiveView attempt=%d response=%s", attempt, tostring(last_response)))
    sleep_ms(120)
  end
  return false, last_response
end

function DdServerWire:af_drive()
  if self.legacy_transport_only or not self.session_open then
    return self:af_drive_legacy()
  end
  self:ensure_transport_ready(false)
  self:device_ready()
  self.last_af_success_at = 0
  local _, response_code = self:execute(NIKON_AF_DRIVE)
  if response_code ~= RESP_OK then
    fail("transport_error", string.format("af failed 0x%04x", response_code or 0))
  end
  -- Nikon can acknowledge AF before its internal focus operation has released
  -- DeviceBusy. Do not let a following shutter command race that interval.
  for _ = 1, 160 do
    local ready_response = self:device_ready()
    if ready_response == RESP_OK then
      self.last_af_success_at = now_ms()
      return response_code
    end
    if ready_response == NIKON_OUT_OF_FOCUS then
      fail("focus_failed", "camera could not acquire focus")
    end
    if ready_response ~= RESP_DEVICE_BUSY then
      fail("camera_error", string.format("camera ready after AF failed 0x%04x", ready_response or 0))
    end
    sleep_ms(25)
  end
  fail("camera_busy", "camera remained busy after AF")
  return response_code
end

function DdServerWire:af_drive_start()
  if self.legacy_transport_only or not self.session_open then
    return self:af_drive_legacy()
  end
  self:ensure_transport_ready(false)
  self:wait_device_ready(2000, 10)
  self.last_af_success_at = 0
  self.af_started_at = 0
  local _, response_code = self:execute(NIKON_AF_DRIVE)
  if response_code ~= RESP_OK then
    fail("transport_error", string.format("af start failed 0x%04x", response_code or 0))
  end
  self.af_started_at = now_ms()
  return response_code
end

function DdServerWire:shutter(focus_latched, burst_fast)
  if self.legacy_transport_only or not self.session_open then
    return self:shutter_legacy()
  end
  self:ensure_transport_ready(false)
  self:wait_device_ready(4000, 5)
  if (tonumber(self.af_started_at) or 0) > 0 then
    self.last_af_success_at = now_ms()
    self.af_started_at = 0
  end

  -- 0x9207 does not perform autofocus. Couple AF-S/AF-C/AF-A capture to
  -- the shutter command, while leaving hard/soft manual focus untouched.
  local focus_already_latched = focus_latched == true
    and (tonumber(self.last_af_success_at) or 0) > 0
  local af_mode = 0
  if not focus_already_latched then
    local af_mode_payload = self:get_device_prop_value(PROP_AF_MODE_SELECT)
    af_mode = af_mode_payload and #af_mode_payload >= 2 and u16(af_mode_payload, 1) or 0
  end
  if not focus_already_latched and af_mode ~= 3 and af_mode ~= 4 then
    -- The slider starts AF before it reaches the shutter detent. Reuse that
    -- fresh result instead of focusing a second time at the release point.
    local focus_age = now_ms() - (tonumber(self.last_af_success_at) or 0)
    local can_reuse_focus = focus_age >= 0
      and ((focus_latched == true and self.last_af_success_at > 0) or focus_age <= 5000)
    if not can_reuse_focus then
      self:af_drive()
    else
      debug_log(string.format(
        "shutter reusing focused state ageMs=%.0f latched=%s",
        focus_age,
        tostring(focus_latched == true)
      ))
    end
  end

  -- The camera may still be in Live View after a failed frame/recovery path
  -- even when the bridge's cached flag was cleared. Reconcile the physical
  -- state before choosing the non-Live-View camera-mode release sequence.
  if not self.live_view_active then
    local status_ok, camera_live = pcall(function()
      return self:live_view_enabled()
    end)
    if status_ok and camera_live then
      debug_log("shutter reconciled stale live-view state from camera")
    end
  end

  if self.live_view_active then
    if burst_fast == true then
      local _, response_code = self:execute(NIKON_SHUTTER, { 0xFFFFFFFF, 0x0000 })
      if response_code == RESP_OK then
        return response_code
      end
      if response_code == RESP_DEVICE_BUSY then
        -- As with StartLiveView, Nikon may return DeviceBusy after accepting
        -- the release. Wait for completion; retransmission can create an
        -- extra photograph.
        self:wait_device_ready(5000, 20)
        debug_log("burst shutter accepted asynchronously")
        return RESP_OK
      end
      fail("transport_error", string.format("burst shutter failed 0x%04x", response_code or 0))
    end
    self:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(0))
    self:wait_device_ready(3000, 10)

    local capture_ok, capture_result, response_code = pcall(function()
      return self:execute(NIKON_SHUTTER, { 0xFFFFFFFF, 0x0000 })
    end)

    if capture_ok and response_code == RESP_OK then
      for _ = 1, 40 do
        local ready_response = self:device_ready()
        if ready_response == RESP_OK then
          break
        end
        if ready_response ~= RESP_DEVICE_BUSY then
          debug_log(string.format("camera ready after live-view shutter failed 0x%04x", ready_response or 0))
          break
        end
        sleep_ms(150)
      end
    end

    local restored, restore_err = pcall(function()
      self:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(1))
    end)
    if not restored then
      debug_log(string.format("failed to restore live-view recording media: %s", tostring(restore_err)))
    end
    if not capture_ok then
      if type(capture_result) == "table" then
        error(capture_result, 0)
      end
      fail("transport_error", tostring(capture_result or "live-view shutter transport failed"))
    end
    if response_code ~= RESP_OK then
      fail("transport_error", string.format("live-view shutter failed 0x%04x", response_code or 0))
    end
    return response_code
  end

  local _, mode_response = self:execute(NIKON_CHANGE_CAMERA_MODE, { 1 })
  if mode_response ~= RESP_OK then
    fail("transport_error", string.format("camera control mode failed 0x%04x", mode_response or 0))
  end
  self:device_ready()
  local response_code
  _, response_code = self:execute(NIKON_SHUTTER, { 0xFFFFFFFF, 0x0000 })
  if response_code ~= RESP_OK then
    fail("transport_error", string.format("shutter failed 0x%04x", response_code or 0))
  end
  self:release_camera_control()
end

function DdServerWire:release_camera_control()
  local last_response = nil
  for _ = 1, 40 do
    local ready_response = self:device_ready()
    if ready_response == RESP_OK then
      local _, mode_response = self:execute(NIKON_CHANGE_CAMERA_MODE, { 0 })
      last_response = mode_response
      if mode_response == RESP_OK then
        return true
      end
      -- D810 commonly answers InvalidStatus after a successful program
      -- shutter because it has already left PC control mode. The photograph
      -- and ObjectAdded event are valid, so this is an idempotent release.
      if mode_response == NIKON_INVALID_STATUS then
        debug_log("camera control already released after shutter 0xa003")
        return true
      end
      if mode_response ~= RESP_DEVICE_BUSY then
        fail("transport_error", string.format("camera control release failed 0x%04x", mode_response or 0))
      end
    elseif ready_response == NIKON_OUT_OF_FOCUS then
      fail("focus_failed", "camera refused capture because focus was not acquired")
    elseif ready_response ~= RESP_DEVICE_BUSY then
      fail("transport_error", string.format("camera ready before control release failed 0x%04x", ready_response or 0))
    else
      last_response = ready_response
    end
    sleep_ms(150)
  end
  fail("camera_busy", string.format("camera control release remained busy 0x%04x", last_response or 0))
end

function DdServerWire:live_view_enabled()
  if self.legacy_transport_only or not self.session_open then
    return self:live_view_enabled_legacy()
  end
  local payload = self:get_device_prop_value(PROP_LIVE_VIEW_STATUS)
  self.transport_ready = true
  self.live_view_active = payload ~= nil and #payload > 0 and payload:byte(1) == 1
  return self.live_view_active
end

function DdServerWire:live_view_frame(wait_hook)
  if self.legacy_transport_only or not self.session_open then
    return self:live_view_frame_legacy()
  end
  local payload, response_code
  local ok, err = pcall(function()
    if FAST_LIVE_VIEW_9203 then
      payload, response_code = self:execute_live_view_image(wait_hook)
    else
      payload, response_code = self:execute(NIKON_GET_LIVE_VIEW_IMAGE)
      self.last_live_transport_metrics = nil
    end
  end)
  if not ok then
    -- Preserve structured transport errors so the session layer can
    -- distinguish a dead ddserver socket from a malformed camera frame.
    if type(err) == "table" then
      error(err, 0)
    end
    fail("transport_error", tostring(err or "ddserver live-view transport failed"))
  end
  if response_code == MTP_NOT_LIVE_VIEW then
    self.live_view_active = false
    fail("not_live_view", "camera is not in live view")
  end
  if not payload or #payload == 0 then
    fail("capture_failed", "live view payload was empty")
  end
  if FAST_LIVE_VIEW_9203 and is_jpeg_blob(payload) then
    self.live_view_active = true
    return payload
  end
  local extracted, extract_err = extract_jpeg_blob(payload:sub(385))
  if extracted then
    self.live_view_active = true
    return extracted
  end
  extracted, extract_err = extract_jpeg_blob(payload)
  if extracted then
    self.live_view_active = true
    return extracted
  end
  fail("capture_failed", "unable to extract jpeg from live view payload: " .. tostring(extract_err or "unknown"))
end

-- Module: session, status, recovery, and actions (bridge contract 2).
local BridgeSession = {}
BridgeSession.__index = BridgeSession
LIVE_PERF_WINDOW = 4096

function perf_ring_push(session, key, value)
  value = tonumber(value)
  if not value or value < 0 then return end
  local ring = session[key]
  if type(ring) ~= "table" then
    ring = { values = {}, next = 1, count = 0, sum = 0 }
    session[key] = ring
  end
  local old = ring.values[ring.next]
  if old then
    ring.sum = ring.sum - old
  else
    ring.count = ring.count + 1
  end
  ring.values[ring.next] = value
  ring.sum = ring.sum + value
  ring.next = ring.next % LIVE_PERF_WINDOW + 1
end

function perf_ring_summary(ring)
  if type(ring) ~= "table" or (tonumber(ring.count) or 0) <= 0 then
    return nil
  end
  local sorted = {}
  for i = 1, ring.count do
    sorted[i] = ring.values[i]
  end
  table.sort(sorted)
  local function percentile(ratio)
    local index = math.max(1, math.min(#sorted, math.ceil(#sorted * ratio)))
    return sorted[index]
  end
  return {
    count = ring.count,
    avg = ring.sum / ring.count,
    p50 = percentile(0.50),
    p95 = percentile(0.95),
    max = sorted[#sorted],
  }
end

function BridgeSession.new(host, port, frame_path)
  local started_at = now_ms()
  local self = setmetatable({
    host = host,
    port = port,
    frame_path = frame_path,
    wire = nil,
    device = nil,
    live_view_active = false,
    last_status = "idle",
    last_error = "",
    last_frame = nil,
    last_frame_b64 = nil,
    last_captured_preview = nil,
    last_captured_preview_b64 = nil,
    last_captured_preview_meta = nil,
    last_captured_object_handle = 0,
    last_captured_object_info = nil,
    last_captured_object_blob = nil,
    last_captured_object_meta = nil,
    last_captured_object_file_handle = 0,
    shutter_priority = false,
    last_capture_event_seq = 0,
    last_capture_event_at = 0,
    last_capture_event_code = 0,
    last_capture_event_handle = 0,
    last_camera_event_code = 0,
    last_camera_event_parameter = 0,
    last_power = nil,
    last_metrics = nil,
    last_device = nil,
    last_status_at = 0,
    last_battery_at = 0,
    last_frame_at = 0,
    last_frame_cache_at = 0,
    last_frame_last_good_at = 0,
    last_command_at = 0,
    frame_failures = 0,
    frame_seq = 0,
    reconnect_count = 0,
    session_id = current_session_id(),
    session_label = current_session_label(),
    live_session_id = nil,
    live_session_label = "",
    backend_started_at = started_at,
    backend_state = "idle",
    readiness_state = "detecting",
    readiness_reason = "backend_starting",
    readiness_started_at = started_at,
    readiness_transition_at = started_at,
    ready_since_at = 0,
    readiness_last_ms = 0,
    readiness_sample_count = 0,
    readiness_total_ms = 0,
    readiness_max_ms = 0,
    live_view_faulted = false,
    live_view_fault_reason = "",
    live_view_limited = false,
    live_view_limit_reason = "",
    capability_certified = false,
    capability_certified_at = 0,
    capability_certification_reason = "capability_certification_required",
    device_ready_verified = false,
    properties_ready = false,
    storage_ready = false,
    command_route_ready = false,
    live_view_path_ready = false,
    capture_route_ready = false,
    file_route_ready = false,
    last_recover_at = 0,
    last_recover_reason = "",
    last_connect_at = 0,
    next_connect_try_at = 0,
    transport_ready = false,
    hardware_detected = false,
    session_mode_live = false,
  }, BridgeSession)
  self:load_session_state()
  local readiness_stats = read_state_file(READINESS_STATS_PATH)
  if type(readiness_stats) == "table" then
    self.readiness_sample_count = tonumber(readiness_stats.sampleCount or "") or self.readiness_sample_count
    self.readiness_total_ms = tonumber(readiness_stats.totalMs or "") or self.readiness_total_ms
    self.readiness_last_ms = tonumber(readiness_stats.lastMs or "") or self.readiness_last_ms
    self.readiness_max_ms = tonumber(readiness_stats.maxMs or "") or self.readiness_max_ms
  end
  -- Persisted state is diagnostic history, not current readiness evidence.
  -- Every bridge process must re-prove hardware and PTP transport before it
  -- can publish READY; otherwise a stale state file creates a false-ready
  -- window during daemon/session replacement.
  self.backend_started_at = started_at
  self.backend_state = "idle"
  self.transport_ready = false
  self.hardware_detected = false
  self.live_view_active = false
  self.readiness_state = "detecting"
  self.readiness_reason = "backend_starting"
  self.readiness_started_at = started_at
  self.readiness_transition_at = started_at
  self.ready_since_at = 0
  self.capability_certified = false
  self.capability_certified_at = 0
  self.capability_certification_reason = "capability_certification_required"
  self.device_ready_verified = false
  self.properties_ready = false
  self.storage_ready = false
  self.command_route_ready = false
  self.live_view_path_ready = false
  self.capture_route_ready = false
  self.file_route_ready = false
  self.session_id = tonumber(self.session_id or SESSION_ID) or self.session_id
  self.session_label = self.session_label or current_session_label()
  self.live_session_id, self.live_session_label = read_live_session()
  SESSION_ID = self.session_id or SESSION_ID
  SESSION_LABEL = self.session_label or SESSION_LABEL
  local mode = read_mode_file(SESSION_MODE)
  self.session_mode_live = mode == "live"
  return self
end

function BridgeSession:_wire()
  if not self.wire then
    self.wire = DdServerWire.new(self.host, self.port, BRIDGE_TIMEOUT)
  end
  return self.wire
end

function BridgeSession:close()
  if self.wire then
    self.wire:close()
  end
  self.wire = nil
  self.device = nil
  self.live_view_active = false
  self.last_power = nil
  self.last_status_at = 0
  self.last_battery_at = 0
  self.backend_state = "idle"
  self.transport_ready = false
  self.hardware_detected = false
  self:clear_frame_cache()
  self:clear_captured_preview_cache()
  self:clear_captured_object_cache()
end

function BridgeSession:mark_connect_failure(reason)
  self.last_error = tostring(reason or "")
  self.last_connect_at = now_ms()
  self.next_connect_try_at = self.last_connect_at + CONNECT_RETRY_DELAY_MS
end

function BridgeSession:load_session_state()
  local state = read_state_file(SESSION_STATE)
  if type(state) ~= "table" then
    return false
  end
  self.backend_state = state.backendState or self.backend_state or "idle"
  self.live_view_active = state.liveView == "true"
  self.transport_ready = state.transportReady == "true"
  self.hardware_detected = state.hardwareDetected == "true"
  self.last_status = state.lastStatus or self.last_status or "idle"
  self.last_error = state.lastError or self.last_error or ""
  self.backend_started_at = tonumber(state.backendStartedAt or "") or self.backend_started_at
  self.last_status_at = tonumber(state.lastStatusAt or "") or self.last_status_at
  self.last_recover_reason = state.lastRecoverReason or self.last_recover_reason or ""
  self.last_command_at = tonumber(state.lastCommandAt or "") or self.last_command_at
  self.readiness_state = state.readinessState or self.readiness_state or "detecting"
  self.readiness_reason = state.readinessReason or self.readiness_reason or "backend_starting"
  self.readiness_started_at = tonumber(state.readinessStartedAt or "") or self.readiness_started_at
  self.readiness_transition_at = tonumber(state.readinessTransitionAt or "") or self.readiness_transition_at
  self.ready_since_at = tonumber(state.readySinceAt or "") or self.ready_since_at
  self.readiness_last_ms = tonumber(state.readinessLastMs or "") or self.readiness_last_ms
  self.readiness_sample_count = tonumber(state.readinessSampleCount or "") or self.readiness_sample_count
  self.readiness_total_ms = tonumber(state.readinessTotalMs or "") or self.readiness_total_ms
  self.readiness_max_ms = tonumber(state.readinessMaxMs or "") or self.readiness_max_ms
  self.live_view_faulted = state.liveViewFaulted == "true"
  self.live_view_fault_reason = state.liveViewFaultReason or self.live_view_fault_reason or ""
  self.live_view_limited = state.liveViewLimited == "true"
  self.live_view_limit_reason = state.liveViewLimitReason or self.live_view_limit_reason or ""
  self.session_id = tonumber(state.sessionId or "") or self.session_id
  self.session_label = state.sessionLabel or self.session_label or current_session_label()
  if state.liveView == "true" then
    self.session_mode_live = true
  end
  local vendor_id = tonumber(state.lastDeviceVendorId or "")
  local product_id = tonumber(state.lastDeviceProductId or "")
  if vendor_id and product_id then
    self.last_device = {
      vendor_id = vendor_id,
      product_id = product_id,
      vendor_name = state.lastDeviceVendorName or "NIKON",
      product_name = state.lastDeviceProductName or "NIKON DSC D810",
    }
  end
  return true
end

function BridgeSession:save_session_state()
  return write_state_file(SESSION_STATE, {
    backendState = self.backend_state or "idle",
    liveView = self.live_view_active == true and "true" or "false",
    transportReady = self.transport_ready == true and "true" or "false",
    hardwareDetected = self.hardware_detected and "true" or "false",
    lastStatus = self.last_status or "idle",
    lastError = self.last_error or "",
    backendStartedAt = tostring(self.backend_started_at or now_ms()),
    lastStatusAt = tostring(self.last_status_at or now_ms()),
    lastCommandAt = tostring(self.last_command_at or 0),
    readinessState = self.readiness_state or "detecting",
    readinessReason = self.readiness_reason or "backend_starting",
    readinessStartedAt = tostring(self.readiness_started_at or self.backend_started_at or now_ms()),
    readinessTransitionAt = tostring(self.readiness_transition_at or 0),
    readySinceAt = tostring(self.ready_since_at or 0),
    readinessLastMs = tostring(self.readiness_last_ms or 0),
    readinessSampleCount = tostring(self.readiness_sample_count or 0),
    readinessTotalMs = tostring(self.readiness_total_ms or 0),
    readinessMaxMs = tostring(self.readiness_max_ms or 0),
    liveViewFaulted = self.live_view_faulted == true and "true" or "false",
    liveViewFaultReason = self.live_view_fault_reason or "",
    liveViewLimited = self.live_view_limited == true and "true" or "false",
    liveViewLimitReason = self.live_view_limit_reason or "",
    lastRecoverReason = self.last_recover_reason or "",
    lastDeviceVendorId = self.last_device and tostring(self.last_device.vendor_id or "") or "",
    lastDeviceProductId = self.last_device and tostring(self.last_device.product_id or "") or "",
    lastDeviceVendorName = self.last_device and tostring(self.last_device.vendor_name or "") or "",
    lastDeviceProductName = self.last_device and tostring(self.last_device.product_name or "") or "",
    sessionId = tostring(self.session_id or SESSION_ID or ""),
    sessionLabel = self.session_label or session_label_from_id(self.session_id or SESSION_ID),
  })
end

function BridgeSession:reload_command_session(session_id)
  local id = tonumber(session_id or "")
  if not id then
    fail("invalid_session", "missing command session id")
  end
  self.session_id = id
  self.session_label = session_label_from_id(id)
  SESSION_ID = id
  SESSION_LABEL = self.session_label
  self.live_session_id, self.live_session_label = read_live_session()
  self:save_session_state()
  debug_log(string.format("command session rebound id=%d live=%s", id, tostring(self.live_session_label or "")))
  return self:_ok(self.live_view_active and "liveview_on" or "ready", {
    liveView = self.live_view_active,
    liveSessionId = self.live_session_id,
    liveSessionLabel = self.live_session_label,
    commandSessionId = self.session_id,
    commandSessionLabel = self.session_label,
  })
end

function BridgeSession:save_session_mode(mode)
  self.session_mode_live = mode == "live"
  return write_mode_file(SESSION_MODE, self.session_mode_live and "live" or "idle")
end

function BridgeSession:load_latest_metrics()
  return self.last_metrics
end

function BridgeSession:set_backend_state(state)
  self.backend_state = state or self.backend_state or "idle"
end

function BridgeSession:record_status_touch()
  self.last_status_at = now_ms()
end

function BridgeSession:record_command_touch()
  self.last_command_at = now_ms()
end

function BridgeSession:purge_idle_runtime(reason)
  debug_log(string.format("idle purge: %s", tostring(reason or "idle")))
  self:clear_frame_cache()
  self:clear_captured_preview_cache()
  self:clear_captured_object_cache()
  self.last_metrics = nil
  self.last_frame = nil
  self.last_frame_at = 0
  self.last_error = ""
  if not self.live_view_active then
    self:purge_frame_files()
  end
  for _, lockdir in ipairs({
    FRAME_CAPTURE_LOCK,
    COMMAND_ACTION_LOCK,
  }) do
    pcall(function()
      os.remove(lockdir .. "/owner")
    end)
    pcall(function()
      os.remove(lockdir .. "/pid")
    end)
    pcall(function()
      os.execute(string.format("rmdir %s >/dev/null 2>&1", shell_quote(lockdir)))
    end)
  end
  self:save_session_state()
end

function BridgeSession:frame_age_ms()
  if not self.last_frame_at or self.last_frame_at <= 0 then
    return nil
  end
  return now_ms() - self.last_frame_at
end

function BridgeSession:has_recent_runtime_state()
  local frame_age = self:frame_age_ms()
  return frame_age ~= nil and frame_age <= FRAME_LAST_GOOD_GRACE_MS
end

function BridgeSession:read_last_good_frame(max_age_ms)
  local meta = read_meta_file(FRAME_META)
  if not path_has_size(FRAME_LAST_GOOD) then
    return nil, meta
  end
  local capture_done_at = tonumber((meta or {}).captureDoneAt or (meta or {}).writeDoneAt or (meta or {}).startedAt or "0") or 0
  if max_age_ms and capture_done_at > 0 and (now_ms() - capture_done_at) > max_age_ms then
    return nil, meta
  end
  local handle = io.open(FRAME_LAST_GOOD, "rb")
  if not handle then
    return nil, meta
  end
  local blob = handle:read("*a")
  handle:close()
  if not is_jpeg_blob(blob) then
    return nil, meta
  end
  self.last_frame = blob
  self.last_frame_at = capture_done_at > 0 and capture_done_at or self.last_frame_at
  meta = meta or {}
  meta.cached = true
  meta.lastGood = true
  self.last_metrics = meta
  return blob, meta
end

function BridgeSession:is_session_stale()
  if not self.live_view_active then
    return false
  end
  local age = self:frame_age_ms()
  return age ~= nil and age > SESSION_STALE_MS
end

function BridgeSession:refresh_battery(force)
  local age = now_ms() - (self.last_battery_at or 0)
  if not force and BATTERY_CACHE_TTL_MS > 0 and self.last_power and age <= BATTERY_CACHE_TTL_MS then
    return self.last_power.batteryPercent
  end
  local ok_battery, battery_percent = pcall(function()
    return self:_wire():get_battery_percent()
  end)
  if ok_battery and type(battery_percent) == "number" then
    self.last_battery_at = now_ms()
    self.last_power = {
      batteryPercent = battery_percent,
      batterySource = "ptp",
      batteryMeasuredAtMs = self.last_battery_at,
    }
    self:update_live_view_limitation(battery_percent)
    return battery_percent
  end
  self.last_power = nil
  self.last_battery_at = 0
  return nil
end

function BridgeSession:update_live_view_limitation(battery_percent)
  local percent = tonumber(battery_percent)
  local limited = percent ~= nil and percent <= LIVE_VIEW_LOW_BATTERY_THRESHOLD
  self.live_view_limited = limited
  self.live_view_limit_reason = limited and "low_battery" or ""
  if limited then
    self.live_view_path_ready = false
  end
  return limited
end

function BridgeSession:update_probe_state(probe)
  if type(probe) ~= "table" then
    return
  end
  local probe_transport_ready = probe.transportReady == true
  if probe_transport_ready then
    self.transport_ready = true
  else
    self.transport_ready = false
  end
  self.hardware_detected = probe.hardwareDetected == true
  -- Client intent is persisted separately; only the camera probe may assert
  -- that physical Live View is actually active.
  self.live_view_active = probe.liveView == true
  if probe.batterySampled == true then
    if type(probe.batteryPercent) == "number" then
      self.last_battery_at = tonumber(probe.batteryMeasuredAtMs) or now_ms()
      self.last_power = {
        batteryPercent = probe.batteryPercent,
        batterySource = probe.batterySource or "ptp",
        batteryMeasuredAtMs = self.last_battery_at,
      }
    else
      self.last_power = nil
      self.last_battery_at = 0
    end
  end
end

function BridgeSession:recover_transport(reason, preserve_live_intent)
  local requested_live = preserve_live_intent == true
    and (self.session_mode_live == true or self.live_view_active == true)
  self.last_recover_reason = tostring(reason or "")
  debug_log(string.format("backend recover requested: %s", tostring(reason or "unknown")))
  self.reconnect_count = (tonumber(self.reconnect_count) or 0) + 1
  self:set_backend_state("recovering")
  local ok, err = pcall(function()
    -- During active live view, legacy fallback can race procd's ddserver
    -- respawn and turn a retryable socket outage into a sticky start failure.
    self:connect(not requested_live)
  end)
  if not ok then
    if requested_live then
      -- ddserver/procd can need a few seconds to return. Keep the explicit
      -- live intent and producer loop alive so the bounded retry can reconnect
      -- instead of silently collapsing the session to idle.
      self.session_mode_live = true
      self.live_view_active = false
      self.transport_ready = false
      self.hardware_detected = false
      self.last_status = "recovering"
      self:set_backend_state("degraded")
      self:save_session_mode("live")
      self:save_session_state()
    else
      self:invalidate_session("recover failed: " .. tostring(type(err) == "table" and (err.message or err.status) or err), "idle")
    end
    error(err, 0)
  end
  self:save_session_state()
  return true
end

function BridgeSession:invalidate_session(reason, backend_state)
  self:close()
  self.device = nil
  self.transport_ready = false
  self.hardware_detected = false
  self.live_view_active = false
  self.session_mode_live = false
  self.last_status = "reset"
  self.last_error = tostring(reason or "")
  self.last_recover_reason = tostring(reason or "")
  self:set_backend_state(backend_state or "idle")
  self:save_session_mode("idle")
  self:save_session_state()
end

function BridgeSession:reset_session(reason)
  debug_log(string.format("reset begin reason=%s", tostring(reason or "reset")))
  self:invalidate_session(reason or "reset", "idle")
  self.backend_started_at = now_ms()
  self.last_status_at = 0
  self.last_battery_at = 0
  self.last_frame_at = 0
  self.last_recover_at = 0
  self.reconnect_count = 0
  self.last_power = nil
  self.last_metrics = nil
  self.last_device = nil
  for _, path in ipairs({
    SESSION_STATE,
    SESSION_MODE,
    SESSION_BOOT,
    FRAME_REFRESH_PIDFILE,
    FRAME_PATH,
    FRAME_LAST_GOOD,
    FRAME_META,
    CAPTURED_PREVIEW_PATH,
    CAPTURED_PREVIEW_META,
    CAPTURED_OBJECT_PATH,
    CAPTURED_OBJECT_META,
    BATTERY_CACHE_PATH,
    BATTERY_CACHE_PATH .. ".ts",
    DEBUG_LOG,
    "/tmp/gphoto-detect.out",
    BRIDGE_PIDFILE,
    WS_PIDFILE,
    SESSION_HEALTH_PIDFILE,
    STACK_GUARDIAN_PIDFILE,
    BATTERY_WORKER_PIDFILE,
  }) do
    pcall(function()
      os.remove(path)
    end)
  end
  for _, lockdir in ipairs({
    FRAME_CAPTURE_LOCK,
    COMMAND_ACTION_LOCK,
    BATTERY_WORKER_LOCKDIR,
    BRIDGE_START_LOCK,
    BRIDGE_RESTART_LOCK,
    WS_START_LOCK,
    SESSION_HEALTH_START_LOCK,
    STACK_GUARDIAN_START_LOCK,
    BATTERY_WORKER_START_LOCK,
  }) do
    pcall(function()
      os.remove(lockdir .. "/owner")
    end)
    pcall(function()
      os.remove(lockdir .. "/pid")
    end)
    pcall(function()
      os.execute(string.format("rmdir %s >/dev/null 2>&1", shell_quote(lockdir)))
    end)
  end
  self:clear_frame_cache()
  self:clear_captured_preview_cache()
  self:clear_captured_object_cache()
  self:purge_frame_files()
  self.last_status = "reset"
  self.last_error = tostring(reason or "reset")
  self.last_recover_reason = tostring(reason or "reset")
  self:save_session_mode("idle")
  self:save_session_state()
  debug_log("reset done")
  return self:_ok("reset", {
    backend = BACKEND_NAME,
    sessionBackend = true,
    backendState = "idle",
    liveView = false,
    transportReady = false,
    hardwareDetected = false,
    cameraDetected = false,
  })
end

function BridgeSession:maintain_runtime_state()
  local wire = self:_wire()

  if not self.wire or not self.device then
    local probe = wire:probe_camera_state()
    self:update_probe_state(probe)
    if probe.cameraDetected or probe.hardwareDetected then
      self:set_backend_state(probe.transportReady and (probe.liveView and "live" or "ready") or "degraded")
      self:record_status_touch()
    else
      self.transport_ready = false
      self.live_view_active = false
      self:set_backend_state("idle")
      self:record_status_touch()
      return
    end
  end

  local probe = wire:probe_camera_state()
  self:update_probe_state(probe)

  if not probe.cameraDetected and not probe.hardwareDetected then
    self:invalidate_session("camera_missing", "idle")
    self:record_status_touch()
    return
  end

  if self.hardware_detected and not self.transport_ready then
    self:set_backend_state("degraded")
    self:record_status_touch()
    return
  end

  if self.transport_ready then
    self:refresh_battery((now_ms() - (self.last_battery_at or 0)) > BATTERY_CACHE_TTL_MS)
  end

  self:set_backend_state(self.transport_ready
      and (self.live_view_active and "live" or "ready")
      or (self.hardware_detected and "degraded" or "idle"))
  self:record_status_touch()
end

function BridgeSession:refresh_runtime_state(force_camera_poll)
  self:ensure_connected()
  local now = now_ms()
  if not force_camera_poll and self.last_status_at > 0 and (now - self.last_status_at) <= STATUS_CACHE_TTL_MS then
    return
  end
  local probe = self:_wire():probe_camera_state()
  self:update_probe_state(probe)
  if self.hardware_detected and not self.transport_ready then
    self:set_backend_state("degraded")
  end
  self.live_view_active = probe.liveView == true
  if self.transport_ready then
    self:refresh_battery(force_camera_poll or (now - (self.last_battery_at or 0)) > BATTERY_CACHE_TTL_MS)
  end
  self:record_status_touch()
end

function BridgeSession:maintain()
  debug_log("maintain begin")
  local ok, err = pcall(function()
    self:maintain_runtime_state()
  end)
  if not ok then
    self:invalidate_session(type(err) == "table" and (err.message or err.status) or tostring(err), "idle")
    return self:_ok("maintained", {
      liveView = false,
      degraded = true,
      maintenanceError = self.last_error,
    })
  end
  if self.last_command_at > 0 and (now_ms() - self.last_command_at) > IDLE_PURGE_MS then
    self:purge_idle_runtime("idle timeout")
  end
  self.last_status = "maintained"
  self.last_error = ""
  debug_log("maintain done")
  return self:_ok("maintained", { liveView = self.live_view_active })
end

function BridgeSession:restore_live_view_after_connect()
  if not self.device or not self.transport_ready then
    return false
  end
  self.live_session_id, self.live_session_label = ensure_live_session()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy while restoring live session")
  end
  local ok, err = pcall(function()
    self:_wire():start_live_view()
  end)
  release_lock(COMMAND_ACTION_LOCK)
  if not ok then
    error(err, 0)
  end
  self.live_view_active = true
  self.session_mode_live = true
  self.transport_ready = true
  local frame_ok = false
  local frame_err = nil
  for attempt = 1, LIVE_FIRST_FRAME_RETRY_COUNT do
    frame_ok, frame_err = pcall(function()
      -- Keep the accepted Nikon Live View transition intact while its image
      -- producer warms up. Restarting LIVE on an empty early payload can put
      -- the camera back into DeviceBusy.
      self:_capture_frame(false, false, true)
    end)
    if frame_ok then break end
    debug_log(string.format("live_start first frame pending attempt=%d error=%s", attempt, error_text(frame_err)))
    sleep_ms(LIVE_FIRST_FRAME_RETRY_MS)
  end
  if not frame_ok then
    local frame_error_message = error_text(frame_err)
    debug_log("live restore first frame verification failed: " .. frame_error_message)
    pcall(function()
      self:_wire():stop_live_view()
    end)
    local restored_wire = self:_wire()
    restored_wire.live_view_active = false
    self.live_view_active = false
    self.transport_ready = false
    self.last_frame_at = 0
    self:set_backend_state("degraded")
    self:clear_frame_cache()
    self:purge_frame_files()
    self.last_status = "liveview_restore_failed"
    self.last_error = frame_error_message
    self:save_session_mode("live")
    self:save_session_state()
    fail("liveview_restore_failed", frame_error_message)
  end
  self:set_backend_state("live")
  self.last_status = "liveview_on"
  self.last_error = ""
  self:save_session_mode("live")
  self:save_session_state()
  debug_log(string.format("live session restored id=%s label=%s", tostring(self.live_session_id or ""), tostring(self.live_session_label or "")))
  return true
end

function BridgeSession:connect(allow_legacy_fallback)
  if allow_legacy_fallback == nil then
    allow_legacy_fallback = true
  end
  debug_log("connect begin")
  local restore_live = self.session_mode_live == true or self.live_view_active == true
  self:close()
  self:set_backend_state("connecting")
  self.last_connect_at = now_ms()
  self.next_connect_try_at = 0
  self.session_mode_live = false
  local wire = self:_wire()
  local prefer_legacy = os.getenv("D810D_PREFER_LEGACY_TRANSPORT")
  if prefer_legacy == "1" or prefer_legacy == "true" or prefer_legacy == "legacy" then
    debug_log("connect prefer legacy transport")
    local hardware_detected = wire:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
    if hardware_detected then
      wire:enable_legacy_transport_only("prefer legacy transport")
      debug_log("connect legacy transport enabled")
      local fallback = fallback_local_device()
      self.device = fallback
      self.last_device = fallback
      self.hardware_detected = true
      self.transport_ready = true
      self.live_view_active = false
      self.last_status = "connected"
      self.last_error = ""
      self.frame_failures = 0
      self:record_status_touch()
      if restore_live then
        self:restore_live_view_after_connect()
      else
        self:save_session_mode("idle")
      end
      if not restore_live then
        self:set_backend_state("ready")
      end
      self:save_session_state()
      return
    end
  end
  local persistent_ok, persistent_err = pcall(function()
    wire:connect()
  end)
  if not persistent_ok then
    debug_log(string.format("connect persistent failed: %s", error_text(persistent_err)))
    if not allow_legacy_fallback then
      self.transport_ready = false
      self.hardware_detected = wire:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
      fail("transport_error", "persistent ddserver transport unavailable")
    end
    local hardware_detected = wire:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
    if hardware_detected then
      wire:enable_legacy_transport_only(persistent_err)
      debug_log("connect falling back to legacy transport")
      local fallback = fallback_local_device()
      self.device = fallback
      self.last_device = fallback
      self.hardware_detected = true
      self.transport_ready = true
      self.live_view_active = false
      self.last_status = "connected"
      self.last_error = ""
      self.frame_failures = 0
      self:record_status_touch()
      if restore_live then
        self:restore_live_view_after_connect()
      else
        self:save_session_mode("idle")
      end
      if not restore_live then
        self:set_backend_state("ready")
      end
      self:save_session_state()
      return
    end
    self:mark_connect_failure(persistent_err)
    error(persistent_err, 0)
  end
  local candidates = {}
  if self.last_device then
    candidates[#candidates + 1] = self.last_device
    debug_log(string.format("trying remembered device %04x:%04x", self.last_device.vendor_id, self.last_device.product_id))
  end
  local fallback = fallback_local_device()
  if fallback then
    candidates[#candidates + 1] = fallback
    debug_log(string.format("trying fallback device %04x:%04x %s %s", fallback.vendor_id, fallback.product_id, tostring(fallback.vendor_name), tostring(fallback.product_name)))
  end
  local devices = {}
  local ok, err = pcall(function()
    devices = wire:read_device_list()
  end)
  if not ok then
    debug_log(string.format("device list failed: %s", tostring(err)))
  end
  for _, scanned in ipairs(devices) do
    candidates[#candidates + 1] = scanned
  end

  local device = nil
  local last_connect_error = nil
  local seen = {}
  for _, candidate in ipairs(candidates) do
    local key = string.format("%04x:%04x", candidate.vendor_id or 0, candidate.product_id or 0)
    if not seen[key] then
      seen[key] = true
      local connect_ok, connect_err = pcall(function()
        return wire:connect_device(candidate)
      end)
      if connect_ok then
        device = candidate
        debug_log(string.format("connect candidate %s accepted", key))
        self.transport_ready = wire.transport_ready == true
        self.hardware_detected = wire.hardware_detected == true
        break
      end
      last_connect_error = connect_err
      debug_log(string.format("connect candidate %s failed: %s", key, error_text(connect_err)))
    end
  end
  if not device then
    local hardware_detected = wire:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
    if hardware_detected then
      wire:enable_legacy_transport_only(last_connect_error)
      debug_log("connect fallback to local device after scan")
      local fallback = fallback_local_device()
      self.device = fallback
      self.last_device = fallback
      self.hardware_detected = true
      self.transport_ready = true
      self.live_view_active = false
      self.last_status = "connected"
      self.last_error = ""
      self.frame_failures = 0
      self:record_status_touch()
      if restore_live then
        self:restore_live_view_after_connect()
      else
        self:save_session_mode("idle")
      end
      if not restore_live then
        self:set_backend_state("ready")
      end
      self:save_session_state()
      return
    end
    self:mark_connect_failure("camera_missing")
    self:invalidate_session("camera_missing", "idle")
    if type(last_connect_error) == "table" then
      fail(last_connect_error.status or "camera_missing", last_connect_error.message or "device connect failed")
    end
    fail("camera_missing", "no imaging device found on ddserver")
  end
  if self.transport_ready then
    self:refresh_battery(true)
  end
  self.device = device
  self.last_device = device
  self.live_view_active = false
  self.last_status = "connected"
  self.last_error = ""
  self.frame_failures = 0
  self.next_connect_try_at = 0
  self:record_status_touch()
  if restore_live then
    self:restore_live_view_after_connect()
  else
    self:save_session_mode("idle")
    self:set_backend_state(self.transport_ready and "ready" or "degraded")
  end
  self:save_session_state()
  debug_log(string.format("connect done backend=%s transport=%s live=%s", tostring(self.backend_state or "idle"), tostring(self.transport_ready == true), tostring(self.live_view_active == true)))
end

function BridgeSession:ensure_connected()
  local now = now_ms()
  if self.next_connect_try_at > 0 and now < self.next_connect_try_at then
    return
  end
  local allow_legacy_fallback = not (self.session_mode_live == true or self.live_view_active == true)
  if not self.wire or not self.device then
    if allow_legacy_fallback then
      self:connect(true)
    else
      self:recover_transport("ensure connected during live view", true)
    end
    return
  end
  if not self.transport_ready then
    if allow_legacy_fallback then
      self:connect(true)
    else
      self:recover_transport("ensure transport during live view", true)
    end
  end
end

function BridgeSession:shutdown()
  local wire = self.wire
  if wire then
    if self.live_view_active or wire.live_view_active then
      local stopped, stop_err = pcall(function() wire:stop_live_view() end)
      if not stopped then
        debug_log("shutdown live stop failed: " .. error_text(stop_err))
      end
    end
    wire:graceful_close()
  end
  self.wire = nil
  self.device = nil
  self.live_view_active = false
  self.transport_ready = false
  self.hardware_detected = false
  self:invalidate_capability_certification("transport_closed")
  self.backend_state = "idle"
  self.session_mode_live = false
  clear_live_session()
  self:clear_frame_cache()
  self:save_session_mode("idle")
  self:save_session_state()
  return response_ok("stopping", { backend = BACKEND_NAME, sessionBackend = true })
end

local function response_bool(extra, key, fallback)
  if extra[key] ~= nil then
    return extra[key] == true
  end
  return fallback == true
end

function BridgeSession:invalidate_capability_certification(reason)
  self.capability_certified = false
  self.capability_certified_at = 0
  self.capability_certification_reason = tostring(reason or "capability_certification_required")
  self.device_ready_verified = false
  self.properties_ready = false
  self.storage_ready = false
  self.command_route_ready = false
  self.live_view_path_ready = false
  self.capture_route_ready = false
  self.file_route_ready = false
end

function BridgeSession:capability_certification_fresh()
  local certified_at = tonumber(self.capability_certified_at) or 0
  local age_ms = certified_at > 0 and math.max(0, now_ms() - certified_at) or 0
  return self.capability_certified == true
    and certified_at > 0
    and (CAPABILITY_CERTIFICATION_TTL_MS <= 0 or age_ms <= CAPABILITY_CERTIFICATION_TTL_MS),
    age_ms
end

function BridgeSession:record_capability_failure(command_name, err)
  command_name = tostring(command_name or ""):upper()
  local status = type(err) == "table" and tostring(err.status or "") or "transport_error"
  if status == "liveview_limited" or status == "operation_limited" then
    return false
  end
  if command_name == "AF" and status == "focus_failed" then
    return false
  end
  if status == "bad_request" or status == "unknown" or status:match("^invalid_") then
    return false
  end
  local sensitive = {
    LIVE_START = true,
    LIVE_STOP = true,
    AF = true,
    SHUTTER = true,
    SHUTTER_PREPARE = true,
    SHUTTER_HOLD_BEGIN = true,
    SHUTTER_HOLD_END = true,
    RAW_MODE = true,
    UNLOCK = true,
    STORAGE = true,
    CAPTURE_EVENTS = true,
    FRAME = true,
    FRAME_BIN = true,
    FRAME_STORE = true,
    CAPTURED_JPEG = true,
    CAPTURED_OBJECT = true,
    CAPTURED_IMAGES = true,
    MANUAL_STATUS = true,
    SET_MANUAL_MODE = true,
    SET_AUTO_ISO = true,
    SET_M = true,
  }
  if not sensitive[command_name] then
    return false
  end
  local reason = string.format("%s_failed:%s", command_name:lower(), error_text(err))
  self:invalidate_capability_certification(reason)
  self.last_error = reason
  self:set_backend_state("degraded")
  self:save_session_state()
  return true
end

function BridgeSession:certify_capabilities()
  self:invalidate_capability_certification("capability_verification_in_progress")
  self:ensure_connected()
  local wire = self:_wire()
  local preserve_live = self.live_view_active == true or self.session_mode_live == true
  local started_live = false
  local original_recording_media = nil
  local certification_started_at = now_ms()

  local ok, err = pcall(function()
    wire:wait_device_ready(3000, 20)
    self.device_ready_verified = true

    local required_properties = {
      PROP_LIVE_VIEW_STATUS,
      PROP_RECORDING_MEDIA,
      PROP_AF_MODE_SELECT,
      PROP_EXPOSURE_PROGRAM_MODE,
      PROP_EXPOSURE_INDEX,
      PROP_EXPOSURE_ISO_STATUS,
      PROP_AUTO_ISO,
    }
    for _, code in ipairs(required_properties) do
      local value = wire:get_device_prop_value(code)
      if type(value) ~= "string" or #value == 0 then
        fail("capability_verification_failed", string.format("required property 0x%04x is unavailable", code))
      end
      if code == PROP_RECORDING_MEDIA then
        original_recording_media = value
      end
    end
    self.properties_ready = true

    local storage_ids = wire:get_storage_ids()
    if type(storage_ids) ~= "table" or #storage_ids == 0 then
      fail("capability_verification_failed", "camera storage is unavailable")
    end
    local storage = wire:get_storage_info(storage_ids[1])
    if type(storage) ~= "table" or tonumber(storage.storageId or 0) == 0 then
      fail("capability_verification_failed", "camera storage information is unavailable")
    end
    wire:get_object_handles(storage_ids[1], PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
    self.storage_ready = true
    self.file_route_ready = true
    self.command_route_ready = true
    self.capture_route_ready = true

    local battery_percent = self:refresh_battery(true)
    local live_view_limited = self:update_live_view_limitation(battery_percent)

    if live_view_limited then
      if preserve_live then
        pcall(function() wire:stop_live_view() end)
        self.live_view_active = false
        self:save_session_mode("idle")
      end
    else
      if not preserve_live then
        wire:start_live_view()
        started_live = true
        self.live_view_active = true
      else
        wire:start_live_view()
        self.live_view_active = true
      end
      local frame = wire:live_view_frame()
      if type(frame) ~= "string" or #frame <= 384 or not is_jpeg_blob(frame) then
        fail("capability_verification_failed", "live view verification did not return a valid JPEG frame")
      end
      self.last_frame = frame
      self.last_frame_at = now_ms()
      self.frame_failures = 0
      self.live_view_path_ready = true

      if started_live then
        wire:stop_live_view()
        self.live_view_active = false
        if type(original_recording_media) == "string" and #original_recording_media > 0 then
          wire:set_device_prop_value(PROP_RECORDING_MEDIA, original_recording_media)
        end
        wire:wait_device_ready(3000, 20)
      end
    end
  end)

  if not ok then
    if started_live then
      pcall(function() wire:stop_live_view() end)
      self.live_view_active = false
      if type(original_recording_media) == "string" and #original_recording_media > 0 then
        pcall(function() wire:set_device_prop_value(PROP_RECORDING_MEDIA, original_recording_media) end)
      end
    end
    local reason = error_text(err)
    self:invalidate_capability_certification(reason)
    self.last_error = reason
    self:set_backend_state("degraded")
    self:save_session_state()
    rethrow(err)
  end

  self.capability_certified = true
  self.capability_certified_at = now_ms()
  self.capability_certification_reason = self.live_view_limited and "certified_limited" or "certified"
  self.last_error = ""
  self.live_view_faulted = false
  self.live_view_fault_reason = ""
  self:set_backend_state(self.live_view_active and "live" or "ready")
  self:save_session_state()
  debug_log(string.format("capability certification passed in %.0fms", self.capability_certified_at - certification_started_at))
  return true
end

function BridgeSession:update_readiness(extra)
  extra = extra or {}
  local now = now_ms()
  local backend_state = tostring(extra.backendState or self.backend_state or "idle")
  local hardware_detected = response_bool(extra, "hardwareDetected", self.hardware_detected)
  local camera_detected = response_bool(extra, "cameraDetected",
    self.hardware_detected == true or self.transport_ready == true or self.device ~= nil)
  local transport_ready = response_bool(extra, "transportReady", self.transport_ready)
  local live_view = response_bool(extra, "liveView", self.live_view_active)
  local software_ready = response_bool(extra, "softwareReady", transport_ready or live_view)
  local degraded = response_bool(extra, "degraded", backend_state == "degraded")
  local frame_age_ms = tonumber(extra.frameAgeMs)
  if frame_age_ms == nil then
    frame_age_ms = self:frame_age_ms()
  end
  local live_frame_ready = not live_view
    or ((tonumber(self.frame_failures) or 0) == 0
      and frame_age_ms ~= nil and frame_age_ms >= 0 and frame_age_ms <= 3000)
  local capability_certified, capability_age_ms = self:capability_certification_fresh()
  if self.capability_certified == true and not capability_certified then
    self.capability_certified = false
    self.capability_certification_reason = "capability_certification_expired"
  end

  local state
  local reason
  if backend_state == "recovering" then
    state, reason = "recovering", self.last_recover_reason ~= ""
      and self.last_recover_reason or "transport_recovery"
  elseif not camera_detected and not hardware_detected then
    state, reason = "offline", "camera_not_detected"
  elseif not transport_ready then
    state, reason = "verifying", self.last_error ~= ""
      and self.last_error or "transport_not_ready"
  elseif not capability_certified then
    state, reason = "verifying", self.capability_certification_reason ~= ""
      and self.capability_certification_reason or "capability_certification_required"
  elseif self.live_view_limited == true then
    state, reason = "limited", self.live_view_limit_reason ~= ""
      and self.live_view_limit_reason or "live_view_limited"
  elseif self.live_view_faulted == true then
    state, reason = "degraded", self.live_view_fault_reason ~= ""
      and self.live_view_fault_reason or "liveview_verification_failed"
  elseif live_view and not live_frame_ready then
    state, reason = "degraded", "liveview_frame_stale"
  elseif degraded or backend_state == "degraded" then
    state, reason = "degraded", self.last_error ~= ""
      and self.last_error or "backend_degraded"
  elseif software_ready and (backend_state == "ready" or backend_state == "live") then
    state, reason = "ready", "ready"
  else
    state, reason = "connecting", "services_preparing"
  end
  reason = tostring(reason or "unknown"):gsub("[\r\n=]", " "):sub(1, 160)

  local previous = self.readiness_state or "detecting"
  local previous_reason = self.readiness_reason or ""
  if state ~= previous then
    if state == "ready" or state == "limited" then
      local started_at = tonumber(self.readiness_started_at) or tonumber(self.backend_started_at) or now
      self.readiness_last_ms = math.max(0, now - started_at)
      self.readiness_sample_count = (tonumber(self.readiness_sample_count) or 0) + 1
      self.readiness_total_ms = (tonumber(self.readiness_total_ms) or 0) + self.readiness_last_ms
      self.readiness_max_ms = math.max(tonumber(self.readiness_max_ms) or 0, self.readiness_last_ms)
      self.ready_since_at = now
      write_state_file(READINESS_STATS_PATH, {
        sampleCount = tostring(self.readiness_sample_count),
        totalMs = tostring(self.readiness_total_ms),
        lastMs = tostring(self.readiness_last_ms),
        maxMs = tostring(self.readiness_max_ms),
        updatedAtMs = tostring(now),
      })
    elseif previous == "ready" or previous == "limited" then
      self.readiness_started_at = now
      self.ready_since_at = 0
    end
    self.readiness_state = state
    self.readiness_transition_at = now
  end
  self.readiness_reason = reason
  if state ~= previous or reason ~= previous_reason then
    debug_log(string.format(
      "readiness transition from=%s to=%s reason=%s readyAfterMs=%d",
      previous,
      state,
      tostring(reason),
      tonumber(self.readiness_last_ms) or 0
    ))
    self:save_session_state()
  end

  local sample_count = tonumber(self.readiness_sample_count) or 0
  local average_ms = sample_count > 0
    and math.floor((tonumber(self.readiness_total_ms) or 0) / sample_count + 0.5)
    or 0
  return {
    appReady = state == "ready" or state == "limited",
    operationalState = state == "limited" and "limited"
      or ((state == "degraded" or state == "offline") and "fault" or "normal"),
    limitationActive = state == "limited",
    limitationStage = state == "limited" and "live_view" or "",
    limitationReason = state == "limited" and reason or "",
    readinessState = state,
    readinessReason = reason,
    readinessStartedAt = tonumber(self.readiness_started_at) or 0,
    readinessTransitionAt = tonumber(self.readiness_transition_at) or 0,
    readySinceAt = tonumber(self.ready_since_at) or 0,
    readyAfterMs = tonumber(self.readiness_last_ms) or 0,
    readinessSampleCount = sample_count,
    readinessAverageMs = average_ms,
    readinessMaxMs = tonumber(self.readiness_max_ms) or 0,
    capabilityCertified = capability_certified,
    capabilityCertifiedAt = tonumber(self.capability_certified_at) or 0,
    capabilityAgeMs = capability_age_ms,
    deviceReady = capability_certified and self.device_ready_verified == true,
    propertiesReady = capability_certified and self.properties_ready == true,
    storageReady = capability_certified and self.storage_ready == true,
    fileRouteReady = capability_certified and self.file_route_ready == true,
    captureReady = capability_certified and self.capture_route_ready == true,
    liveViewReady = capability_certified and self.live_view_limited ~= true and self.live_view_path_ready == true
      and self.live_view_faulted ~= true and live_frame_ready,
    liveViewLimited = capability_certified and self.live_view_limited == true,
    liveViewLimitReason = self.live_view_limited and self.live_view_limit_reason or "",
    liveViewFaulted = self.live_view_faulted == true,
    commandReady = capability_certified and self.command_route_ready == true
      and transport_ready and software_ready,
  }
end

function BridgeSession:derive_ui_phase(extra)
  extra = extra or {}
  local backend_state = tostring(extra.backendState or self.backend_state or "idle")
  local live_view = response_bool(extra, "liveView", self.live_view_active)
  local connected = response_bool(extra, "connected", self.transport_ready)
  local transport_ready = response_bool(extra, "transportReady", self.transport_ready)
  local camera_detected = response_bool(extra, "cameraDetected",
    self.hardware_detected == true or self.device ~= nil)
  local hardware_detected = response_bool(extra, "hardwareDetected", self.hardware_detected)

  if extra.limitationActive == true then
    return "Limited", "Live View unavailable: camera battery is low"
  end

  if extra.appReady == false then
    if extra.readinessState == "offline" then
      return "Offline", "Camera is not detected"
    end
    return "Preparing", tostring(extra.readinessReason or "Verifying camera readiness")
  end

  if backend_state == "recovering" or backend_state == "degraded" then
    return "Preparing", live_view
        and "Recovering the live session"
        or "Recovering the camera session"
  end

  if live_view and connected and transport_ready and (backend_state == "live" or backend_state == "ready") then
    return "Ready", "Live view and commands are ready right away"
  end

  if camera_detected and connected and transport_ready and (backend_state == "live" or backend_state == "ready") then
    return "Ready", live_view
        and "Live view and commands are ready right away"
        or "Camera connection confirmed and ready for commands"
  end

  if camera_detected or hardware_detected or connected or backend_state == "connecting" then
    return "Preparing", live_view
        and "Preparing or recovering the live session"
        or "Attaching the device and preparing the service session"
  end

  return "Detecting", "Checking whether the device is available"
end

function BridgeSession:_ok(status, extra)
  extra = extra or {}
  if extra.cameraDetected == nil then
    extra.cameraDetected = self.hardware_detected or self.transport_ready or self.device ~= nil
  end
  if extra.connected == nil then
    extra.connected = self.transport_ready == true
  end
  if extra.transportReady == nil then
    extra.transportReady = self.transport_ready == true
  end
  if extra.hardwareDetected == nil then
    extra.hardwareDetected = self.hardware_detected == true
  end
  if extra.liveView == nil then
    extra.liveView = self.live_view_active
  end
  if extra.backend == nil then
    extra.backend = BACKEND_NAME
  end
  if extra.sessionBackend == nil then
    extra.sessionBackend = true
  end
  if extra.commandSessionId == nil then
    extra.commandSessionId = self.session_id or SESSION_ID
  end
  if extra.commandSessionLabel == nil then
    extra.commandSessionLabel = self.session_label or current_session_label()
  end
  if extra.liveSessionId == nil then
    extra.liveSessionId = self.live_session_id or LIVE_SESSION_ID
  end
  if extra.liveSessionLabel == nil then
    extra.liveSessionLabel = self.live_session_label or LIVE_SESSION_LABEL
  end
  if extra.backendState == nil then
    extra.backendState = self.backend_state or "idle"
  end
  if extra.reconnectCount == nil then
    extra.reconnectCount = self.reconnect_count or 0
  end
  if extra.frameFailures == nil then
    extra.frameFailures = self.frame_failures or 0
  end
  if extra.frameAgeMs == nil then
    extra.frameAgeMs = self:frame_age_ms()
  end
  if extra.backendStartedAt == nil then
    extra.backendStartedAt = self.backend_started_at
  end
  if self.last_power then
    for k, v in pairs(self.last_power) do
      if k ~= "batteryPercent" and extra[k] == nil then
        extra[k] = v
      end
    end
  end
  if self.last_metrics then
    for k, v in pairs(self.last_metrics) do
      if k ~= "framePath" and k ~= "savedTo" then
        extra[k] = v
      end
    end
  end
  local readiness = self:update_readiness(extra)
  for key, value in pairs(readiness) do
    extra[key] = value
  end
  extra.uiPhase, extra.uiDetail = self:derive_ui_phase(extra)
  return response_ok(status, extra)
end

function BridgeSession:recover()
  local healthy = false
  if self.wire and self.device and self.transport_ready == true then
    if self.live_view_active == true and self.session_mode_live == true then
      local frame_age_ms = now_ms() - (tonumber(self.last_frame_at) or 0)
      healthy = (tonumber(self.frame_failures) or 0) == 0
        and self.last_frame ~= nil
        and frame_age_ms >= 0
        and frame_age_ms <= 3000
    else
      local ok, probe = pcall(function()
        return self.wire:probe_camera_state({
          force = true,
          allowHardwareScan = false,
          timeoutSec = 2,
        })
      end)
      if ok and type(probe) == "table" then
        self:update_probe_state(probe)
        healthy = probe.transportReady == true
      end
    end
  end
  if healthy then
    debug_log("recover endpoint skipped: transport already healthy")
    return self:status()
  end
  self:recover_transport("recover endpoint")
  return self:status()
end

function BridgeSession:kill(reason)
  debug_log(string.format("kill begin reason=%s", tostring(reason or "user kill")))
  self:set_backend_state("recovering")
  self.session_mode_live = false
  self.live_view_active = false
  clear_live_session()
  self.live_session_id = nil
  self.live_session_label = ""
  self:clear_frame_cache()
  self:purge_frame_files()

  -- Closing the old socket is what discards an in-flight PTP transaction.
  if self.wire then
    pcall(function() self.wire:close() end)
  end
  self.wire = nil
  self.device = nil
  self.transport_ready = false
  self.hardware_detected = false

  local connected, connect_err = pcall(function()
    self:connect()
  end)
  if not connected then
    return response_error("kill_reconnect_failed", error_text(connect_err))
  end

  local wire = self:_wire()
  local cleaned, clean_detail = wire:force_end_live_view()
  if not cleaned then
    self:set_backend_state("degraded")
    self.last_error = "PTP kill cleanup failed: " .. tostring(clean_detail or "unknown")
    self:save_session_state()
    return response_error("kill_incomplete", self.last_error)
  end

  self.live_view_active = false
  self.session_mode_live = false
  self:set_backend_state(self.transport_ready and "ready" or "degraded")
  self.last_status = "killed"
  self.last_error = ""
  self:save_session_mode("idle")
  self:save_session_state()
  debug_log("kill done; PTP line cleared")
  return self:_ok("killed", {
    liveView = false,
    commandLineCleared = true,
    ptpCleanup = "EndLiveView",
  })
end

-- Module: status (bridge contract 2-4).
function BridgeSession:status()
  debug_log("status begin")
  self:load_latest_metrics()
  if not self.live_view_active and self.wire and self.device then
    local probe_ok, probe_or_error = pcall(function()
      return self:_wire():probe_camera_state({ includeHardware = false, force = true })
    end)
    if probe_ok and type(probe_or_error) == "table" then
      self:update_probe_state(probe_or_error)
      if not probe_or_error.transportReady then
        self.last_error = error_text(probe_or_error.message ~= "" and probe_or_error.message or "PTP status probe failed")
        self:set_backend_state("degraded")
      elseif self.live_view_faulted ~= true then
        self.last_error = ""
      end
    elseif not probe_ok then
      self.transport_ready = false
      self.last_error = error_text(probe_or_error)
      self:set_backend_state("degraded")
    end
  end
  if self.live_view_active and self.transport_ready then
    self:refresh_battery(true)
  end
  local command_busy = command_lock_busy()
  local software_ready = self.transport_ready == true or self.live_view_active == true
  if self.live_view_active then
    self:set_backend_state("live")
  elseif software_ready and self.live_view_faulted ~= true then
    -- A fresh successful status probe is authoritative. Do not keep a stale
    -- degraded state after transport has demonstrably recovered.
    self:set_backend_state("ready")
  elseif self.backend_state == "recovering" or self.backend_state == "degraded" then
    self:set_backend_state(self.backend_state)
  else
    self:set_backend_state("idle")
  end
  self.last_status = (self.backend_state == "recovering" or self.backend_state == "degraded")
    and self.backend_state
    or (software_ready and "ready" or "idle")
  self:record_status_touch()
  local session_condition = session_condition_from_backend(self.backend_state, command_busy, self.transport_ready, self.live_view_active)
  if self.backend_state == "recovering" then
    debug_log("status returning recovering")
    return self:_ok("recovering", {
      liveView = self.live_view_active,
      recovering = true,
      degraded = true,
      recoveryReason = self.last_recover_reason or self.last_error or "",
      softwareReady = false,
      cameraDetected = self.hardware_detected == true or self.transport_ready == true or self.device ~= nil,
      hardwareDetected = self.hardware_detected == true,
      sessionCondition = session_condition,
    })
  end
  if self.backend_state == "degraded" then
    debug_log("status returning degraded")
    return self:_ok("degraded", {
      liveView = false,
      recovering = false,
      degraded = true,
      recoveryReason = self.last_error or self.last_recover_reason or "",
      softwareReady = false,
      cameraDetected = self.hardware_detected == true or self.device ~= nil,
      hardwareDetected = self.hardware_detected == true,
      transportReady = false,
      sessionCondition = session_condition,
    })
  end
  local battery_percent = nil
  local battery_source = nil
  local battery_measured_at_ms = 0
  if self.last_power then
    battery_percent = tonumber(self.last_power.batteryPercent)
    battery_source = self.last_power.batterySource
    battery_measured_at_ms = tonumber(self.last_power.batteryMeasuredAtMs) or 0
  end
  local status = self.live_view_active and "liveview_on" or (software_ready and "ready" or "idle")
  local request_gap_perf = perf_ring_summary(self.perf_request_gap_us)
  local stream_send_perf = perf_ring_summary(self.perf_stream_send_us)
  local wait_hook_perf = perf_ring_summary(self.perf_wait_hook_us)
  debug_log(string.format("status returning %s", status))
  return self:_ok(status, {
    liveView = self.live_view_active,
    batteryPercent = battery_percent,
    batterySource = battery_source,
    batteryMeasuredAtMs = battery_measured_at_ms,
    softwareReady = software_ready,
    cameraDetected = self.hardware_detected == true or self.transport_ready == true or self.device ~= nil,
    hardwareDetected = self.hardware_detected == true,
    sessionCondition = session_condition,
    perfRequestGapCount = request_gap_perf and request_gap_perf.count or 0,
    perfRequestGapAvgUs = request_gap_perf and request_gap_perf.avg or 0,
    perfRequestGapP50Us = request_gap_perf and request_gap_perf.p50 or 0,
    perfRequestGapP95Us = request_gap_perf and request_gap_perf.p95 or 0,
    perfRequestGapMaxUs = request_gap_perf and request_gap_perf.max or 0,
    perfStreamSendAvgUs = stream_send_perf and stream_send_perf.avg or 0,
    perfStreamSendP50Us = stream_send_perf and stream_send_perf.p50 or 0,
    perfStreamSendP95Us = stream_send_perf and stream_send_perf.p95 or 0,
    perfWaitHookAvgUs = wait_hook_perf and wait_hook_perf.avg or 0,
    perfWaitHookP50Us = wait_hook_perf and wait_hook_perf.p50 or 0,
    perfWaitHookP95Us = wait_hook_perf and wait_hook_perf.p95 or 0,
  })
end

function BridgeSession:battery_status()
  self:ensure_connected()
  local battery_percent = self:refresh_battery(true)
  if type(battery_percent) ~= "number" then
    return self:_ok("battery_unavailable", {
      batteryAvailable = false,
      batteryPercent = nil,
    })
  end
  self:save_session_state()
  return self:_ok("battery_status", {
    batteryAvailable = true,
    batteryPercent = battery_percent,
    batterySource = "ptp",
    batteryMeasuredAtMs = self.last_battery_at,
  })
end

function BridgeSession:boot()
  debug_log("boot begin")
  local ok, err = pcall(function()
    self:certify_capabilities()
  end)
  if not ok then
    self:set_backend_state("degraded")
    self.last_error = tostring(type(err) == "table" and (err.message or err.status) or err)
    debug_log(string.format("boot degraded: %s", tostring(type(err) == "table" and (err.message or err.status) or err)))
    return self:_ok("degraded", {
      liveView = self.live_view_active,
      degraded = true,
      hardwareDetected = self.hardware_detected == true,
      cameraDetected = self.hardware_detected == true or self.transport_ready == true or self.device ~= nil,
      transportReady = false,
      softwareReady = false,
    })
  end
  debug_log("boot returning status")
  return self:status()
end

function BridgeSession:auto_detect()
  debug_log("autodetect begin")
  if self.live_view_active and self.session_mode_live == true then
    debug_log("autodetect observe-only during live session")
    self:load_latest_metrics()
    return self:status()
  end
  self:load_latest_metrics()
  local wire = self:_wire()
  local hardware_detected = wire:detect_camera_hardware(STATUS_GPHOTO_TIMEOUT)
  self.hardware_detected = hardware_detected
  wire:clear_probe_cache()
  local probe = wire:probe_camera_state({ includeHardware = false })
  self:update_probe_state(probe)

  local software_ready = self.transport_ready == true or self.live_view_active == true
  if hardware_detected and software_ready then
    debug_log("autodetect ready")
    self.last_status = self.live_view_active and "liveview_on" or "ready"
    self:record_status_touch()
    self:save_session_state()
    local battery_percent = nil
    if self.transport_ready then
      battery_percent = tonumber(self:refresh_battery(true))
    end
    return self:_ok(self.live_view_active and "liveview_on" or "ready", {
      liveView = self.live_view_active,
      batteryPercent = battery_percent,
      softwareReady = true,
      hardwareDetected = true,
      cameraDetected = true,
    })
  end

  if hardware_detected then
    debug_log("autodetect degraded")
    self:set_backend_state("degraded")
    self.last_status = "degraded"
    self:record_status_touch()
    self:save_session_state()
    return self:_ok("degraded", {
      liveView = self.live_view_active,
      softwareReady = software_ready,
      hardwareDetected = true,
      cameraDetected = true,
    })
  end

  debug_log("autodetect camera missing")
  self:invalidate_session("camera_missing", "idle")
  local battery_percent = nil
  self.last_status = "idle"
  self:record_status_touch()
  return self:_ok("idle", {
    liveView = false,
    batteryPercent = battery_percent,
    softwareReady = false,
    hardwareDetected = false,
    cameraDetected = false,
  })
end

function BridgeSession:probe_props(arg)
  self:ensure_connected()
  local codes = parse_prop_code_list(arg)
  if #codes == 0 then
    return response_error("bad_request", "provide one or more property codes, for example PROBE 0xD1A2,0xD1A6")
  end
  local rows = {}
  for _, code in ipairs(codes) do
    local ok_desc, desc = pcall(function()
      return self:_wire():get_device_prop_desc(code)
    end)
    local ok_value, value = pcall(function()
      return self:_wire():get_device_prop_value(code)
    end)
    rows[#rows + 1] = string.format(
      '{"code":%d,"codeHex":"0x%04x","descPresent":%s,"descLen":%d,"descHex":"%s","valuePresent":%s,"valueLen":%d,"valueHex":"%s"}',
      code,
      code,
      ok_desc and type(desc) == "string" and #desc > 0 and "true" or "false",
      ok_desc and type(desc) == "string" and #desc or 0,
      json_escape(bytes_to_hex(ok_desc and desc or "", 32)),
      ok_value and type(value) == "string" and #value > 0 and "true" or "false",
      ok_value and type(value) == "string" and #value or 0,
      json_escape(bytes_to_hex(ok_value and value or "", 32))
    )
  end
  return "{" ..
    '"ok":true,' ..
    '"status":"probe",' ..
    '"backend":"' .. json_escape(BACKEND_NAME) .. '",' ..
    '"cameraDetected":true,' ..
    '"connected":true,' ..
    '"sessionBackend":true,' ..
    '"liveView":' .. (self.live_view_active and "true" or "false") .. ',' ..
    '"props":[' .. table.concat(rows, ",") .. ']' ..
    "}"
end

function BridgeSession:live_start()
  debug_log("live_start begin")
  self.perf_request_gap_us = nil
  self.perf_stream_send_us = nil
  self.perf_wait_hook_us = nil
  self:ensure_connected()
  local battery_percent = self:refresh_battery(true)
  if self:update_live_view_limitation(battery_percent) then
    self.live_view_active = false
    self.live_view_faulted = false
    self.live_view_fault_reason = ""
    self.last_status = "liveview_limited"
    self.last_error = ""
    self:set_backend_state("ready")
    self:save_session_mode("idle")
    self:save_session_state()
    fail("liveview_limited", "low_battery")
  end
  self.live_session_id, self.live_session_label = ensure_live_session()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  local ok, err = pcall(function()
    local wire = self:_wire()
    if not self.live_view_active and not wire.live_view_active then
      wire:start_live_view()
    end
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not ok and type(err) == "table" and err.status == "transport_error" then
    debug_log("live_start transport failed; reconnecting and retrying once: " .. error_text(err))
    local recovered, recover_err = pcall(function()
      self:recover_transport("live start transport failure")
    end)
    if recovered then
      clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
      command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
      if command_lock then
        ok, err = pcall(function()
          local wire = self:_wire()
          if not self.live_view_active and not wire.live_view_active then
            wire:start_live_view()
          end
        end)
        release_lock(COMMAND_ACTION_LOCK)
      else
        ok = false
        err = { status = "camera_busy", message = "camera command lock busy after live recovery" }
      end
    else
      err = recover_err
    end
  end
  if not ok then
    self.live_view_active = false
    self.transport_ready = false
    self.live_view_faulted = true
    self.live_view_fault_reason = error_text(err)
    self:set_backend_state("degraded")
    self.last_status = "liveview_start_failed"
    self.last_error = error_text(err)
    self:save_session_mode("idle")
    self:save_session_state()
    error(err, 0)
  end
  local live_wire = self:_wire()
  live_wire.live_view_active = true
  self.live_view_active = true
  self.transport_ready = true
  self:set_backend_state("live")
  -- Nikon can acknowledge StartLiveView while frame retrieval is still
  -- unusable (observed as 0x2002). Do not advertise a ready Live View until
  -- one fresh JPEG has crossed the complete camera-to-bridge path.
  local frame_ok = false
  local frame_err = nil
  for attempt = 1, LIVE_FIRST_FRAME_RETRY_COUNT do
    frame_ok, frame_err = pcall(function()
      self:_capture_frame(false, false, true)
    end)
    if frame_ok then break end
    debug_log(string.format("live_start first frame pending attempt=%d error=%s", attempt, error_text(frame_err)))
    sleep_ms(LIVE_FIRST_FRAME_RETRY_MS)
  end
  if not frame_ok then
    local frame_error_message = error_text(frame_err)
    debug_log("live_start first frame verification failed: " .. frame_error_message)
    local stop_ok, stop_err = pcall(function()
      live_wire:stop_live_view()
    end)
    if not stop_ok then
      debug_log("live_start cleanup failed: " .. error_text(stop_err))
    end
    live_wire.live_view_active = false
    self.live_view_active = false
    self.transport_ready = false
    self.live_view_faulted = true
    self.live_view_fault_reason = frame_error_message
    self.last_frame_at = 0
    self:set_backend_state("degraded")
    self:clear_frame_cache()
    self:purge_frame_files()
    self.last_status = "liveview_start_failed"
    self.last_error = frame_error_message
    self:save_session_mode("idle")
    self:save_session_state()
    fail("liveview_start_failed", frame_error_message)
  end
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  end
  self:record_status_touch()
  self.last_status = "liveview_on"
  self.last_error = ""
  self.live_view_faulted = false
  self.live_view_fault_reason = ""
  self:save_session_mode("live")
  self:save_session_state()
  debug_log("live_start done")
  return self:_ok("liveview_on", {
    liveView = true,
    batteryPercent = battery_percent,
  })
end

function BridgeSession:live_stop()
  debug_log("live_stop begin")
  self:ensure_connected()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  local ok, err = pcall(function()
    local wire = self:_wire()
    if self.live_view_active or wire.live_view_active then
      wire:stop_live_view()
    end
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  local camera_stop_confirmed = ok
  local stop_warning = nil
  if not camera_stop_confirmed then
    debug_log("live_stop transport failed; reconnecting once before local shutdown")
    local recovered, recover_err = pcall(function()
      self:recover_transport("live stop transport failure")
    end)
    if recovered then
      camera_stop_confirmed, err = pcall(function()
        local wire = self:_wire()
        if self.live_view_active or wire.live_view_active then
          wire:stop_live_view()
        end
      end)
    else
      err = recover_err
    end
    if not camera_stop_confirmed then
      stop_warning = tostring(type(err) == "table" and (err.message or err.status) or err)
      debug_log("live_stop camera confirmation failed; fencing local producer: " .. stop_warning)
    end
  end
  local stopped_wire = self:_wire()
  stopped_wire.live_view_active = false
  self.live_view_active = false
  clear_live_session()
  self.live_session_id = nil
  self.live_session_label = ""
  self.last_frame_at = 0
  if camera_stop_confirmed then
    local probe_ok, probe = pcall(function()
      return self:_wire():probe_camera_state({ includeHardware = false, force = true })
    end)
    if probe_ok and type(probe) == "table" then
      self:update_probe_state(probe)
    else
      self.transport_ready = false
      stop_warning = stop_warning or error_text(probe)
    end
  end
  if not camera_stop_confirmed then
    self.live_view_faulted = true
    self.live_view_fault_reason = stop_warning or "liveview_stop_unconfirmed"
  end
  self:set_backend_state(camera_stop_confirmed and self.transport_ready and "ready" or "degraded")
  self:record_status_touch()
  self:clear_frame_cache()
  self:purge_frame_files()
  self.last_status = "liveview_off"
  self.last_error = ""
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  end
  local response = self:_ok("liveview_off", {
    liveView = false,
    batteryPercent = battery_percent,
    batterySource = battery_source,
    batteryMeasuredAtMs = battery_measured_at_ms,
    cameraStopConfirmed = camera_stop_confirmed,
    stopWarning = stop_warning,
  })
  self:save_session_mode("idle")
  self:save_session_state()
  debug_log("live_stop done")
  return response
end

function BridgeSession:af()
  debug_log("af begin")
  self:ensure_connected()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  local af_response_code
  local ok, err = pcall(function()
    af_response_code = self:_wire():af_drive()
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not ok then
    error(err, 0)
  end
  self.transport_ready = true
  if self.hardware_detected then
    self:set_backend_state(self.live_view_active and "live" or "ready")
  end
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  end
  self:record_status_touch()
  self.last_status = "ok"
  self.last_error = ""
  local response = self:_ok("ok", {
    batteryPercent = battery_percent,
    afResponseCode = af_response_code,
  })
  self:save_session_state()
  debug_log("af done")
  return response
end

function BridgeSession:shutter()
  debug_log("shutter begin")
  self:ensure_connected()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  if self.shutter_priority == true then
    local ok, err = pcall(function()
      self:_wire():shutter(true, true)
    end)
    release_lock(COMMAND_ACTION_LOCK)
    if not ok then rethrow(err) end
    self.burst_shots_issued = (tonumber(self.burst_shots_issued) or 0) + 1
    self.last_frame_at = 0
    debug_log(string.format("burst shutter accepted count=%d", self.burst_shots_issued))
    return self:_ok("burst_accepted", {
      liveView = self.live_view_active,
      captureAccepted = true,
      captureVerified = false,
      burstShots = self.burst_shots_issued,
    })
  end
  -- Drain stale notifications so a previous capture cannot satisfy this one.
  pcall(function() self:_wire():get_events() end)
  local before_handle = tonumber(self.last_verified_capture_handle) or 0
  if before_handle <= 0 then
    local ok_baseline, baseline_handles = pcall(function()
      local latest = 0
      for _, storage_id in ipairs(self:_wire():get_storage_ids()) do
        for _, handle in ipairs(self:_wire():get_object_handles(storage_id, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)) do
          latest = math.max(latest, tonumber(handle) or 0)
        end
      end
      return latest
    end)
    if ok_baseline then before_handle = baseline_handles or 0 end
  end
  local should_resume_live = self.live_view_active == true
  local ok, err = pcall(function()
    -- CL/CH hold keeps the focus acquired at the first detent. Re-running AF
    -- between frames breaks the burst into short groups.
    self:_wire():shutter(self.shutter_priority == true)
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not ok and type(err) == "table" and err.status == "transport_error" then
    debug_log("AF transport failed; reconnecting and retrying once: " .. error_text(err))
    local recovered, recover_err = pcall(function()
      self:recover_transport("AF transport failure")
    end)
    if recovered then
      clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
      command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
      if command_lock then
        ok, err = pcall(function()
          af_response_code = self:_wire():af_drive()
        end)
        release_lock(COMMAND_ACTION_LOCK)
      else
        ok = false
        err = { status = "camera_busy", message = "camera command lock busy after AF recovery" }
      end
    else
      err = recover_err
    end
  end
  if not ok then
    rethrow(err)
  end
  local saved_info = self:verify_capture_saved(before_handle)
  self.last_verified_capture_handle = tonumber(saved_info.handle) or 0
  self.transport_ready = true
  if self.hardware_detected then
    self:set_backend_state(should_resume_live and "live" or "ready")
  end
  self.last_frame_at = 0
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  end
  self:record_status_touch()
  self:clear_captured_preview_cache()
  self:clear_captured_object_cache()
  self.last_status = "ok"
  self.last_error = ""
  local response = self:_ok("ok", {
    batteryPercent = battery_percent,
    liveView = should_resume_live,
    captureVerified = true,
    savedHandle = tonumber(saved_info.handle) or 0,
    savedBytes = tonumber(saved_info.compressedSize) or 0,
  })
  self:save_session_state()
  debug_log("shutter done")
  return response
end

function BridgeSession:verify_capture_saved(previous_handle)
  local deadline = now_ms() + 12000
  local baseline = tonumber(previous_handle) or 0
  local capture_complete_seen = false

  local function inspect_recent_objects()
    local candidates = {}
    local storage_ids = self:_wire():get_storage_ids()
    for _, storage_id in ipairs(storage_ids) do
      local handles = self:_wire():get_object_handles(storage_id, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
      table.sort(handles, function(a, b) return tonumber(a) < tonumber(b) end)
      local first = math.max(1, #handles - 7)
      for index = first, #handles do
        candidates[#candidates + 1] = handles[index]
      end
    end
    table.sort(candidates, function(a, b) return tonumber(a) > tonumber(b) end)
    for _, handle in ipairs(candidates) do
      local numeric_handle = tonumber(handle) or 0
      if numeric_handle > baseline then
        local ok_info, info = pcall(function() return self:_wire():get_object_info(numeric_handle) end)
        if ok_info and info and is_jpeg_format(info.formatCode)
            and (tonumber(info.compressedSize) or 0) > 0 then
          return info
        end
      end
    end
    return nil
  end

  while now_ms() < deadline do
    local events = self:_wire():get_events()
    if type(events) == "table" then
      for _, event in ipairs(events) do
        local handle = tonumber(event.parameter) or 0
        if event.code == CAPTURE_EVENT.CAPTURE_COMPLETE or event.code == CAPTURE_EVENT.CAPTURE_COMPLETE_IN_SDRAM then
          capture_complete_seen = true
        end
        if (event.code == CAPTURE_EVENT.OBJECT_ADDED or event.code == CAPTURE_EVENT.OBJECT_ADDED_IN_SDRAM) and handle > 0 then
          local ok_info, info = pcall(function() return self:_wire():get_object_info(handle) end)
          if ok_info and info and (tonumber(info.compressedSize) or 0) > 0 and handle > baseline then
            return info
          end
        end
      end
    end
    if capture_complete_seen then
      local info = inspect_recent_objects()
      if info then return info end
    end
    sleep_ms(200)
  end
  fail("capture_missing", "shutter command completed but no new image was saved to the camera card")
end

function BridgeSession:verify_burst_saved(expected_shots)
  local expected = math.max(0, tonumber(expected_shots) or 0)
  local deadline = now_ms() + 5000
  local verified = {}
  local verified_count = 0
  local latest_info = nil
  while now_ms() < deadline and verified_count < expected do
    local events = self:_wire():get_events()
    for _, event in ipairs(type(events) == "table" and events or {}) do
      local handle = tonumber(event.parameter) or 0
      if (event.code == CAPTURE_EVENT.OBJECT_ADDED
          or event.code == CAPTURE_EVENT.OBJECT_ADDED_IN_SDRAM)
          and handle > 0 and not verified[handle] then
        local ok_info, info = pcall(function()
          return self:_wire():get_object_info(handle)
        end)
        if ok_info and info and (tonumber(info.compressedSize) or 0) > 0 then
          verified[handle] = true
          verified_count = verified_count + 1
          if not latest_info or handle > (tonumber(latest_info.handle) or 0) then
            latest_info = info
          end
        end
      end
    end
    if verified_count < expected then sleep_ms(50) end
  end
  if latest_info then
    self.last_verified_capture_handle = tonumber(latest_info.handle) or 0
  end
  return verified_count, latest_info
end

function BridgeSession:raw_mode()
  debug_log("raw mode begin")
  self:ensure_connected()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  local compression_setting
  local image_size
  local ok, err = pcall(function()
    local wire = self:_wire()
    wire:device_ready()
    wire:set_device_prop_value(PROP_COMPRESSION_SETTING, string.char(COMPRESSION_RAW_WITH_FINE_JPEG))
    wire:set_device_prop_value(PROP_IMAGE_SIZE, encode_ptp_string(PREVIEW_JPEG_IMAGE_SIZE))
    sleep_ms(100)
    local payload = wire:get_device_prop_value(PROP_COMPRESSION_SETTING)
    compression_setting = payload and payload:byte(1) or nil
    local image_size_payload = wire:get_device_prop_value(PROP_IMAGE_SIZE)
    image_size = image_size_payload and select(1, read_ptp_string(image_size_payload, 1)) or nil
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not ok then
    error(err, 0)
  end
  if compression_setting ~= COMPRESSION_RAW_WITH_FINE_JPEG then
    fail("transport_error", "camera did not accept RAW + Fine JPEG compression setting")
  end
  if image_size ~= PREVIEW_JPEG_IMAGE_SIZE then
    fail("transport_error", "camera did not accept 9 MP JPEG image size")
  end
  self.transport_ready = true
  self:record_status_touch()
  self.last_status = "ok"
  self.last_error = ""
  local response = self:_ok("raw_mode", {
    compressionSetting = compression_setting,
    imageSize = image_size,
  })
  self:save_session_state()
  debug_log("raw mode done")
  return response
end

function BridgeSession:unlock()
  debug_log("unlock begin")
  self:ensure_connected()
  clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  local command_lock = acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    fail("camera_busy", "camera command lock busy")
  end
  local ok, err = pcall(function()
    self:_wire():release_camera_control()
  end)
  release_lock(COMMAND_ACTION_LOCK)
  if not ok then
    error(err, 0)
  end
  self:record_status_touch()
  self.last_status = "ok"
  self.last_error = ""
  local response = self:_ok("unlocked", {})
  self:save_session_state()
  debug_log("unlock done")
  return response
end

function BridgeSession:storage_status()
  self:ensure_connected()
  local wire = self:_wire()
  local storage_ids = wire:get_storage_ids()
  if #storage_ids == 0 then
    fail("camera_missing", "camera returned no storage")
  end
  local info = wire:get_storage_info(storage_ids[1])
  return self:_ok("storage", info)
end

MANUAL_SETTING_SPECS = {
  aperture = {
    code = PROP_FNUMBER,
    width = 2,
    allowed = { 280, 320, 350, 400, 450, 500, 560, 630, 710, 800, 900, 1000, 1100, 1300, 1400, 1600, 1800, 2000, 2200 },
  },
  shutter = {
    code = PROP_EXPOSURE_TIME,
    width = 4,
    allowed = { 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 31, 40, 50, 62, 80, 100, 125, 166, 200, 250, 333, 400, 500, 666, 769, 1000, 1250, 1666, 2000, 2500, 3333, 4000, 5000, 6250, 6666, 7692, 10000, 13000, 15000, 16000, 20000, 25000, 30000, 40000, 50000, 60000, 80000, 100000, 130000, 150000, 200000, 250000, 300000 },
  },
  iso = {
    code = PROP_EXPOSURE_INDEX,
    width = 2,
    allowed = { 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600, 51200 },
  },
}

function list_contains(values, wanted)
  for _, value in ipairs(values or {}) do
    if value == wanted then return true end
  end
  return false
end

function BridgeSession:manual_status()
  self:ensure_connected()
  local wire = self:_wire()
  local mode = u16(wire:get_device_prop_value(PROP_EXPOSURE_PROGRAM_MODE), 1)
  self.manual_mode_verified = mode == 1
  return self:_ok("manual_status", {
    liveView = self.live_view_active,
    manualMode = mode == 1,
    mode = mode,
    aperture = u16(wire:get_device_prop_value(PROP_FNUMBER), 1),
    shutter = u32(wire:get_device_prop_value(PROP_EXPOSURE_TIME), 1),
    -- 0x500F is the configurable ISO value.  Nikon's 0xD1AA is retained in
    -- capability probing, but is not promoted to an actual LCD ISO because
    -- it does not match the camera's AUTO display on this D810.
    iso = u16(wire:get_device_prop_value(PROP_EXPOSURE_INDEX), 1),
    configuredIso = u16(wire:get_device_prop_value(PROP_EXPOSURE_INDEX), 1),
    captureMode = u16(wire:get_device_prop_value(PROP_STILL_CAPTURE_MODE), 1),
    afMode = u16(wire:get_device_prop_value(PROP_AF_MODE_SELECT), 1),
    recordingMedia = (wire:get_device_prop_value(PROP_RECORDING_MEDIA) or ""):byte(1) or 0,
    autoIso = u16(wire:get_device_prop_value(PROP_AUTO_ISO), 1) == 1,
  })
end

function BridgeSession:set_manual_mode()
  self:ensure_connected()
  local wire = self:_wire()
  wire:set_device_prop_value(PROP_EXPOSURE_PROGRAM_MODE, le_u16(1))
  self.manual_mode_verified = true
  self:record_command_touch()
  return self:_ok("manual_mode_applied", {
    liveView = self.live_view_active,
    manualMode = true,
    mode = 1,
  })
end

function BridgeSession:set_control_mode(arg)
  self:ensure_connected()
  local value = tostring(arg or ""):match("^([01])$")
  if not value then
    return response_error("invalid_control_mode", "expected 0 or 1")
  end
  local response_code = self:_wire():set_control_mode(tonumber(value))
  self:record_command_touch()
  return self:_ok("control_mode_applied", {
    liveView = self.live_view_active,
    controlMode = tonumber(value),
    responseCode = response_code,
  })
end

function BridgeSession:set_auto_iso(arg)
  self:ensure_connected()
  local value = tostring(arg or ""):match("^([01])$")
  if not value then
    return response_error("invalid_auto_iso", "expected 0 or 1")
  end
  self:_wire():set_device_prop_value(PROP_AUTO_ISO, le_u16(tonumber(value)))
  self:record_command_touch()
  return self:_ok("auto_iso_applied", { enabled = value == "1" })
end

function BridgeSession:set_manual_setting(arg)
  self:ensure_connected()
  -- bridge_request appends TRACE_ID/COMMAND_ID metadata after the payload.
  -- Parse only the first token so metadata cannot make a valid setting look
  -- malformed while keeping the setting grammar strict.
  local payload = tostring(arg or ""):match("^(%S+)") or ""
  local key, raw_value = payload:match("^([a-z]+)=([0-9]+)$")
  local spec = key and MANUAL_SETTING_SPECS[key] or nil
  local value = tonumber(raw_value)
  if not spec or not value or not list_contains(spec.allowed, value) then
    return response_error("invalid_manual_setting", "unsupported M-mode setting")
  end
  if self.manual_mode_verified ~= true then
    return response_error("manual_mode_required", "set the D810 mode dial to M")
  end
  local wire = self:_wire()
  wire:set_device_prop_value(spec.code, spec.width == 2 and le_u16(value) or le_u32(value))
  self:record_command_touch()
  return self:_ok("manual_setting_applied", {
    liveView = self.live_view_active,
    key = key,
    value = value,
    manualMode = true,
  })
end

function BridgeSession:capture_events()
  self:ensure_connected()
  local events, response_code = self:_wire():get_events()
  local capture_event = false
  local capture_complete = false
  local event_code = 0
  local object_handle = 0
  local property_changed = false
  local property_code = 0
  for _, camera_event in ipairs(events) do
    local code = tonumber(camera_event.code) or 0
    local parameter = tonumber(camera_event.parameter) or 0
    self.last_camera_event_code = code
    self.last_camera_event_parameter = parameter
    debug_log(string.format("camera event code=0x%04x parameter=%d", code, parameter))
    if code == EVENT_DEVICE_PROP_CHANGED then
      property_changed = true
      property_code = parameter
    elseif code == CAPTURE_EVENT.OBJECT_ADDED or code == CAPTURE_EVENT.OBJECT_ADDED_IN_SDRAM then
      capture_event = true
      event_code = code
      object_handle = parameter
    elseif code == CAPTURE_EVENT.CAPTURE_COMPLETE or code == CAPTURE_EVENT.CAPTURE_COMPLETE_IN_SDRAM then
      capture_complete = true
      if event_code == 0 then
        event_code = code
      end
    end
  end

  local preview_ready = false
  if capture_event then
    self.last_capture_event_seq = (tonumber(self.last_capture_event_seq) or 0) + 1
    self.last_capture_event_at = now_ms()
    self.last_capture_event_code = event_code
    self.last_capture_event_handle = object_handle
    self:clear_captured_preview_cache()
    local preview_ok = pcall(function()
      self:captured_preview()
    end)
    preview_ready = preview_ok and file_exists(CAPTURED_PREVIEW_PATH)
  end

  return response_ok(capture_event and "capture_event" or "no_event", {
    captureEvent = capture_event,
    captureComplete = capture_complete,
    captureEventSeq = tonumber(self.last_capture_event_seq) or 0,
    captureEventAt = tonumber(self.last_capture_event_at) or 0,
    eventCode = tonumber(self.last_capture_event_code) or 0,
    objectHandle = tonumber(self.last_capture_event_handle) or 0,
    eventCount = #events,
    latestCameraEventCode = tonumber(self.last_camera_event_code) or 0,
    latestCameraEventParameter = tonumber(self.last_camera_event_parameter) or 0,
    eventResponseCode = tonumber(response_code) or 0,
    previewReady = preview_ready,
    propertyChanged = property_changed,
    propertyCode = property_code,
    propertyEventAt = property_changed and now_ms() or 0,
  })
end

function BridgeSession:select_latest_jpeg_object()
  self:ensure_connected()
  local wire = self:_wire()

  -- The shutter path already verified the newly-created JPEG and retained its
  -- object handle. Reusing that handle avoids another full PTP object scan
  -- when the UI requests the immediate preview after capture.
  local verified_handle = tonumber(self.last_verified_capture_handle) or 0
  if verified_handle > 0 then
    local ok_verified, verified_info = pcall(function()
      return wire:get_object_info(verified_handle)
    end)
    if ok_verified and verified_info and is_jpeg_format(verified_info.formatCode)
        and (tonumber(verified_info.compressedSize) or 0) > 0 then
      return verified_info, 1, 1
    end
  end

  local roots = {}
  local ok_all, all_handles = pcall(function()
    return wire:get_object_handles(PTP_ALL_STORAGES, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
  end)
  if ok_all and type(all_handles) == "table" and #all_handles > 0 then
    roots = all_handles
  else
    local storage_ids = wire:get_storage_ids()
    for _, storage_id in ipairs(storage_ids) do
      local storage_handles = wire:get_object_handles(storage_id, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
      for _, handle in ipairs(storage_handles) do
        roots[#roots + 1] = handle
      end
    end
  end

  if #roots == 0 then
    fail("capture_missing", "camera returned no stored objects")
  end

  local pending = {}
  for _, handle in ipairs(roots) do
    pending[#pending + 1] = handle
  end
  local visited = {}
  local scanned = 0
  while #pending > 0 do
    local handle = table.remove(pending)
    if not visited[handle] then
      visited[handle] = true
    local info = wire:get_object_info(handle)
      if info.formatCode == OBJECT_FORMAT_ASSOCIATION then
        local children = wire:get_object_handles(info.storageId, PTP_ALL_OBJECT_FORMATS, info.handle)
        for child_index = 1, #children do
          pending[#pending + 1] = children[child_index]
        end
      elseif info.formatCode ~= OBJECT_FORMAT_UNDEFINED then
        scanned = scanned + 1
        debug_log(string.format(
          "captured scan handle=%d format=0x%04x size=%d parent=%d",
          tonumber(info.handle) or 0,
          tonumber(info.formatCode) or 0,
          tonumber(info.compressedSize) or 0,
          tonumber(info.parentObject) or 0
        ))
        if is_jpeg_format(info.formatCode) then
          return info, scanned, #roots
        end
        if scanned >= CAPTURED_JPEG_SCAN_LIMIT then
          break
        end
      end
    end
  end

  fail("capture_missing", "latest jpeg object was not found")
end

function BridgeSession:select_latest_nef_object()
  self:ensure_connected()
  local wire = self:_wire()
  local storage_ids = wire:get_storage_ids()
  if #storage_ids == 0 then storage_ids = { PTP_ALL_STORAGES } end

  local best_info = nil
  local total_scanned = 0
  local total_roots = 0
  for _, storage_id in ipairs(storage_ids) do
    local ok_roots, roots = pcall(function()
      return wire:get_object_handles(storage_id, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
    end)
    if not ok_roots or type(roots) ~= "table" then
      debug_log(string.format("captured NEF scan skipped unavailable storage=%d", tonumber(storage_id) or 0))
    else
      total_roots = total_roots + #roots
      table.sort(roots, function(a, b) return tonumber(a) < tonumber(b) end)
      local pending, visited, scanned = {}, {}, 0
      for _, handle in ipairs(roots) do pending[#pending + 1] = handle end
      while #pending > 0 and scanned < CAPTURED_NEF_SCAN_LIMIT do
      local handle = table.remove(pending)
      if not visited[handle] then
        visited[handle] = true
        local ok_info, info = pcall(function()
          return wire:get_object_info(handle)
        end)
        if not ok_info then
          scanned = scanned + 1
          total_scanned = total_scanned + 1
          debug_log(string.format("captured NEF scan skipped stale handle=%d", tonumber(handle) or 0))
        elseif info.formatCode == OBJECT_FORMAT_ASSOCIATION then
          local ok_children, children = pcall(function()
            return wire:get_object_handles(info.storageId, PTP_ALL_OBJECT_FORMATS, info.handle)
          end)
          if ok_children and type(children) == "table" then
            table.sort(children, function(a, b) return tonumber(a) < tonumber(b) end)
            for _, child in ipairs(children) do pending[#pending + 1] = child end
          else
            debug_log(string.format("captured NEF scan skipped stale folder=%d", tonumber(handle) or 0))
          end
        else
          scanned = scanned + 1
          total_scanned = total_scanned + 1
          local object_name = tostring(info.filename or "")
          debug_log(string.format(
            "captured NEF scan storage=%d handle=%d format=0x%04x size=%d name=%s",
            tonumber(storage_id) or 0,
            tonumber(info.handle) or 0,
            tonumber(info.formatCode) or 0,
            tonumber(info.compressedSize) or 0,
            object_name
          ))
          local nef_by_name = object_name:upper():match("%.NEF$") ~= nil
          local nef_by_format = info.formatCode == OBJECT_FORMAT_UNDEFINED
              and (tonumber(info.compressedSize) or 0) >= CAPTURED_NEF_MIN_BYTES
          if (nef_by_name or nef_by_format)
              and (not best_info or tonumber(info.handle) > tonumber(best_info.handle)) then
            best_info = info
          end
        end
      end
      end
    end
  end
  if best_info then return best_info, total_scanned, total_roots end
  fail("capture_missing", "latest NEF object was not found")
end

function BridgeSession:clear_captured_preview_cache()
  self.last_captured_preview = nil
  self.last_captured_preview_b64 = nil
  self.last_captured_preview_meta = nil
  self.last_captured_object_handle = 0
  self.last_captured_object_info = nil
  for _, path in ipairs({
    CAPTURED_PREVIEW_PATH,
    CAPTURED_PREVIEW_META,
    CAPTURED_PREVIEW_PATH .. ".tmp",
  }) do
    pcall(function()
      os.remove(path)
    end)
  end
end

function BridgeSession:clear_captured_object_cache()
  self.last_captured_object_blob = nil
  self.last_captured_object_meta = nil
  self.last_captured_object_file_handle = 0
  for _, path in ipairs({
    CAPTURED_OBJECT_PATH,
    CAPTURED_OBJECT_META,
    CAPTURED_OBJECT_PATH .. ".tmp",
  }) do
    pcall(function()
      os.remove(path)
    end)
  end
end

function BridgeSession:write_captured_preview_cache(blob, meta)
  if type(blob) ~= "string" or #blob == 0 then
    return false
  end
  local tmp_path = CAPTURED_PREVIEW_PATH .. ".tmp"
  local ok = pcall(function()
    write_file(tmp_path, blob)
    os.rename(tmp_path, CAPTURED_PREVIEW_PATH)
  end)
  if not ok then
    pcall(function()
      os.remove(tmp_path)
    end)
    return false
  end
  write_meta_file(CAPTURED_PREVIEW_META, meta or {})
  return true
end

function BridgeSession:write_captured_object_cache(blob, meta)
  if type(blob) ~= "string" or #blob == 0 then
    return false
  end
  local tmp_path = CAPTURED_OBJECT_PATH .. ".tmp"
  local ok = pcall(function()
    write_file(tmp_path, blob)
    os.rename(tmp_path, CAPTURED_OBJECT_PATH)
  end)
  if not ok then
    pcall(function()
      os.remove(tmp_path)
    end)
    return false
  end
  write_meta_file(CAPTURED_OBJECT_META, meta or {})
  return true
end

function BridgeSession:captured_preview()
  debug_log("captured_preview begin")
  self:ensure_connected()
  local started_at = now_ms()
  local info, scanned, total_handles = self:select_latest_jpeg_object()

  if self.last_captured_object_handle == info.handle and file_exists(CAPTURED_PREVIEW_PATH) and self.last_captured_preview_meta then
    debug_log("captured_preview cached")
    self.last_metrics = self.last_captured_preview_meta
    self.last_status = "captured_ready"
    self.last_error = ""
    return self:_ok("captured_ready", self.last_captured_preview_meta)
  end

  local download_started_at = now_ms()
  local blob
  local preview_source = "thumb"
  if (tonumber(info.thumbCompressedSize) or 0) > 0 then
    local thumb_ok, thumb_blob = pcall(function()
      return self:_wire():get_thumb(info.handle)
    end)
    if thumb_ok and type(thumb_blob) == "string" and #thumb_blob > 0 then
      blob = thumb_blob
      preview_source = "thumb"
    end
  end
  if not blob then
    fail("capture_preview_unavailable", "camera thumbnail was unavailable")
  end
  if not is_jpeg_blob(blob) then
    local extracted, jpeg_err = extract_jpeg_blob(blob)
    if not extracted then
      fail("capture_failed", jpeg_err or "captured object was not a valid jpeg")
    end
    blob = extracted
  end
  local download_done_at = now_ms()
  self.last_captured_preview = blob
  self.last_captured_preview_b64 = nil
  self.last_captured_object_handle = info.handle
  self.last_captured_object_info = info
  local write_started_at = now_ms()
  local meta = {
    startedAt = started_at,
    selectDoneAt = download_started_at,
    downloadDoneAt = download_done_at,
    writeDoneAt = write_started_at,
    totalMs = write_started_at - started_at,
    queryMs = download_started_at - started_at,
    downloadMs = download_done_at - download_started_at,
    writeMs = 0,
    bytes = #blob,
    objectHandle = info.handle,
    objectFormat = info.formatCode,
    storageId = info.storageId,
    objectSize = info.compressedSize,
    thumbSize = info.thumbCompressedSize,
    thumbWidth = info.thumbWidth,
    thumbHeight = info.thumbHeight,
    objectName = info.filename or "",
    previewSource = preview_source,
    scanned = scanned,
    totalHandles = total_handles,
    cached = false,
  }
  self:write_captured_preview_cache(blob, meta)
  self.last_captured_preview_meta = meta
  self.last_metrics = meta
  self.last_status = "captured_ready"
  self.last_error = ""
  debug_log("captured_preview done")
  return self:_ok("captured_ready", meta)
end

function BridgeSession:captured_preview_bin()
  self:ensure_connected()
  if not self.last_captured_preview then
    self:captured_preview()
  end
  if not self.last_captured_preview_b64 then
    self.last_captured_preview_b64 = base64_encode(self.last_captured_preview or "")
  end
  return self.last_captured_preview_b64 or ""
end

function BridgeSession:select_captured_object_info()
  if self.last_captured_object_info
      and self.last_captured_object_handle == self.last_captured_object_info.handle
      and self.last_captured_preview_meta
      and tonumber(self.last_captured_preview_meta.objectHandle) == tonumber(self.last_captured_object_info.handle)
      and is_jpeg_format(self.last_captured_object_info.formatCode)
      and (tonumber(self.last_captured_object_info.compressedSize) or 0) > 0 then
    return self.last_captured_object_info,
      tonumber(self.last_captured_preview_meta.scanned) or 0,
      tonumber(self.last_captured_preview_meta.totalHandles) or 0,
      "preview"
  end
  local info, scanned, total_handles = self:select_latest_jpeg_object()
  return info, scanned, total_handles, "scan"
end

function BridgeSession:captured_object()
  debug_log("captured_object begin")
  self:ensure_connected()
  local started_at = now_ms()
  local info, scanned, total_handles, selection_source = self:select_captured_object_info()
  local select_done_at = now_ms()

  if self.last_captured_object_file_handle == info.handle and file_exists(CAPTURED_OBJECT_PATH) and self.last_captured_object_meta then
    self.last_metrics = self.last_captured_object_meta
    self.last_status = "captured_object_ready"
    self.last_error = ""
    return self:_ok("captured_object_ready", self.last_captured_object_meta)
  end

  local download_started_at = now_ms()
  local live_pause_started_at = download_started_at
  local was_live = self.live_view_active == true
  if was_live then
    debug_log("captured_object pausing live view for full object download")
    self:_wire():stop_live_view()
    self.live_view_active = false
    sleep_ms(CAPTURED_OBJECT_LIVE_PAUSE_MS)
  end
  local live_pause_done_at = now_ms()
  local object_wire = self:_wire()
  local previous_timeout = object_wire.timeout
  object_wire.timeout = CAPTURED_OBJECT_TIMEOUT
  local expected_size = tonumber(info.compressedSize) or 0
  local effective_chunk_size = CAPTURED_OBJECT_CHUNK_SIZE
  if expected_size > 0 and expected_size <= CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT then
    effective_chunk_size = expected_size
  end
  local tmp_path = CAPTURED_OBJECT_PATH .. ".tmp"
  pcall(function() os.remove(tmp_path) end)
  local transfer_started_at = now_ms()
  local chunk_count = 0
  local wire_ms = 0
  local file_write_ms = 0
  local flush_ms = 0
  local chunk_min_ms = nil
  local chunk_max_ms = 0
  local ok_object, bytes_or_error = pcall(function()
    if expected_size <= 0 then
      fail("capture_failed", "captured object size was unavailable")
    end
    local output, open_error = io.open(tmp_path, "wb")
    if not output then
      fail("capture_failed", open_error or "unable to open captured object temp file")
    end
    local downloaded = 0
    while downloaded < expected_size do
      local request_size = math.min(effective_chunk_size, expected_size - downloaded)
      local wire_started_at = now_ms()
      local chunk = object_wire:get_partial_object(info.handle, downloaded, request_size)
      local wire_done_at = now_ms()
      local current_wire_ms = wire_done_at - wire_started_at
      chunk_count = chunk_count + 1
      wire_ms = wire_ms + current_wire_ms
      chunk_min_ms = chunk_min_ms and math.min(chunk_min_ms, current_wire_ms) or current_wire_ms
      chunk_max_ms = math.max(chunk_max_ms, current_wire_ms)
      if type(chunk) ~= "string" or #chunk == 0 then
        output:close()
        fail("capture_failed", string.format("captured object chunk was empty at offset %d", downloaded))
      end
      local write_started_at = now_ms()
      output:write(chunk)
      file_write_ms = file_write_ms + (now_ms() - write_started_at)
      downloaded = downloaded + #chunk
      chunk = nil
      collectgarbage("collect")
    end
    local flush_started_at = now_ms()
    output:flush()
    output:close()
    flush_ms = now_ms() - flush_started_at
    return downloaded
  end)
  local transfer_done_at = now_ms()
  object_wire.timeout = previous_timeout
  local live_resume_started_at = now_ms()
  if was_live then
    local ok_resume = pcall(function()
      self:_wire():start_live_view()
    end)
    self.live_view_active = ok_resume
    debug_log("captured_object live view resume=" .. tostring(ok_resume))
  end
  local live_resume_done_at = now_ms()
  if not ok_object then
    pcall(function() os.remove(tmp_path) end)
    error(bytes_or_error, 0)
  end
  local downloaded_bytes = tonumber(bytes_or_error) or 0
  if downloaded_bytes ~= expected_size then
    pcall(function() os.remove(tmp_path) end)
    fail("capture_failed", string.format("captured object size mismatch expected=%d actual=%d", expected_size, downloaded_bytes))
  end
  local validation_started_at = now_ms()
  local completed = io.open(tmp_path, "rb")
  local jpeg_start = completed and completed:read(2) or ""
  if completed then completed:seek("end", -2) end
  local jpeg_end = completed and completed:read(2) or ""
  if completed then completed:close() end
  if jpeg_start ~= string.char(0xFF, 0xD8) or jpeg_end ~= string.char(0xFF, 0xD9) then
    pcall(function() os.remove(tmp_path) end)
    fail("capture_failed", "captured object JPEG markers were invalid")
  end
  os.rename(tmp_path, CAPTURED_OBJECT_PATH)
  local validation_done_at = now_ms()
  local download_done_at = now_ms()
  local write_started_at = now_ms()
  local meta = {
    startedAt = started_at,
    selectDoneAt = download_started_at,
    downloadDoneAt = download_done_at,
    writeDoneAt = write_started_at,
    totalMs = write_started_at - started_at,
    queryMs = select_done_at - started_at,
    downloadMs = download_done_at - download_started_at,
    livePauseMs = live_pause_done_at - live_pause_started_at,
    transferMs = transfer_done_at - transfer_started_at,
    wireMs = wire_ms,
    writeMs = file_write_ms,
    flushMs = flush_ms,
    chunkCount = chunk_count,
    chunkSize = effective_chunk_size,
    selectionSource = selection_source,
    chunkMinMs = chunk_min_ms or 0,
    chunkMaxMs = chunk_max_ms,
    chunkAvgMs = chunk_count > 0 and math.floor(wire_ms / chunk_count) or 0,
    liveResumeMs = live_resume_done_at - live_resume_started_at,
    validationMs = validation_done_at - validation_started_at,
    bytes = downloaded_bytes,
    objectHandle = info.handle,
    objectFormat = info.formatCode,
    storageId = info.storageId,
    objectSize = info.compressedSize,
    thumbSize = info.thumbCompressedSize,
    thumbWidth = info.thumbWidth,
    thumbHeight = info.thumbHeight,
    objectName = info.filename or "",
    previewSource = "object",
    scanned = scanned,
    totalHandles = total_handles,
    cached = false,
  }
  write_meta_file(CAPTURED_OBJECT_META, meta)
  self.last_captured_object_blob = nil
  self.last_captured_object_meta = meta
  self.last_captured_object_file_handle = info.handle
  self.last_metrics = meta
  self.last_status = "captured_object_ready"
  self.last_error = ""
  debug_log(string.format(
    "captured_object done total=%dms query=%dms pause=%dms transfer=%dms wire=%dms write=%dms flush=%dms resume=%dms validate=%dms chunks=%d chunk_avg=%dms chunk_max=%dms",
    meta.totalMs,
    meta.queryMs,
    meta.livePauseMs,
    meta.transferMs,
    meta.wireMs,
    meta.writeMs,
    meta.flushMs,
    meta.liveResumeMs,
    meta.validationMs,
    meta.chunkCount,
    meta.chunkAvgMs,
    meta.chunkMaxMs
  ))
  return self:_ok("captured_object_ready", meta)
end

function BridgeSession:captured_thumbnail_stream(conn, requested_handle)
  debug_log("captured_thumbnail_stream begin")
  local info = self:select_jpeg_object_by_handle(requested_handle)
  local blob = self:_wire():get_thumb(info.handle)
  if type(blob) ~= "string" or #blob == 0 then
    fail("capture_preview_unavailable", "camera thumbnail was unavailable")
  end
  if not is_jpeg_blob(blob) then
    local extracted, jpeg_err = extract_jpeg_blob(blob)
    if not extracted then
      fail("capture_failed", jpeg_err or "captured thumbnail was not a valid JPEG")
    end
    blob = extracted
  end
  conn:write(string.format("BINARY %d\n", #blob))
  conn:write(blob)
  debug_log(string.format("captured_thumbnail_stream done handle=%d bytes=%d", info.handle, #blob))
  return true
end

function BridgeSession:captured_object_stream(conn, object_kind, requested_handle)
  debug_log("captured_object_stream begin")
  self:ensure_connected()
  local started_at = now_ms()
  object_kind = object_kind or "jpeg"
  local info, scanned, total_handles, selection_source
  if object_kind == "nef" then
    info, scanned, total_handles = self:select_latest_nef_object()
    selection_source = "nef_scan"
  elseif tonumber(requested_handle) and tonumber(requested_handle) > 0 then
    info = self:select_jpeg_object_by_handle(requested_handle)
    scanned, total_handles, selection_source = 1, 1, "handle"
  else
    info, scanned, total_handles, selection_source = self:select_captured_object_info()
  end
  local select_done_at = now_ms()
  local expected_size = tonumber(info.compressedSize) or 0
  if expected_size <= 0 then
    fail("capture_failed", "captured object size was unavailable")
  end
  local effective_chunk_size = CAPTURED_OBJECT_CHUNK_SIZE
  if expected_size <= CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT then
    effective_chunk_size = expected_size
  end

  local was_live = self.live_view_active == true
  local live_pause_started_at = now_ms()
  if was_live then
    self:_wire():stop_live_view()
    self.live_view_active = false
    sleep_ms(CAPTURED_OBJECT_LIVE_PAUSE_MS)
  end
  local live_pause_done_at = now_ms()
  conn:write(string.format("BINARY %d\n", expected_size))

  local object_wire = self:_wire()
  local previous_timeout = object_wire.timeout
  object_wire.timeout = CAPTURED_OBJECT_TIMEOUT
  local transfer_started_at = now_ms()
  local downloaded = 0
  local chunk_count = 0
  local wire_ms = 0
  local socket_write_ms = 0
  local first_marker = ""
  local last_marker = ""
  local ok_object, object_error = pcall(function()
    while downloaded < expected_size do
      local request_size = math.min(effective_chunk_size, expected_size - downloaded)
      local wire_started_at = now_ms()
      local chunk = object_wire:get_partial_object(info.handle, downloaded, request_size)
      wire_ms = wire_ms + (now_ms() - wire_started_at)
      if type(chunk) ~= "string" or #chunk == 0 then
        fail("capture_failed", string.format("captured object chunk was empty at offset %d", downloaded))
      end
      if downloaded == 0 then first_marker = chunk:sub(1, 2) end
      last_marker = chunk:sub(-2)
      local write_started_at = now_ms()
      conn:write(chunk)
      socket_write_ms = socket_write_ms + (now_ms() - write_started_at)
      downloaded = downloaded + #chunk
      chunk_count = chunk_count + 1
      chunk = nil
      collectgarbage("collect")
    end
  end)
  object_wire.timeout = previous_timeout
  local transfer_done_at = now_ms()

  local stream_valid = ok_object and downloaded == expected_size
  if object_kind == "jpeg" then
    stream_valid = stream_valid
        and first_marker == string.char(0xFF, 0xD8)
        and last_marker == string.char(0xFF, 0xD9)
  end
  if stream_valid then
    -- The browser has the complete validated JPEG. Close this response before
    -- restoring live view so camera recovery does not extend image load time.
    pcall(function() conn:close() end)
  end
  local live_resume_started_at = now_ms()
  if was_live then
    local ok_resume = pcall(function() self:_wire():start_live_view() end)
    self.live_view_active = ok_resume
  end
  local live_resume_done_at = now_ms()
  if not ok_object then error(object_error, 0) end
  if downloaded ~= expected_size then
    fail("capture_failed", string.format("captured object size mismatch expected=%d actual=%d", expected_size, downloaded))
  end
  if object_kind == "jpeg"
      and (first_marker ~= string.char(0xFF, 0xD8) or last_marker ~= string.char(0xFF, 0xD9)) then
    fail("capture_failed", "captured object JPEG markers were invalid")
  end

  local done_at = now_ms()
  local meta = {
    startedAt = started_at,
    totalMs = done_at - started_at,
    queryMs = select_done_at - started_at,
    livePauseMs = live_pause_done_at - live_pause_started_at,
    transferMs = transfer_done_at - transfer_started_at,
    wireMs = wire_ms,
    writeMs = socket_write_ms,
    liveResumeMs = live_resume_done_at - live_resume_started_at,
    bytes = downloaded,
    objectHandle = info.handle,
    objectFormat = info.formatCode,
    storageId = info.storageId,
    objectSize = info.compressedSize,
    objectName = info.filename or "",
    chunkCount = chunk_count,
    chunkSize = effective_chunk_size,
    selectionSource = selection_source,
    delivery = "http_stream",
    scanned = scanned,
    totalHandles = total_handles,
    cached = false,
    objectKind = object_kind,
  }
  write_meta_file(CAPTURED_OBJECT_META, meta)
  self.last_captured_object_meta = meta
  self.last_metrics = meta
  self.last_status = "captured_object_ready"
  self.last_error = ""
  debug_log(string.format("captured_object_stream done total=%dms wire=%dms socket=%dms chunks=%d", meta.totalMs, meta.wireMs, meta.writeMs, meta.chunkCount))
  return meta
end

function BridgeSession:_capture_frame(use_cache, skip_process_locks, skip_frame_recovery, wait_hook)
  self:ensure_connected()
  if not self.live_view_active then
    fail("liveview_inactive", "live view has not been started")
  end
  local locked = skip_process_locks == true or acquire_lock(FRAME_CAPTURE_LOCK, FRAME_LOCK_TIMEOUT_MS)
  if not locked then
    fail("camera_busy", "live view capture lock timed out")
  end
  if not skip_process_locks then
    clear_lock_if_stale(COMMAND_ACTION_LOCK, LOCK_STALE_MS)
  end
  local command_lock = skip_process_locks == true or acquire_lock(COMMAND_ACTION_LOCK, FRAME_COMMAND_LOCK_TIMEOUT_MS)
  if not command_lock then
    if not skip_process_locks then release_lock(FRAME_CAPTURE_LOCK) end
    fail("camera_busy", "camera command lock busy")
  end

  local previous_frame_at = self.last_frame_at
  local previous_frame_done_us = self.last_frame_done_us
  local started_us = now_us()
  local started_at = now_ms()
  local next_frame_id = (self.frame_seq or 0) + 1
  if TRACE_FRAMES then
    debug_log(string.format("trace frame=%d ptp_start at=%.0f", next_frame_id, started_at))
  end
  local wire = self:_wire()
  local function attempt_capture()
    -- During the bounded first-frame gate, keep polling 0x9203 after Nikon
    -- accepted StartLiveView. A transient NotLiveView response clears the
    -- observed flag, but must not cause another 0x9201 transition.
    if not wire.live_view_active and not skip_frame_recovery then
      local ok_start, start_err = pcall(function()
        wire:start_live_view()
      end)
      if not ok_start then
        local status = type(start_err) == "table" and start_err.status or "capture_failed"
        local message = type(start_err) == "table" and start_err.message or tostring(start_err)
        return nil, status, message
      end
    end
    self.live_view_active = true
    local capture_start_us = now_us()
    local capture_start = now_ms()
    local frame
    local function capture_once()
      frame = wire:live_view_frame(wait_hook)
    end
    local ok_capture, err = pcall(capture_once)
    if not ok_capture then
      local status = type(err) == "table" and err.status or "capture_failed"
      local message = type(err) == "table" and err.message or tostring(err)
      return nil, status, message
    end
    if not frame or #frame <= 384 or not is_jpeg_blob(frame) then
      return nil, "capture_failed", "live view frame was not a valid jpeg"
    end
    local capture_done_us = now_us()
    local capture_done = now_ms()
    local write_done = now_ms()
    self.frame_seq = (self.frame_seq or 0) + 1
    self.last_frame = frame
    self.last_frame_at = capture_done
    self.last_frame_done_us = capture_done_us
    self.frame_failures = 0
    self:set_backend_state("live")
    self.last_metrics = {
      startedAt = started_at,
      prepMs = capture_start - started_at,
      captureStartedAt = capture_start,
      captureDoneAt = capture_done,
      writeDoneAt = write_done,
      totalMs = write_done - started_at,
      captureMs = capture_done - capture_start,
      writeMs = 0,
      bytes = #frame,
      frameId = self.frame_seq,
      requestGapMs = previous_frame_at > 0 and (started_at - previous_frame_at) or 0,
      requestGapUs = previous_frame_done_us and math.max(0, started_us - previous_frame_done_us) or 0,
      captureUs = math.max(0, capture_done_us - capture_start_us),
      cached = false,
    }
    if self.last_metrics.requestGapUs > 0 then
      perf_ring_push(self, "perf_request_gap_us", self.last_metrics.requestGapUs)
    end
    local transport_metrics = wire.last_live_transport_metrics
    if type(transport_metrics) == "table" then
      self.last_metrics.commandWriteUs = tonumber(transport_metrics.commandWriteUs) or 0
      self.last_metrics.firstPacketUs = tonumber(transport_metrics.firstPacketUs) or 0
      self.last_metrics.socketReadUs = tonumber(transport_metrics.socketReadUs) or 0
      self.last_metrics.parseUs = tonumber(transport_metrics.parseUs) or 0
      self.last_metrics.wireTotalUs = tonumber(transport_metrics.wireTotalUs) or 0
      self.last_metrics.waitHookUs = tonumber(transport_metrics.waitHookUs) or 0
      self.last_metrics.transportPackets = tonumber(transport_metrics.transportPackets) or 0
      perf_ring_push(self, "perf_wait_hook_us", self.last_metrics.waitHookUs)
    end
    if TRACE_FRAMES then
      debug_log(string.format("trace frame=%d ptp_done bytes=%d captureMs=%.0f at=%.0f", self.frame_seq, #frame, capture_done - capture_start, capture_done))
    end
    return frame
  end

  local ok, frame_or_err = pcall(function()
    local frame, status, message = attempt_capture()
    if not frame and not skip_frame_recovery then
      if status == "not_live_view" then
        sleep_ms(1000)
        pcall(function()
          wire:start_live_view()
        end)
        self.live_view_active = true
        sleep_ms(1000)
        frame, status, message = attempt_capture()
      elseif status == "capture_failed" then
        local startup_capture = (tonumber(self.frame_seq) or 0) == 0
        sleep_ms(startup_capture and LIVE_VIEW_WARMUP_MS or 20)
        pcall(function()
          wire:device_ready()
        end)
        frame, status, message = attempt_capture()
        if not frame and startup_capture then
          debug_log("first live frame unavailable; restarting camera live view once")
          pcall(function()
            wire:stop_live_view()
          end)
          sleep_ms(120)
          pcall(function()
            wire:start_live_view()
          end)
          self.live_view_active = true
          frame, status, message = attempt_capture()
        end
      end
    end
    if not frame and use_cache then
      local cached_frame, cached_meta = self:read_last_good_frame(FRAME_LAST_GOOD_GRACE_MS)
      if cached_frame and #cached_frame > 0 then
        self.last_frame = cached_frame
        self.last_frame_at = now_ms()
        self.frame_failures = 0
        self:set_backend_state("live")
        self.last_metrics = cached_meta or self.last_metrics or {}
        self.last_metrics.cached = true
        self.last_metrics.lastGood = true
        return cached_frame, self.last_metrics or {}
      end
    end
    if not frame then
      fail(status or "capture_failed", message or "live view capture failed")
    end
    return frame
  end)
  if command_lock and not skip_process_locks then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not skip_process_locks then release_lock(FRAME_CAPTURE_LOCK) end
  if not ok then
    self.frame_failures = (tonumber(self.frame_failures) or 0) + 1
    if use_cache then
      local cached_frame, cached_meta = self:read_last_good_frame(FRAME_LAST_GOOD_GRACE_MS)
      if cached_frame and #cached_frame > 0 then
        self.last_frame = cached_frame
        self.last_frame_at = now_ms()
        self.frame_failures = 0
        self:set_backend_state("live")
        self.last_metrics = cached_meta or self.last_metrics or {}
        self.last_metrics.cached = true
        self.last_metrics.lastGood = true
        return cached_frame
      end
    end
    self:set_backend_state("degraded")
    error(frame_or_err, 0)
  end
  return frame_or_err, self.last_metrics or {}
end

function BridgeSession:latest_live_frame()
  if type(self.last_frame) == "string" and #self.last_frame > 0 then
    return self.last_frame, self.last_metrics or {}
  end
  local frame, meta = self:read_cached_frame(3000)
  if frame then
    return frame, meta or self.last_metrics or {}
  end
  fail("frame_unavailable", "live session has no cached frame")
end

function BridgeSession:frame()
  debug_log("frame begin")
  local from_live_cache = self.live_view_active and self.session_mode_live == true
  local ok, frame_or_err = pcall(function()
    self:ensure_connected()
    if self.live_view_active and self.session_mode_live == true then
      return self:latest_live_frame()
    end
    return self:_capture_frame(true)
  end)
  if not ok then
    debug_log(string.format("frame failed: %s", tostring(frame_or_err)))
    error(frame_or_err, 0)
  end
  local frame = frame_or_err
  local meta = self.last_metrics or {}
  if not from_live_cache then
    self:write_frame_cache(frame, meta)
  end
  self.live_view_active = true
  self.transport_ready = true
  self:set_backend_state("live")
  self.last_status = "updated"
  self.last_error = ""
  debug_log("frame done")
  return self:_ok("updated", {
    frameBytes = #frame,
    liveView = true,
    prepMs = meta.prepMs,
    totalMs = meta.totalMs,
    captureMs = meta.captureMs,
    writeMs = meta.writeMs,
    startedAt = meta.startedAt,
    captureStartedAt = meta.captureStartedAt,
    captureDoneAt = meta.captureDoneAt,
    writeDoneAt = meta.writeDoneAt,
  })
end

function BridgeSession:frame_jpeg_direct()
  debug_log("frame_jpeg_direct begin")
  self:ensure_connected()
  if self.live_view_active and self.session_mode_live == true then
    local frame, meta = self:latest_live_frame()
    debug_log("frame_jpeg_direct cached")
    return frame, meta
  end
  local frame = self:_capture_frame(true)
  self.live_view_active = true
  self.transport_ready = true
  self:set_backend_state("live")
  self.last_status = "updated"
  self.last_error = ""
  debug_log("frame_jpeg_direct done")
  return frame, self.last_metrics or {}
end

function BridgeSession:frame_bin()
  debug_log("frame_bin begin")
  self:ensure_connected()
  if not (self.live_view_active and self.session_mode_live == true) then
    self:_capture_frame(true)
  end
  self.last_frame_b64 = base64_encode(self.last_frame or "")
  debug_log("frame_bin done")
  return self.last_frame_b64 or ""
end

function BridgeSession:frame_packet()
  debug_log("frame_packet begin")
  self:ensure_connected()
  -- Live websocket delivery must fetch a fresh camera frame every time.
  if not (self.live_view_active and self.session_mode_live == true) then
    self:_capture_frame(true)
  end
  self.last_frame_b64 = base64_encode(self.last_frame or "")
  local meta = self.last_metrics or {}
  debug_log("frame_packet done")
  return self:_ok("updated", {
    frameData = self.last_frame_b64 or "",
    frameBytes = #(self.last_frame or ""),
    liveView = true,
    prepMs = meta.prepMs,
    totalMs = meta.totalMs,
    captureMs = meta.captureMs,
    writeMs = meta.writeMs,
    startedAt = meta.startedAt,
    captureStartedAt = meta.captureStartedAt,
    captureDoneAt = meta.captureDoneAt,
    writeDoneAt = meta.writeDoneAt,
  })
end

function BridgeSession:clear_frame_cache()
  self.last_frame = nil
  self.last_frame_b64 = nil
end

function BridgeSession:write_frame_cache(frame, meta, options)
  if type(frame) ~= "string" or #frame == 0 then
    return false
  end
  options = type(options) == "table" and options or {}
  local write_last_good = options.writeLastGood ~= false
  local cache_started_at = now_ms()
  local tmp_path = self.frame_path .. ".tmp"
  local ok = pcall(function()
    write_file(tmp_path, frame)
    os.rename(tmp_path, self.frame_path)
    if write_last_good then
      write_file(FRAME_LAST_GOOD .. ".tmp", frame)
      os.rename(FRAME_LAST_GOOD .. ".tmp", FRAME_LAST_GOOD)
    end
  end)
  if not ok then
    pcall(function()
      os.remove(tmp_path)
      os.remove(FRAME_LAST_GOOD .. ".tmp")
    end)
    return false
  end
  if type(meta) == "table" then
    meta.cacheStartedAt = cache_started_at
    meta.cacheDoneAt = now_ms()
    meta.cacheMs = meta.cacheDoneAt - cache_started_at
  end
  if TRACE_FRAMES and type(meta) == "table" then
    debug_log(string.format("trace frame=%d cache_done bytes=%d cacheMs=%.0f at=%.0f", tonumber(meta.frameId) or 0, #frame, tonumber(meta.cacheMs) or 0, tonumber(meta.cacheDoneAt) or now_ms()))
  end
  write_meta(meta or {})
  return true
end

function BridgeSession:read_cached_frame(max_age_ms)
  local meta = read_meta_file(FRAME_META)
  if not path_has_size(self.frame_path) then
    return nil, nil
  end
  local capture_done_at = tonumber((meta or {}).captureDoneAt or (meta or {}).writeDoneAt or (meta or {}).startedAt or "0") or 0
  if capture_done_at <= 0 then
    return nil, meta
  end
  if max_age_ms and capture_done_at > 0 and (now_ms() - capture_done_at) > max_age_ms then
    return nil, meta
  end
  local handle = io.open(self.frame_path, "rb")
  if not handle then
    return nil, meta
  end
  local blob = handle:read("*a")
  handle:close()
  if not is_jpeg_blob(blob) then
    return nil, meta
  end
  self.last_frame = blob
  self.last_frame_at = capture_done_at > 0 and capture_done_at or self.last_frame_at
  self.last_metrics = meta or {
    cached = true,
  }
  return blob, meta
end

function BridgeSession:start_frame_refresh_worker()
  local pid = nil
  local pidfile = io.open(FRAME_REFRESH_PIDFILE, "rb")
  if pidfile then
    pid = trim(pidfile:read("*a") or "")
    pidfile:close()
  end
  if pid and pid ~= "" then
    local alive = os.execute(string.format("kill -0 %s >/dev/null 2>&1", pid))
    if alive == true or alive == 0 then
      return true
    end
  end
  pcall(function()
    os.remove(FRAME_REFRESH_PIDFILE)
  end)

  local command = string.format(
    "%s %s %s >/dev/null 2>&1 &",
    shell_quote("/bin/sh"),
    shell_quote(FRAME_REFRESH_SCRIPT),
    shell_quote("start")
  )
  local ok = os.execute(command)
  if ok ~= true and ok ~= 0 then
    debug_log("frame refresh worker failed to start")
    return false
  end
  return true
end

function BridgeSession:stop_frame_refresh_worker()
  local pidfile = io.open(FRAME_REFRESH_PIDFILE, "rb")
  if pidfile then
    local pid = trim(pidfile:read("*a") or "")
    pidfile:close()
    if pid ~= "" then
      os.execute(string.format("kill %s >/dev/null 2>&1", pid))
    end
  end
  pcall(function()
    os.remove(FRAME_REFRESH_PIDFILE)
  end)
end

function BridgeSession:capture_live_frame_background(write_cache, wait_hook)
  if self.shutter_priority == true then
    return false
  end
  if not self.live_view_active or self.session_mode_live ~= true then
    return false
  end
  local ok, err = pcall(function()
    -- The daemon loop is single-threaded and is now the sole PTP producer, so
    -- per-frame shell mkdir/rmdir locks only add process-launch latency.
    -- A failed background frame is dropped. The next refresh cycle gets a
    -- fresh frame; recovery belongs to the session/live-view transition path.
    local frame, frame_meta = self:_capture_frame(false, true, true, wait_hook)
    if write_cache ~= false then
      local write_last_good = (now_ms() - (tonumber(self.last_frame_last_good_at) or 0))
        >= LIVE_LAST_GOOD_INTERVAL_MS
      if not self:write_frame_cache(frame, frame_meta, {
        writeLastGood = write_last_good,
      }) then
        fail("transport_error", "background frame cache write failed")
      end
      self.last_frame_cache_at = now_ms()
    end
  end)
  if not ok then
    self.frame_failures = (self.frame_failures or 0) + 1
    local error_status = type(err) == "table" and err.status or "capture_failed"
    debug_log("background frame failed: " .. tostring(type(err) == "table" and (err.status or err.message) or err))
    local recover_due = (error_status == "transport_error" or error_status == "liveview_start_failed")
      and self.frame_failures >= LIVE_FRAME_TRANSPORT_RECOVER_THRESHOLD
      and (now_ms() - (tonumber(self.last_background_recover_at) or 0)) >= LIVE_FRAME_TRANSPORT_RECOVER_COOLDOWN_MS
    if recover_due then
      self.last_background_recover_at = now_ms()
      local recovered, recover_err = pcall(function()
        self:recover_transport("background live frame transport failure", true)
      end)
      if recovered then
        self.frame_failures = 0
        debug_log("background live transport recovered")
      else
        self.live_view_faulted = true
        self.live_view_fault_reason = error_text(recover_err)
        self:set_backend_state("degraded")
        self:save_session_state()
        debug_log("background live transport recovery failed: " .. tostring(type(recover_err) == "table" and (recover_err.status or recover_err.message) or recover_err))
      end
    end
    return false
  end
  self.frame_failures = 0
  return true
end

function BridgeSession:set_shutter_priority(enabled)
  enabled = enabled == true
  if enabled == self.shutter_priority then
    return self:_ok(enabled and "shutter_priority_enabled" or "shutter_priority_disabled", {
      liveView = self.live_view_active,
      shutterPriority = self.shutter_priority,
      burstShots = tonumber(self.burst_shots_issued) or 0,
      captureVerified = false,
    })
  end
  self:ensure_connected()
  local wire = self:_wire()
  local verified_count = 0
  if enabled then
    -- Pause live-frame work first and drain old events. Recording-media
    -- selection is a Live View concern; Nikon rejects this property change in
    -- camera/idle mode even though AF remains available there.
    self.shutter_priority = true
    self.burst_shots_issued = 0
    pcall(function() wire:get_events() end)
    local prepared, prepare_err = pcall(function()
      if self.live_view_active then
        wire:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(0))
      end
      wire:wait_device_ready(3000, 10)
    end)
    if not prepared then
      self.shutter_priority = false
      if self.live_view_active then
        pcall(function() wire:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(1)) end)
      end
      rethrow(prepare_err)
    end
  else
    local expected = tonumber(self.burst_shots_issued) or 0
    local finalized, finalize_err = pcall(function()
      -- OutOfFocus ends AF just as decisively as OK. Cleanup must still
      -- restore the live-view media selector even when no frame was taken.
      pcall(function() wire:wait_device_ready(5000, 10) end)
      wire.af_started_at = 0
      if self.live_view_active then
        wire:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(1))
      end
      verified_count = self:verify_burst_saved(expected)
    end)
    self.shutter_priority = false
    self:clear_captured_preview_cache()
    self:clear_captured_object_cache()
    if not finalized then rethrow(finalize_err) end
  end
  debug_log("shutter priority " .. (self.shutter_priority and "enabled" or "disabled"))
  return self:_ok(self.shutter_priority and "shutter_priority_enabled" or "shutter_priority_disabled", {
    liveView = self.live_view_active,
    shutterPriority = self.shutter_priority,
    burstShots = tonumber(self.burst_shots_issued) or 0,
    verifiedFiles = verified_count,
    captureVerified = not enabled
      and verified_count >= (tonumber(self.burst_shots_issued) or 0),
  })
end

function BridgeSession:prepare_shutter()
  self:set_shutter_priority(true)
  local af_response_code = nil
  local prepared, prepare_err = pcall(function()
    af_response_code = self:_wire():af_drive_start()
  end)
  if not prepared then
    pcall(function() self:set_shutter_priority(false) end)
    rethrow(prepare_err)
  end
  debug_log("shutter prepared with AF in flight")
  return self:_ok("shutter_prepared", {
    liveView = self.live_view_active,
    shutterPriority = true,
    afStarted = true,
    afResponseCode = af_response_code,
    captureVerified = false,
  })
end

function BridgeSession:select_jpeg_object_by_handle(handle)
  self:ensure_connected()
  handle = math.floor(tonumber(handle) or 0)
  if handle <= 0 then
    fail("capture_missing", "captured image handle was invalid")
  end
  local info = self:_wire():get_object_info(handle)
  if not info or not is_jpeg_format(info.formatCode) or (tonumber(info.compressedSize) or 0) <= 0 then
    fail("capture_missing", "captured image handle was not a JPEG")
  end
  return info
end

function BridgeSession:list_recent_jpeg_objects(requested_limit)
  self:ensure_connected()
  local wire = self:_wire()
  local limit = math.max(1, math.min(CAPTURED_BROWSER_LIST_LIMIT, math.floor(tonumber(requested_limit) or CAPTURED_BROWSER_LIST_LIMIT)))
  if self.live_view_active == true and self.session_mode_live == true then
    -- Avoid one GetObjectInfo transaction per photo while live view is running.
    -- Walk association handles only, then ask Nikon for JPEG handles in each
    -- folder. This preserves the DCIM hierarchy without inspecting every file.
    local storage_ids = { PTP_ALL_STORAGES }
    local ok_storages, detected_storages = pcall(function() return wire:get_storage_ids() end)
    if ok_storages and type(detected_storages) == "table" and #detected_storages > 0 then
      storage_ids = detected_storages
    end
    local folders, images, visited = {}, {}, {}
    for _, storage_id in ipairs(storage_ids) do
      local ok_roots, roots = pcall(function()
        return wire:get_object_handles(storage_id, OBJECT_FORMAT_ASSOCIATION, PTP_ROOT_PARENT)
      end)
      if ok_roots and type(roots) == "table" then
        for _, handle in ipairs(roots) do
          folders[#folders + 1] = { storageId = storage_id, handle = handle }
        end
      end
    end
    local folder_count = 0
    while #folders > 0 and folder_count < 128 do
      local folder = table.remove(folders)
      if not visited[folder.handle] then
        visited[folder.handle] = true
        folder_count = folder_count + 1
        local ok_jpegs, jpeg_handles = pcall(function()
          return wire:get_object_handles(folder.storageId, OBJECT_FORMAT_EXIF_JPEG, folder.handle)
        end)
        if ok_jpegs and type(jpeg_handles) == "table" then
          for _, handle in ipairs(jpeg_handles) do images[#images + 1] = { handle = tonumber(handle) or 0 } end
        end
        local ok_children, child_folders = pcall(function()
          return wire:get_object_handles(folder.storageId, OBJECT_FORMAT_ASSOCIATION, folder.handle)
        end)
        if ok_children and type(child_folders) == "table" then
          for _, handle in ipairs(child_folders) do
            folders[#folders + 1] = { storageId = folder.storageId, handle = handle }
          end
        end
      end
    end
    table.sort(images, function(a, b) return tonumber(a.handle) > tonumber(b.handle) end)
    while #images > limit do table.remove(images) end
    return images, #images, folder_count
  end
  local roots = {}
  -- Enumerate each storage explicitly. Nikon can return a short aggregate
  -- root list for PTP_ALL_STORAGES even when the card contains more folders.
  local ok_storages, storage_ids = pcall(function() return wire:get_storage_ids() end)
  if ok_storages and type(storage_ids) == "table" then
    for _, storage_id in ipairs(storage_ids) do
      local ok_roots, handles = pcall(function()
        return wire:get_object_handles(storage_id, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
      end)
      if ok_roots and type(handles) == "table" then
        for _, handle in ipairs(handles) do roots[#roots + 1] = handle end
      end
    end
  end
  if #roots == 0 then
    local ok_all, all_handles = pcall(function()
      return wire:get_object_handles(PTP_ALL_STORAGES, PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)
    end)
    if ok_all and type(all_handles) == "table" then roots = all_handles end
  end
  table.sort(roots, function(a, b) return tonumber(a) < tonumber(b) end)
  local pending, visited, images = {}, {}, {}
  for _, handle in ipairs(roots) do pending[#pending + 1] = handle end
  local scanned = 0
  while #pending > 0 and scanned < CAPTURED_BROWSER_SCAN_LIMIT and #images < limit do
    local handle = table.remove(pending)
    if not visited[handle] then
      visited[handle] = true
      local ok_info, info = pcall(function() return wire:get_object_info(handle) end)
      if ok_info and info then
        if info.formatCode == OBJECT_FORMAT_ASSOCIATION then
          -- Do not depend on Nikon's format-filtered handle response. Some
          -- firmware/transport paths return only a short window of JPEG
          -- handles (observed as exactly 24). Walk every child and classify
          -- it from GetObjectInfo instead.
          local ok_children, children = pcall(function()
            return wire:get_object_handles(info.storageId, PTP_ALL_OBJECT_FORMATS, info.handle)
          end)
          if ok_children and type(children) == "table" then
            for _, child in ipairs(children) do pending[#pending + 1] = child end
          end
        elseif info.formatCode ~= OBJECT_FORMAT_UNDEFINED then
          scanned = scanned + 1
          if is_jpeg_format(info.formatCode) then
            images[#images + 1] = { handle = tonumber(info.handle) or 0 }
          end
        end
      else
        scanned = scanned + 1
      end
    end
  end
  table.sort(images, function(a, b) return tonumber(a.handle) > tonumber(b.handle) end)
  while #images > limit do
    table.remove(images)
  end
  return images, scanned, #roots
end

function BridgeSession:captured_images(requested_limit)
  local images, scanned, total_handles = self:list_recent_jpeg_objects(requested_limit)
  local encoded = {}
  for _, info in ipairs(images) do
    encoded[#encoded + 1] = string.format(
      '{"handle":%d}',
      tonumber(info.handle) or 0
    )
  end
  return string.format(
    '{"ok":true,"status":"captured_images_ready","sessionId":%d,"count":%d,"scanned":%d,"totalHandles":%d,"images":[%s]}',
    tonumber(current_session_id()) or 0,
    #images,
    scanned,
    total_handles,
    table.concat(encoded, ",")
  )
end

function BridgeSession:live_frame_failure_backoff_ms()
  local failures = math.max(0, tonumber(self.frame_failures) or 0)
  if failures <= 0 then
    return 0
  end
  return math.min(
    LIVE_FRAME_FAILURE_BACKOFF_MAX_MS,
    LIVE_FRAME_FAILURE_BACKOFF_BASE_MS * failures
  )
end

function BridgeSession:purge_frame_files()
  for _, path in ipairs({
    self.frame_path,
    FRAME_LAST_GOOD,
    FRAME_META,
    CAPTURED_PREVIEW_PATH,
    CAPTURED_PREVIEW_META,
    CAPTURED_OBJECT_PATH,
    CAPTURED_OBJECT_META,
    self.frame_path .. ".tmp",
    FRAME_LAST_GOOD .. ".tmp",
    CAPTURED_PREVIEW_PATH .. ".tmp",
    CAPTURED_OBJECT_PATH .. ".tmp",
  }) do
    pcall(function()
      os.remove(path)
    end)
  end
end

-- Module: entry/router (bridge contract 2-9).
function BridgeSession:handle(command)
  command = trim(command)
  debug_log(string.format("handle raw=%s", command))
  local verb, arg = command:match("^(%S+)%s*(.*)$")
  verb = string.upper(trim(verb or ""))
  arg = trim(arg or "")
  debug_log(string.format("handle verb=%s arg=%s", verb, arg))
  if verb == "" or verb == "PING" then
    return response_ok("pong", { backend = BACKEND_NAME, sessionBackend = true, backendState = self.backend_state or "idle" })
  elseif verb == "BOOT" then
    return self:boot()
  elseif verb == "STATUS" then
    return self:status()
  elseif verb == "AUTODETECT" then
    return self:auto_detect()
  elseif verb == "LIVE_START" then
    return self:live_start()
  elseif verb == "LIVE_STOP" then
    return self:live_stop()
  elseif verb == "AF" then
    return self:af()
  elseif verb == "SHUTTER_PREPARE" then
    return self:prepare_shutter()
  elseif verb == "SHUTTER" then
    return self:shutter()
  elseif verb == "SHUTTER_HOLD_BEGIN" then
    return self:set_shutter_priority(true)
  elseif verb == "SHUTTER_HOLD_END" then
    return self:set_shutter_priority(false)
  elseif verb == "RAW_MODE" then
    return self:raw_mode()
  elseif verb == "UNLOCK" then
    return self:unlock()
  elseif verb == "STORAGE" then
    return self:storage_status()
  elseif verb == "BATTERY_STATUS" then
    return self:battery_status()
  elseif verb == "CAPTURE_EVENTS" then
    return self:capture_events()
  elseif verb == "FRAME" then
    return self:frame()
  elseif verb == "FRAME_BIN" then
    return self:frame_bin()
  elseif verb == "FRAME_PACKET" then
    return self:frame_packet()
  elseif verb == "CAPTURED_JPEG" then
    return self:captured_preview()
  elseif verb == "CAPTURED_JPEG_BIN" then
    return self:captured_preview_bin()
  elseif verb == "CAPTURED_OBJECT" then
    return self:captured_object()
  elseif verb == "CAPTURED_IMAGES" then
    return self:captured_images(arg)
  elseif verb == "RECOVER" then
    return self:recover()
  elseif verb == "KILL" then
    return self:kill(arg ~= "" and arg or "user kill")
  elseif verb == "RESET" then
    return self:reset_session(arg)
  elseif verb == "RELOAD_SESSION" then
    return self:reload_command_session(arg)
  elseif verb == "MAINTAIN" then
    return self:maintain()
  elseif verb == "PROBE" then
    return self:probe_props(arg)
  elseif verb == "MANUAL_STATUS" then
    return self:manual_status()
  elseif verb == "CONTROL_MODE" then
    return self:set_control_mode(arg)
  elseif verb == "SET_MANUAL_MODE" then
    return self:set_manual_mode()
  elseif verb == "SET_AUTO_ISO" then
    return self:set_auto_iso(arg)
  elseif verb == "SET_M" then
    return self:set_manual_setting(arg)
  elseif verb == "STOP" then
    return self:shutdown()
  end
  debug_log(string.format("handle unknown=%s", command))
  return response_error("unknown", "unknown command: " .. command)
end

-- Module: entry/router (bridge contract 2-9).
local function stream_u32be(value)
  value = tonumber(value) or 0
  return string.char(math.floor(value / 16777216) % 256, math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
end

local function stream_packet_header(length, frame_id)
  return stream_u32be(length) .. stream_u32be(frame_id)
end

function stream_u64be(value)
  value = math.max(0, tonumber(value) or 0)
  local high = math.floor(value / 4294967296)
  local low = value - high * 4294967296
  return stream_u32be(high) .. stream_u32be(low)
end

function stream_meta_binary(meta)
  meta = type(meta) == "table" and meta or {}
  return "D8L5"
    .. stream_u32be(52)
    .. stream_u32be(meta.frameId)
    .. stream_u64be(meta.startedAt)
    .. stream_u64be(meta.captureDoneAt)
    .. stream_u32be(meta.totalMs)
    .. stream_u32be(meta.captureMs)
    .. stream_u32be(meta.bytes)
    .. stream_u32be(meta.wireTotalUs)
    .. stream_u32be(meta.firstPacketUs)
    .. stream_u32be(meta.parseUs)
end

local function stream_broadcast(clients, frame, meta)
  if type(frame) ~= "string" or #frame == 0 then return 0 end
  local send_started_us = now_us()
  local frame_id = tonumber(type(meta) == "table" and meta.frameId or 0) or 0
  local meta_binary = stream_meta_binary(meta)
  local prefix = stream_packet_header(4 + #meta_binary + #frame, frame_id)
    .. stream_u32be(#meta_binary)
    .. meta_binary
  if TRACE_FRAMES then
    debug_log(string.format("trace frame=%d stream_send bytes=%d clients=%d at=%.0f", frame_id, #frame, #clients, now_ms()))
  end
  for i = #clients, 1, -1 do
    local ok, wrote_prefix, wrote_frame, send_err = pcall(function()
      local prefix_ok, prefix_err = clients[i]:write(prefix)
      if not prefix_ok then return false, false, prefix_err end
      local frame_ok, frame_err = clients[i]:write(frame)
      return true, frame_ok, frame_err
    end)
    if not ok or not wrote_prefix or not wrote_frame then
      debug_log(string.format(
        "direct stream client removed frame=%d stage=%s error=%s",
        frame_id,
        wrote_prefix and "frame" or "prefix",
        tostring(send_err or (not ok and wrote_prefix) or "write failed")
      ))
      pcall(function() clients[i]:close() end)
      table.remove(clients, i)
    end
  end
  return #clients, math.max(0, now_us() - send_started_us)
end

function stream_close_all(clients)
  for i = #clients, 1, -1 do
    pcall(function() clients[i]:close() end)
    table.remove(clients, i)
  end
end

local function start_server()
  local server, err = socket.listen_tcp(BRIDGE_HOST, BRIDGE_PORT, {
    reuseaddr = true,
    tcp_nodelay = true,
    backlog = 16,
  })
  if not server then
    fail("transport_error", err or "bridge listen failed")
  end
  local stream_server
  if os.getenv("D810D_DISABLE_DIRECT_STREAM") ~= "1" then
    stream_server = socket.listen_tcp(STREAM_HOST, STREAM_PORT, {
      reuseaddr = true,
      tcp_nodelay = true,
      nonblocking_clients = true,
      backlog = 4,
    })
  end
  io.stderr:write(string.format("bridge listening on %s:%d\n", BRIDGE_HOST, BRIDGE_PORT))
  local session = BridgeSession.new(DDSERVER_HOST, DDSERVER_PORT, FRAME_PATH)
  local running = true
  local stream_clients = {}
  local pending_frame = nil
  local pending_meta = nil
  local pending_cache_due = false
  local live_capture_failed = false
  local last_health_publish_at = 0

  local function publish_health(force)
    local observed_at = now_ms()
    if not force and (observed_at - last_health_publish_at) < BRIDGE_HEALTH_INTERVAL_MS then
      return
    end
    local backend_state = tostring(session.backend_state or "idle")
    local readiness = session:update_readiness({
      backendState = backend_state,
      transportReady = session.transport_ready == true,
      hardwareDetected = session.hardware_detected == true,
      cameraDetected = session.hardware_detected == true or session.device ~= nil,
      liveView = session.live_view_active == true,
      softwareReady = session.transport_ready == true or session.live_view_active == true,
      frameAgeMs = session:frame_age_ms(),
    })
    local healthy = session.transport_ready == true
      and session.hardware_detected == true
      and (backend_state == "ready" or backend_state == "live")
      and (session.live_view_active ~= true or (tonumber(session.frame_failures) or 0) == 0)
    local pid_text = select(1, read_file(BRIDGE_PIDFILE)) or ""
    write_state_file(BRIDGE_HEALTH_PATH, {
      component = "bridge",
      state = healthy and "healthy" or "unhealthy",
      pid = trim(pid_text),
      observedAtMs = tostring(observed_at),
      expiresAtSec = tostring(math.floor(observed_at / 1000) + BRIDGE_HEALTH_TTL_SEC),
      backendState = backend_state,
      transportReady = session.transport_ready == true and "true" or "false",
      hardwareDetected = session.hardware_detected == true and "true" or "false",
      liveView = session.live_view_active == true and "true" or "false",
      frameFailures = tostring(tonumber(session.frame_failures) or 0),
      appReady = readiness.appReady and "true" or "false",
      readinessState = readiness.readinessState,
      readinessReason = readiness.readinessReason,
      readyAfterMs = tostring(readiness.readyAfterMs or 0),
      readinessAverageMs = tostring(readiness.readinessAverageMs or 0),
      readinessMaxMs = tostring(readiness.readinessMaxMs or 0),
      liveViewReady = readiness.liveViewReady and "true" or "false",
      commandReady = readiness.commandReady and "true" or "false",
    })
    last_health_publish_at = observed_at
  end

  publish_health(true)

  local function deliver_pending_frame()
    if type(pending_frame) ~= "string" or #pending_frame == 0 then
      return
    end
    local frame = pending_frame
    local meta = pending_meta or {}
    local cache_due = pending_cache_due
    -- Clear first so a retry/recovery path cannot deliver the same frame twice.
    pending_frame = nil
    pending_meta = nil
    pending_cache_due = false

    local _, stream_send_us = stream_broadcast(stream_clients, frame, meta)
    meta.streamSendUs = stream_send_us or 0
    perf_ring_push(session, "perf_stream_send_us", meta.streamSendUs)
    if cache_due then
      local cache_started_us = now_us()
      local write_last_good = (now_ms() - (tonumber(session.last_frame_last_good_at) or 0))
        >= LIVE_LAST_GOOD_INTERVAL_MS
      if session:write_frame_cache(frame, meta, {
        writeLastGood = write_last_good,
      }) then
        session.last_frame_cache_at = now_ms()
      end
      meta.cacheWriteUs = math.max(0, now_us() - cache_started_us)
    else
      meta.cacheWriteUs = 0
    end
  end

  while running do
    publish_health(false)
    local stream_accept_started_us = now_us()
    if stream_server then
      while true do
        local client = stream_server:accept()
        if not client then break end
        stream_clients[#stream_clients + 1] = client
        debug_log(string.format("direct stream client accepted count=%d", #stream_clients))
      end
    end
    local stream_accept_us = math.max(0, now_us() - stream_accept_started_us)
    if session.live_view_active and session.session_mode_live == true
        and session.shutter_priority ~= true then
      local last_cache_activity_at = math.max(
        tonumber(session.last_frame_cache_at) or 0,
        tonumber(session.last_frame_cache_queued_at) or 0
      )
      local cache_due = #stream_clients == 0
        or (now_ms() - last_cache_activity_at) >= LIVE_FRAME_CACHE_INTERVAL_MS
      -- Start the next 0x9203 transaction first. While ddserver/the camera
      -- prepares that response, deliver and cache the previous frame.
      local captured = session:capture_live_frame_background(false, deliver_pending_frame)
      live_capture_failed = not captured
      if captured and session.last_frame then
        session.last_metrics.streamAcceptUs = stream_accept_us
        pending_frame = session.last_frame
        pending_meta = session.last_metrics
        pending_cache_due = cache_due
        if cache_due then
          session.last_frame_cache_queued_at = now_ms()
        end
      end
    elseif session.shutter_priority == true then
      live_capture_failed = false
      deliver_pending_frame()
      sleep_ms(10)
    elseif #stream_clients > 0 then
      live_capture_failed = false
      deliver_pending_frame()
      stream_close_all(stream_clients)
    else
      live_capture_failed = false
    end
    local command_accept_started_us = now_us()
    local conn = server:accept()
    if session.last_metrics then
      session.last_metrics.commandAcceptUs = math.max(0, now_us() - command_accept_started_us)
    end
    if conn then
      while running do
        local line = conn:readuntil("\n")
        if not line then
          break
        end
        local command = trim(line or "")
        local command_name = string.upper((command:match("^(%S+)") or ""))
        debug_log(string.format("daemon received command=%s", command))
        if command_name ~= "" and command_name ~= "PING" and command_name ~= "STATUS" and command_name ~= "PROBE" and command_name ~= "MAINTAIN" then
          session:record_command_touch()
        end
        if command == "FRAME_STORE" then
          local ok, result = pcall(function()
            local frame, frame_meta = session:frame_jpeg_direct()
            if not (session.live_view_active and session.session_mode_live == true) and not session:write_frame_cache(frame, frame_meta) then
              fail("transport_error", "frame cache write failed")
            end
            session:save_session_mode("live")
            session:save_session_state()
            return response_ok("updated", {
              backend = BACKEND_NAME,
              sessionBackend = true,
              liveView = true,
              frameBytes = #frame,
              savedTo = FRAME_PATH,
              backendState = session.backend_state or "live",
            })
          end)
          if ok then
            conn:write(result .. "\n")
          elseif type(result) == "table" then
            conn:write(response_error(result.status or "transport_error", result.message or "") .. "\n")
          else
            conn:write(response_error("transport_error", tostring(result)) .. "\n")
          end
          break
        end
        if command == "RESET" then
          local ok, result = pcall(function()
            return session:reset_session("ui refresh")
          end)
          if ok then
            conn:write(result .. "\n")
          elseif type(result) == "table" then
            conn:write(response_error(result.status or "transport_error", result.message or "") .. "\n")
          else
            conn:write(response_error("transport_error", tostring(result)) .. "\n")
          end
          break
        end
        if command == "FRAME_JPEG" then
          local ok, frame_or_err, meta = pcall(function()
            local frame, frame_meta = session:frame_jpeg_direct()
            return frame, frame_meta
          end)
          if ok and type(frame_or_err) == "string" and #frame_or_err > 0 then
            local frame = frame_or_err
            meta = meta or {}
            conn:write(string.format(
              "BINARY %d %s %s %s %s %s %s %s %s\n",
              #frame,
              tostring(meta.startedAt or ""),
              tostring(meta.prepMs or ""),
              tostring(meta.captureStartedAt or ""),
              tostring(meta.captureDoneAt or ""),
              tostring(meta.writeDoneAt or ""),
              tostring(meta.totalMs or ""),
              tostring(meta.captureMs or ""),
              tostring(meta.writeMs or "")
            ))
            conn:write(frame)
          else
            local response
            if ok then
              response = response_error("frame_empty", "empty frame")
            elseif type(frame_or_err) == "table" then
              response = response_error(frame_or_err.status or "transport_error", frame_or_err.message or "")
            else
              response = response_error("transport_error", tostring(frame_or_err))
            end
            conn:write(response .. "\n")
          end
          break
        end
        if command_name == "CAPTURED_THUMB" then
          local requested_handle = tonumber(command:match("^%S+%s+(%d+)$") or "")
          local ok, result = pcall(function()
            return session:captured_thumbnail_stream(conn, requested_handle)
          end)
          if not ok then
            debug_log("captured thumbnail stream failed: " .. tostring(type(result) == "table" and (result.message or result.status) or result))
          end
          break
        end
        if command_name == "CAPTURED_OBJECT_JPEG" then
          local requested_handle = tonumber(command:match("^%S+%s+(%d+)$") or "")
          local binary_started = false
          local ok, result = pcall(function()
            binary_started = true
            return session:captured_object_stream(conn, "jpeg", requested_handle)
          end)
          if not ok and not binary_started then
            if type(result) == "table" then
              conn:write(response_error(result.status or "transport_error", result.message or "") .. "\n")
            else
              conn:write(response_error("transport_error", tostring(result)) .. "\n")
            end
          elseif not ok then
            debug_log("captured object stream failed after binary start: " .. tostring(result))
          end
          break
        end
        if command == "CAPTURED_OBJECT_NEF" then
          local binary_started = false
          local ok, result = pcall(function()
            binary_started = true
            return session:captured_object_stream(conn, "nef")
          end)
          if not ok and not binary_started then
            if type(result) == "table" then
              conn:write(response_error(result.status or "transport_error", result.message or "") .. "\n")
            else
              conn:write(response_error("transport_error", tostring(result)) .. "\n")
            end
          elseif not ok then
            debug_log("captured NEF stream failed after binary start: " .. tostring(result))
          end
          break
        end
        local response
        local ok, result = pcall(function()
          return session:handle(command)
        end)
        if ok then
          response = result
        else
          session:record_capability_failure(command_name, result)
          if type(result) == "table" then
            response = response_error(result.status or "transport_error", result.message or "")
          else
            response = response_error("transport_error", tostring(result))
          end
        end
        conn:write(response .. "\n")
        if response:find('"status":"stopping"', 1, true) then
          running = false
          break
        end
      end
      conn:close()
    elseif live_capture_failed then
      -- Failed 0x9203 requests must not spin at camera speed.  Poll commands
      -- first, then back off so LIVE_STOP/RESET remain responsive and failed
      -- helper processes cannot accumulate without bound.
      sleep_ms(session:live_frame_failure_backoff_ms())
    elseif not (session.live_view_active and session.session_mode_live == true and #stream_clients > 0) then
      sleep_ms(2)
    end
  end

  deliver_pending_frame()
  pcall(function() os.remove(BRIDGE_HEALTH_PATH) end)
  session:close()
  server:close()
  if stream_server then stream_server:close() end
end

local mode = arg[1] or "daemon"
if mode == "daemon" then
  local ok, err = pcall(start_server)
  if not ok then
    if type(err) == "table" then
      io.stderr:write(string.format("[d810bridge] %s: %s\n", tostring(err.status or "transport_error"), tostring(err.message or "unknown")))
    else
      io.stderr:write(string.format("[d810bridge] %s\n", tostring(err)))
    end
    os.exit(1)
  end
else
  local command = tostring(mode or ""):upper():gsub("%-", "_")
  local command_map = {
    PING = "PING",
    STATUS = "STATUS",
    AUTODETECT = "AUTODETECT",
    LIVE_START = "LIVE_START",
    LIVE_STOP = "LIVE_STOP",
    AF = "AF",
    SHUTTER = "SHUTTER",
    RAW_MODE = "RAW_MODE",
    UNLOCK = "UNLOCK",
    STORAGE = "STORAGE",
    BATTERY_STATUS = "BATTERY_STATUS",
    FRAME = "FRAME",
    FRAME_STORE = "FRAME_STORE",
    FRAME_BIN = "FRAME_BIN",
    FRAME_PACKET = "FRAME_PACKET",
    CAPTURED_JPEG = "CAPTURED_JPEG",
    CAPTURED_JPEG_BIN = "CAPTURED_JPEG_BIN",
    CAPTURED_OBJECT = "CAPTURED_OBJECT",
    RECOVER = "RECOVER",
    KILL = "KILL",
    RESET = "RESET",
    MAINTAIN = "MAINTAIN",
    PROBE = "PROBE",
    STOP = "STOP",
  }
  local mapped = command_map[command]
  if mapped then
    local session = BridgeSession.new(DDSERVER_HOST, DDSERVER_PORT, FRAME_PATH)
    local ok, result = pcall(function()
      if mapped == "FRAME_STORE" then
        local frame, frame_meta = session:frame_jpeg_direct()
        if not session:write_frame_cache(frame, frame_meta) then
          fail("transport_error", "frame cache write failed")
        end
        session:save_session_mode("live")
        session:save_session_state()
        return response_ok("updated", {
          backend = BACKEND_NAME,
          sessionBackend = true,
          liveView = true,
          frameBytes = #frame,
          savedTo = FRAME_PATH,
          backendState = session.backend_state or "live",
        })
      end
      if mapped == "PROBE" then
        return session:handle(mapped .. " " .. tostring(arg[2] or ""))
      end
      return session:handle(mapped)
    end)
    session:close()
    if ok then
      io.write(result .. "\n")
    elseif type(result) == "table" then
      io.write(response_error(result.status or "transport_error", result.message or "") .. "\n")
    else
      io.write(response_error("transport_error", tostring(result)) .. "\n")
    end
  else
    io.write(response_error("unknown", "unknown mode: " .. tostring(mode)) .. "\n")
  end
end
