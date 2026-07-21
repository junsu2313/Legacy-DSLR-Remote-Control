#!/usr/bin/lua

local now_ms
local socket
local nixio_mod
local read_battery_cache
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
          local ok, err = send(tcp, data:sub(sent + 1))
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
local function session_path(name, fallback)
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
local FRAME_META = os.getenv("D810D_FRAME_META") or session_path("frame.meta", "/tmp/d810-live.meta")
local CAPTURED_PREVIEW_META = os.getenv("D810D_CAPTURED_PREVIEW_META") or session_path("captured-preview.meta", "/tmp/d810-captured-preview.meta")
local CAPTURED_OBJECT_META = os.getenv("D810D_CAPTURED_OBJECT_META") or session_path("captured-object.meta", "/tmp/d810-captured-object.meta")
local FRAME_REFRESH_PIDFILE = os.getenv("D810D_FRAME_REFRESH_PIDFILE") or "/tmp/d810-live-refresh.pid"
local FRAME_CAPTURE_LOCK = os.getenv("D810D_FRAME_CAPTURE_LOCK") or "/tmp/d810-live.lock"
local COMMAND_ACTION_LOCK = os.getenv("D810D_COMMAND_ACTION_LOCK") or "/tmp/d810-command.lock"
local BRIDGE_PIDFILE = os.getenv("BRIDGE_PIDFILE") or "/tmp/d810-bridge.pid"
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
local BATTERY_CACHE_PATH = os.getenv("D810D_BATTERY_CACHE") or "/tmp/d810-battery.cache"
local GPHOTO_DETECT_TIMEOUT = tonumber(os.getenv("D810D_GPHOTO_DETECT_TIMEOUT") or "6") or 6
local GPHOTO_DETECT_MODEL = os.getenv("D810D_GPHOTO_DETECT_MODEL") or "Nikon DSC D810"
local PROBE_CACHE_TTL_MS = tonumber(os.getenv("D810D_PROBE_CACHE_TTL_MS") or "2500") or 2500
local STATUS_ACTION_TIMEOUT = tonumber(os.getenv("D810D_STATUS_ACTION_TIMEOUT") or "3") or 3
local STATUS_GPHOTO_TIMEOUT = tonumber(os.getenv("D810D_STATUS_GPHOTO_TIMEOUT") or "3") or 3
local DDSERVER_INIT = os.getenv("D810D_DDSERVER_INIT") or "/etc/init.d/ddserver"
local DDSERVER_RECOVER_TIMEOUT = tonumber(os.getenv("D810D_DDSERVER_RECOVER_TIMEOUT") or "10") or 10
local FRAME_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_FRAME_LOCK_TIMEOUT_MS") or "220") or 220
local FRAME_LOCK_WAIT_MS = tonumber(os.getenv("D810D_FRAME_LOCK_WAIT_MS") or "120") or 120
local COMMAND_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_COMMAND_LOCK_TIMEOUT_MS") or "1200") or 1200
local FRAME_COMMAND_LOCK_TIMEOUT_MS = tonumber(os.getenv("D810D_FRAME_COMMAND_LOCK_TIMEOUT_MS") or "80") or 80
local LOCK_STALE_MS = tonumber(os.getenv("D810D_LOCK_STALE_MS") or "4000") or 4000
local FRAME_STABLE_AGE_MS = tonumber(os.getenv("D810D_FRAME_STABLE_AGE_MS") or "0") or 0
local STATUS_CACHE_TTL_MS = tonumber(os.getenv("D810D_STATUS_CACHE_TTL_MS") or "350") or 350
local BATTERY_CACHE_TTL_MS = tonumber(os.getenv("D810D_BATTERY_CACHE_TTL_MS") or "30000") or 30000
local CONNECT_RETRY_DELAY_MS = tonumber(os.getenv("D810D_CONNECT_RETRY_DELAY_MS") or "3000") or 3000
local SESSION_STALE_MS = tonumber(os.getenv("D810D_SESSION_STALE_MS") or "1500") or 1500
local TRACE_FRAMES = tostring(os.getenv("D810D_TRACE_FRAMES") or "0") == "1"
local FRAME_HEALTH_STALE_MS = tonumber(os.getenv("D810D_FRAME_HEALTH_STALE_MS") or "800") or 800
local FRAME_LAST_GOOD_GRACE_MS = tonumber(os.getenv("D810D_FRAME_LAST_GOOD_GRACE_MS") or "2500") or 2500
local LIVE_VIEW_WARMUP_MS = tonumber(os.getenv("D810D_LIVE_VIEW_WARMUP_MS") or "220") or 220
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

local PROP_LIVE_VIEW_STATUS = 0xD1A2
local PROP_LIVE_VIEW_SELECTOR = 0xD1A6
local PROP_RECORDING_MEDIA = 0xD10B
local PROP_BATTERY_LEVEL = 0x5001
local PROP_IMAGE_SIZE = 0x5003
local PROP_COMPRESSION_SETTING = 0x5004
local COMPRESSION_RAW_WITH_FINE_JPEG = 7
local PREVIEW_JPEG_IMAGE_SIZE = "3680x2456"
local MTP_NOT_LIVE_VIEW = 0xA00B
local OBJECT_FORMAT_ASSOCIATION = 0x3001
local OBJECT_FORMAT_UNDEFINED = 0x3000
local OBJECT_FORMAT_EXIF_JPEG = 0x3801
local OBJECT_FORMAT_JFIF = 0x3808
local OBJECT_FORMAT_JPEG_UNKNOWN = 0x3800
local PTP_ALL_STORAGES = 0xFFFFFFFF
local PTP_ALL_OBJECT_FORMATS = 0x00000000
local PTP_ROOT_PARENT = 0xFFFFFFFF
local CAPTURED_JPEG_SCAN_LIMIT = tonumber(os.getenv("D810D_CAPTURED_JPEG_SCAN_LIMIT") or "24") or 24
local CAPTURED_NEF_SCAN_LIMIT = tonumber(os.getenv("D810D_CAPTURED_NEF_SCAN_LIMIT") or "512") or 512
local CAPTURED_NEF_MIN_BYTES = tonumber(os.getenv("D810D_CAPTURED_NEF_MIN_BYTES") or "4194304") or 4194304
local CAPTURED_OBJECT_TIMEOUT = tonumber(os.getenv("D810D_CAPTURED_OBJECT_TIMEOUT") or "120") or 120
local CAPTURED_OBJECT_CHUNK_SIZE = tonumber(os.getenv("D810D_CAPTURED_OBJECT_CHUNK_SIZE") or "524288") or 524288
local CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT = tonumber(os.getenv("D810D_CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT") or "4194304") or 4194304

local function fail(status, message)
  error({ status = status, message = message }, 0)
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
  return math.floor(os.clock() * 1000)
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
    local handle = io.open(DEBUG_LOG, "a")
    if handle then
      handle:write(line)
      handle:close()
    end
  end
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

local function read_lock_owner(path)
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

local function clear_lock_if_stale(path, stale_ms)
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

local function acquire_lock(path, timeout_ms)
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

local function release_lock(path)
  pcall(function()
    os.remove(path .. "/owner")
  end)
  os.execute(string.format("rmdir %s >/dev/null 2>&1", shell_quote(path)))
end

local function session_condition_from_backend(backend_state, command_busy, transport_ready, live_view_active)
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

local function command_lock_busy()
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

local function tmpname(prefix)
  local suffix = tostring(os.time()) .. "." .. tostring(math.floor(os.clock() * 1000000))
  return "/tmp/" .. tostring(prefix or "d810d") .. "." .. suffix
end

local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil, "open_failed"
  end
  local data = handle:read("*a")
  handle:close()
  return data
end

local function read_prefixed_blob(data, offset)
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

local function parse_container_blob(body)
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

local function parse_stream_blob(data)
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
end

function DdServerWire:enable_legacy_transport_only(reason)
  self:close()
  self.legacy_transport_only = true
  self.hardware_detected = true
  debug_log("legacy transport only enabled: " .. tostring(reason or "unknown"))
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
  return true
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
  local timeout_sec = math.max(30, tonumber(timeout_override) or tonumber(self.timeout) or 10)
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
  if type(options) == "table" then
    if options.includeHardware == false then
      include_hardware = false
    end
  elseif options == false then
    include_hardware = false
  end
  local now = now_ms()
  if self.last_probe and self.last_probe_at > 0 and (now - self.last_probe_at) <= PROBE_CACHE_TTL_MS then
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
      local ok_battery, battery_payload = pcall(function()
        return self:get_device_prop_value(PROP_BATTERY_LEVEL)
      end)
      if ok_battery and type(battery_payload) == "string" and #battery_payload > 0 then
        battery = battery_payload:byte(1)
      end
    else
      status_name = "ready"
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
    transport_ready = true
    status_name = live_view and "liveview_on" or "ready"
    if battery == nil then
      battery = read_battery_cache()
    end
  end
  local camera_detected = transport_ready or hardware_detected
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
  debug_log(string.format("read_exact %d", length))
  local data, err = self.sock:readfull(length, self.timeout)
  if not data then
    debug_log(string.format("read_exact failed: %s", tostring(err)))
    fail("transport_error", err or "ddserver closed the connection")
  end
  debug_log(string.format("read_exact got %d", #data))
  return data
end

function DdServerWire:read_prefixed_block()
  return self:read_prefixed_packet()
end

function DdServerWire:read_prefixed_packet()
  local prefix = self:read_exact(4)
  local length = u32(prefix, 1)
  if length < 4 then
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
    debug_log(string.format("write_container failed: %s", tostring(err)))
    fail("transport_error", err or "ddserver write failed")
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
  self:write_container(CONTAINER_COMMAND, CMD_OPEN_SESSION, le_u32(self.session_id))
  local blocks = self:read_response_blocks(2)
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
    fail("camera_missing", string.format("ddserver rejected device connect 0x%04x", connect_code or 0))
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
    fail("camera_missing", tostring(connect_err or "device connect failed"))
  end
  return true
end

function DdServerWire:device_ready()
  local _, response_code = self:execute(NIKON_DEVICE_READY)
  return response_code
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

read_battery_cache = function()
  local handle = io.open(BATTERY_CACHE_PATH, "rb")
  if not handle then
    return nil
  end
  local data = handle:read("*a") or ""
  handle:close()
  return tonumber((data or ""):match("([0-9]+)"))
end

local function write_battery_cache(value)
  local battery = tonumber(value)
  if not battery then
    return false
  end
  local handle = io.open(BATTERY_CACHE_PATH, "wb")
  if not handle then
    return false
  end
  handle:write(tostring(math.max(0, math.min(100, math.floor(battery)))))
  handle:close()
  return true
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
    fail("camera_missing", string.format("ddserver rejected set prop 0x%04x with 0x%04x", prop_code or 0, response_code or 0))
  end
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
  return parse_u32_array(payload)
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
  if os.getenv("D810D_ENABLE_CAPTURE_IN_SDRAM") == "1" then
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
    local current = self:get_device_prop_value(PROP_LIVE_VIEW_STATUS)
    if current ~= nil and #current > 0 and current:byte(1) == 1 then
      start_response = RESP_OK
      return
    end
    for attempt = 1, 10 do
      local ready_response = self:device_ready()
      if ready_response == RESP_OK then
        local _, response_code = self:execute(NIKON_START_LIVE_VIEW)
        start_response = response_code
        if response_code == RESP_OK then
          return
        end
        if response_code ~= RESP_DEVICE_BUSY then
          fail("liveview_start_failed", string.format("camera live start response 0x%04x", response_code or 0))
        end
      elseif ready_response ~= RESP_DEVICE_BUSY then
        fail("liveview_start_failed", string.format("camera ready response 0x%04x", ready_response or 0))
      end
      sleep_ms(120)
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

function DdServerWire:af_drive()
  if self.legacy_transport_only or not self.session_open then
    return self:af_drive_legacy()
  end
  self:ensure_transport_ready(false)
  self:device_ready()
  local _, response_code = self:execute(NIKON_AF_DRIVE)
  if response_code ~= RESP_OK then
    fail("transport_error", string.format("af failed 0x%04x", response_code or 0))
  end
  return response_code
end

function DdServerWire:shutter()
  if self.legacy_transport_only or not self.session_open then
    return self:shutter_legacy()
  end
  self:ensure_transport_ready(false)
  self:device_ready()

  if self.live_view_active then
    self:set_device_prop_value(PROP_RECORDING_MEDIA, string.char(0))
    sleep_ms(100)
    self:device_ready()

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
      if mode_response ~= RESP_DEVICE_BUSY then
        fail("transport_error", string.format("camera control release failed 0x%04x", mode_response or 0))
      end
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

function DdServerWire:live_view_frame()
  if self.legacy_transport_only or not self.session_open then
    return self:live_view_frame_legacy()
  end
  local payload, response_code
  local ok, err = pcall(function()
    payload, response_code = self:execute(NIKON_GET_LIVE_VIEW_IMAGE)
  end)
  if not ok then
    error(tostring(err or "transport_error"), 0)
  end
  if response_code == MTP_NOT_LIVE_VIEW then
    self.live_view_active = false
    fail("not_live_view", "camera is not in live view")
  end
  if not payload or #payload == 0 then
    fail("capture_failed", "live view payload was empty")
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

function BridgeSession.new(host, port, frame_path)
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
    last_power = nil,
    last_metrics = nil,
    last_device = nil,
    last_status_at = 0,
    last_battery_at = 0,
    last_frame_at = 0,
    last_command_at = 0,
    frame_failures = 0,
    frame_seq = 0,
    reconnect_count = 0,
    session_id = current_session_id(),
    session_label = current_session_label(),
    live_session_id = nil,
    live_session_label = "",
    backend_started_at = now_ms(),
    backend_state = "idle",
    last_recover_at = 0,
    last_recover_reason = "",
    last_connect_at = 0,
    next_connect_try_at = 0,
    transport_ready = false,
    hardware_detected = false,
    session_mode_live = false,
  }, BridgeSession)
  self:load_session_state()
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
  local live_mode = self.session_mode_live == true or self.live_view_active == true
  return write_state_file(SESSION_STATE, {
    backendState = self.backend_state or "idle",
    liveView = live_mode and "true" or "false",
    transportReady = (self.transport_ready == true or live_mode) and "true" or "false",
    hardwareDetected = self.hardware_detected and "true" or "false",
    lastStatus = self.last_status or "idle",
    lastError = self.last_error or "",
    backendStartedAt = tostring(self.backend_started_at or now_ms()),
    lastStatusAt = tostring(self.last_status_at or now_ms()),
    lastCommandAt = tostring(self.last_command_at or 0),
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
  if not force and self.last_power and age <= BATTERY_CACHE_TTL_MS then
    return self.last_power.batteryPercent
  end
  local ok_battery, battery_percent = pcall(function()
    return self:_wire():get_battery_percent()
  end)
  if battery_percent == nil then
    battery_percent = read_battery_cache()
  end
  if ok_battery and battery_percent ~= nil then
    self.last_power = { batteryPercent = battery_percent }
    self.last_battery_at = now_ms()
    write_battery_cache(battery_percent)
    return battery_percent
  end
  if battery_percent ~= nil then
    self.last_power = { batteryPercent = battery_percent }
    self.last_battery_at = now_ms()
    write_battery_cache(battery_percent)
    return battery_percent
  end
  return nil
end

function BridgeSession:update_probe_state(probe)
  if type(probe) ~= "table" then
    return
  end
  local probe_transport_ready = probe.transportReady == true
  local wire = self.wire
  local legacy_ready = wire and wire.legacy_transport_only and (probe.hardwareDetected == true or self.hardware_detected == true)
  if probe_transport_ready then
    self.transport_ready = true
  elseif legacy_ready then
    self.transport_ready = true
  else
    self.transport_ready = false
  end
  self.hardware_detected = probe.hardwareDetected == true
  self.live_view_active = self.session_mode_live == true or probe.liveView == true
  if probe.batteryPercent ~= nil then
    self.last_power = { batteryPercent = probe.batteryPercent }
    self.last_battery_at = now_ms()
  end
end

function BridgeSession:recover_transport(reason)
  self.last_recover_reason = tostring(reason or "")
  debug_log(string.format("backend recover requested: %s", tostring(reason or "unknown")))
  self.reconnect_count = (tonumber(self.reconnect_count) or 0) + 1
  self:set_backend_state("recovering")
  local ok, err = pcall(function()
    self:connect()
  end)
  if not ok then
    self:invalidate_session("recover failed: " .. tostring(type(err) == "table" and (err.message or err.status) or err), "idle")
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
      self.transport_ready = true
      self.live_view_active = self.session_mode_live == true
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

  self:set_backend_state(self.transport_ready and (self.live_view_active and "live" or "ready") or "idle")
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
  if force_camera_poll or not self.live_view_active then
    self.live_view_active = self.session_mode_live == true or probe.liveView == true
  end
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
  self:set_backend_state("live")
  self.last_status = "liveview_on"
  self.last_error = ""
  self:save_session_mode("live")
  self:save_session_state()
  debug_log(string.format("live session restored id=%s label=%s", tostring(self.live_session_id or ""), tostring(self.live_session_label or "")))
  return true
end

function BridgeSession:connect()
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
    debug_log(string.format("connect persistent failed: %s", tostring(persistent_err)))
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
      debug_log(string.format("connect candidate %s failed: %s", key, tostring(connect_err)))
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
  if not self.wire or not self.device then
    self:connect()
    return
  end
  if not self.transport_ready then
    self:connect()
  end
end

function BridgeSession:derive_ui_phase(extra)
  extra = extra or {}
  local backend_state = tostring(extra.backendState or self.backend_state or "idle")
  local live_view = extra.liveView == true or self.live_view_active == true
  local connected = extra.connected == true or self.transport_ready == true
  local transport_ready = extra.transportReady == true or self.transport_ready == true
  local camera_detected = extra.cameraDetected == true or self.hardware_detected == true or self.device ~= nil
  local hardware_detected = extra.hardwareDetected == true or self.hardware_detected == true

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
  extra.uiPhase, extra.uiDetail = self:derive_ui_phase(extra)
  return response_ok(status, extra)
end

function BridgeSession:recover()
  self:recover_transport("recover endpoint")
  return self:status()
end

-- Module: status (bridge contract 2-4).
function BridgeSession:status()
  debug_log("status begin")
  self:load_latest_metrics()
  local command_busy = command_lock_busy()
  local software_ready = self.transport_ready == true or self.live_view_active == true
  if self.live_view_active then
    self:set_backend_state("live")
  elseif self.backend_state == "recovering" or self.backend_state == "degraded" then
    self:set_backend_state(self.backend_state)
  elseif software_ready then
    self:set_backend_state(self.live_view_active and "live" or "ready")
  else
    self:set_backend_state("idle")
  end
  if self.transport_ready and not self.live_view_active then
    local battery_percent = tonumber(self:refresh_battery(true))
    if battery_percent ~= nil then
      self.last_power = { batteryPercent = battery_percent }
    end
  end
  self.last_status = self.backend_state == "recovering" and "recovering" or (software_ready and "ready" or "idle")
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
  local battery_percent = nil
  if self.last_power then
    battery_percent = tonumber(self.last_power.batteryPercent)
  end
  if battery_percent == nil then
    battery_percent = read_battery_cache()
  end
  local status = self.live_view_active and "liveview_on" or (software_ready and "ready" or "idle")
  debug_log(string.format("status returning %s", status))
  return self:_ok(status, {
    liveView = self.live_view_active,
    batteryPercent = battery_percent,
    softwareReady = software_ready,
    cameraDetected = self.hardware_detected == true or self.transport_ready == true or self.device ~= nil,
    hardwareDetected = self.hardware_detected == true,
    sessionCondition = session_condition,
  })
end

function BridgeSession:boot()
  debug_log("boot begin")
  local ok, err = pcall(function()
    self:ensure_connected()
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
    if battery_percent == nil then
      battery_percent = read_battery_cache()
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
  local battery_percent = read_battery_cache()
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
  self.live_session_id, self.live_session_label = ensure_live_session()
  self:ensure_connected()
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
  if not ok then
    error(err, 0)
  end
  local live_wire = self:_wire()
  live_wire.live_view_active = true
  self.live_view_active = true
  self.transport_ready = true
  self:set_backend_state("live")
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  else
    battery_percent = read_battery_cache()
  end
  self:record_status_touch()
  self.last_status = "liveview_on"
  self.last_error = ""
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
  if not ok then
    error(err, 0)
  end
  local stopped_wire = self:_wire()
  stopped_wire.live_view_active = false
  self.live_view_active = false
  clear_live_session()
  self.live_session_id = nil
  self.live_session_label = ""
  self.last_frame_at = 0
  self:set_backend_state("ready")
  self:record_status_touch()
  self:clear_frame_cache()
  self:purge_frame_files()
  self.last_status = "liveview_off"
  self.last_error = ""
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  else
    battery_percent = read_battery_cache()
  end
  local response = self:_ok("liveview_off", {
    liveView = false,
    batteryPercent = battery_percent,
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
  else
    battery_percent = read_battery_cache()
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
  local should_resume_live = self.live_view_active == true
  local ok, err = pcall(function()
    self:_wire():shutter()
  end)
  if command_lock then
    release_lock(COMMAND_ACTION_LOCK)
  end
  if not ok then
    error(err, 0)
  end
  self.transport_ready = true
  if self.hardware_detected then
    self:set_backend_state(should_resume_live and "live" or "ready")
  end
  self.last_frame_at = 0
  local battery_percent = nil
  if self.last_power and self.last_power.batteryPercent ~= nil then
    battery_percent = tonumber(self.last_power.batteryPercent)
  else
    battery_percent = read_battery_cache()
  end
  self:record_status_touch()
  self:clear_captured_preview_cache()
  self:clear_captured_object_cache()
  self.last_status = "ok"
  self.last_error = ""
  local response = self:_ok("ok", {
    batteryPercent = battery_percent,
    liveView = should_resume_live,
  })
  self:save_session_state()
  debug_log("shutter done")
  return response
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

function BridgeSession:select_latest_jpeg_object()
  self:ensure_connected()
  local wire = self:_wire()
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
  local preview_source = "object"
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
    blob = self:_wire():get_object(info.handle)
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
    sleep_ms(250)
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

function BridgeSession:captured_object_stream(conn, object_kind)
  debug_log("captured_object_stream begin")
  self:ensure_connected()
  local started_at = now_ms()
  object_kind = object_kind or "jpeg"
  local info, scanned, total_handles, selection_source
  if object_kind == "nef" then
    info, scanned, total_handles = self:select_latest_nef_object()
    selection_source = "nef_scan"
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
    sleep_ms(250)
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

function BridgeSession:_capture_frame(use_cache, skip_process_locks)
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
  local started_at = now_ms()
  local next_frame_id = (self.frame_seq or 0) + 1
  if TRACE_FRAMES then
    debug_log(string.format("trace frame=%d ptp_start at=%.0f", next_frame_id, started_at))
  end
  local wire = self:_wire()
  local function attempt_capture()
    if not wire.live_view_active then
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
    local capture_start = now_ms()
    local frame
    local function capture_once()
      frame = wire:live_view_frame()
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
    local capture_done = now_ms()
    local write_done = now_ms()
    self.frame_seq = (self.frame_seq or 0) + 1
    self.last_frame = frame
    self.last_frame_at = capture_done
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
      cached = false,
    }
    if TRACE_FRAMES then
      debug_log(string.format("trace frame=%d ptp_done bytes=%d captureMs=%.0f at=%.0f", self.frame_seq, #frame, capture_done - capture_start, capture_done))
    end
    return frame
  end

  local ok, frame_or_err = pcall(function()
    local frame, status, message = attempt_capture()
    if not frame then
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

function BridgeSession:write_frame_cache(frame, meta)
  if type(frame) ~= "string" or #frame == 0 then
    return false
  end
  local cache_started_at = now_ms()
  local tmp_path = self.frame_path .. ".tmp"
  local ok = pcall(function()
    write_file(tmp_path, frame)
    os.rename(tmp_path, self.frame_path)
    write_file(FRAME_LAST_GOOD .. ".tmp", frame)
    os.rename(FRAME_LAST_GOOD .. ".tmp", FRAME_LAST_GOOD)
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

  local interval = tonumber(os.getenv("D810D_FRAME_REFRESH_INTERVAL") or "0.066") or 0.066
  local command = string.format(
    "%s %s %s >/dev/null 2>&1 &",
    shell_quote("/bin/sh"),
    shell_quote(FRAME_REFRESH_SCRIPT),
    shell_quote(tostring(interval))
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

function BridgeSession:capture_live_frame_background()
  if not self.live_view_active or self.session_mode_live ~= true then
    return false
  end
  local ok, err = pcall(function()
    -- The daemon loop is single-threaded and is now the sole PTP producer, so
    -- per-frame shell mkdir/rmdir locks only add process-launch latency.
    local frame, frame_meta = self:_capture_frame(false, true)
    if not self:write_frame_cache(frame, frame_meta) then
      fail("transport_error", "background frame cache write failed")
    end
  end)
  if not ok then
    self.frame_failures = (self.frame_failures or 0) + 1
    debug_log("background frame failed: " .. tostring(type(err) == "table" and (err.status or err.message) or err))
    return false
  end
  self.frame_failures = 0
  return true
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
  elseif verb == "SHUTTER" then
    return self:shutter()
  elseif verb == "RAW_MODE" then
    return self:raw_mode()
  elseif verb == "UNLOCK" then
    return self:unlock()
  elseif verb == "STORAGE" then
    return self:storage_status()
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
  elseif verb == "RECOVER" then
    return self:recover()
  elseif verb == "RESET" then
    return self:reset_session(arg)
  elseif verb == "RELOAD_SESSION" then
    return self:reload_command_session(arg)
  elseif verb == "MAINTAIN" then
    return self:maintain()
  elseif verb == "PROBE" then
    return self:probe_props(arg)
  elseif verb == "STOP" then
    return response_ok("stopping", { backend = BACKEND_NAME, sessionBackend = true })
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

local function stream_broadcast(clients, frame, meta)
  if type(frame) ~= "string" or #frame == 0 then return end
  local frame_id = tonumber(type(meta) == "table" and meta.frameId or 0) or 0
  if TRACE_FRAMES then
    debug_log(string.format("trace frame=%d stream_deferred bytes=%d clients=%d at=%.0f", frame_id, #frame, #clients, now_ms()))
  end
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
  local stream_server = socket.listen_tcp(STREAM_HOST, STREAM_PORT, {
    reuseaddr = true,
    tcp_nodelay = true,
    backlog = 4,
  })
  io.stderr:write(string.format("bridge listening on %s:%d\n", BRIDGE_HOST, BRIDGE_PORT))
  local session = BridgeSession.new(DDSERVER_HOST, DDSERVER_PORT, FRAME_PATH)
  local running = true
  local stream_clients = {}

  while running do
    if stream_server then
      while true do
        local client = stream_server:accept()
        if not client then break end
        stream_clients[#stream_clients + 1] = client
        debug_log(string.format("direct stream client accepted count=%d", #stream_clients))
      end
    end
    if session.live_view_active and session.session_mode_live == true then
      local captured = session:capture_live_frame_background()
      if captured and session.last_frame then
        stream_broadcast(stream_clients, session.last_frame, session.last_metrics)
      end
    end
    local conn = server:accept()
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
        if command == "CAPTURED_OBJECT_JPEG" then
          local binary_started = false
          local ok, result = pcall(function()
            binary_started = true
            return session:captured_object_stream(conn)
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
    else
      sleep_ms(2)
    end
  end

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
    FRAME = "FRAME",
    FRAME_STORE = "FRAME_STORE",
    FRAME_BIN = "FRAME_BIN",
    FRAME_PACKET = "FRAME_PACKET",
    CAPTURED_JPEG = "CAPTURED_JPEG",
    CAPTURED_JPEG_BIN = "CAPTURED_JPEG_BIN",
    CAPTURED_OBJECT = "CAPTURED_OBJECT",
    RECOVER = "RECOVER",
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
