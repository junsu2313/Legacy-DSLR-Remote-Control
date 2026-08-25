#!/usr/bin/lua

local ok_nixio, nixio = pcall(require, "nixio")
local eco_socket = nil
local eco_time = nil
if not ok_nixio then
  local ok_socket, socket_module = pcall(require, "eco.socket")
  local ok_time, time_module = pcall(require, "eco.time")
  if not ok_socket or not ok_time or type(eco) ~= "table" or type(eco.run) ~= "function" then
    error("neither nixio nor eco.socket runtime is available")
  end
  eco_socket = socket_module
  eco_time = time_module
end

local ok_cjson, cjson = pcall(require, "cjson")
if not ok_cjson then
  error("cjson is required")
end

local WS_HOST = os.getenv("WS_HOST") or "0.0.0.0"
local WS_PORT = tonumber(os.getenv("WS_PORT") or "8091")
local DEBUG_LOG = os.getenv("D810D_WS_LOG") or "/tmp/d810-ws-debug.log"
local GLOBAL_LOG = os.getenv("D810D_GLOBAL_LOG") or "/root/d810-camera-events.log"
local GLOBAL_LOG_ROTATE_BYTES = tonumber(os.getenv("D810D_GLOBAL_LOG_ROTATE_BYTES") or "2097152") or 2097152
local global_log_check_count = 0
local POLL_MS = tonumber(os.getenv("D810D_WS_POLL_MS") or "33")
local FRAME_PATH = os.getenv("D810D_FRAME_PATH") or "/tmp/d810-live.jpg"
local FRAME_LAST_GOOD = os.getenv("D810D_FRAME_LAST_GOOD") or "/tmp/d810-live-last-good.jpg"
local FRAME_META = os.getenv("D810D_FRAME_META") or "/tmp/d810-live.meta"
local LIVE_REQUEST_PATH = os.getenv("D810D_SESSION_LIVE_REQUEST") or "/tmp/d810-session.live"
local STREAM_HOST = os.getenv("D810D_STREAM_HOST") or "127.0.0.1"
local STREAM_PORT = tonumber(os.getenv("D810D_STREAM_PORT") or "8190")
local TRACE_FRAMES = tostring(os.getenv("D810D_TRACE_FRAMES") or "0") == "1"
local MAX_WS_CLIENTS = tonumber(os.getenv("D810D_WS_MAX_CLIENTS") or "4") or 4
local WS_HEALTH_PATH = os.getenv("D810D_WS_HEALTH_PATH") or "/tmp/d810-ws-v21.health"
local last_delivered_frame_at_sec = 0
local last_health_publish_at_sec = 0
local socket_runtime = ok_nixio and "nixio" or "eco"

local function method(obj, names)
  for _, name in ipairs(names) do
    if type(obj[name]) == "function" then
      return obj[name]
    end
  end
  return nil
end

local function log_line(message)
  local line = "[d810ws] " .. tostring(message) .. "\n"
  local handle = io.open(DEBUG_LOG, "a")
  if handle then
    handle:write(line)
    handle:close()
  end
  if GLOBAL_LOG ~= "" and GLOBAL_LOG ~= DEBUG_LOG then
    global_log_check_count = global_log_check_count + 1
    local global = io.open(GLOBAL_LOG, "a+")
    if global then
      if global_log_check_count == 1 or global_log_check_count % 128 == 0 then
        local size = global:seek("end") or 0
        if size >= GLOBAL_LOG_ROTATE_BYTES then
          global:close()
          os.remove(GLOBAL_LOG .. ".2")
          os.rename(GLOBAL_LOG .. ".1", GLOBAL_LOG .. ".2")
          os.rename(GLOBAL_LOG, GLOBAL_LOG .. ".1")
          global = io.open(GLOBAL_LOG, "a")
        end
      end
      if not global then
        return
      end
      global:write(line)
      global:close()
    end
  end
end

local function now_ms()
  if ok_nixio and type(nixio.gettimeofday) == "function" then
    local sec, usec = nixio.gettimeofday()
    return (tonumber(sec) or 0) * 1000 + math.floor((tonumber(usec) or 0) / 1000)
  end
  return os.time() * 1000
end

local function publish_ws_health(frame_delivered, force)
  local now_sec = os.time()
  if frame_delivered then
    last_delivered_frame_at_sec = now_sec
  end
  if not force and now_sec == last_health_publish_at_sec then
    return
  end
  local tmp_path = WS_HEALTH_PATH .. ".tmp"
  local handle = io.open(tmp_path, "w")
  if not handle then return end
  handle:write("state=ready\n")
  handle:write("runtime=" .. socket_runtime .. "\n")
  handle:write("observedAtSec=" .. tostring(now_sec) .. "\n")
  handle:write("lastFrameAtSec=" .. tostring(last_delivered_frame_at_sec) .. "\n")
  handle:close()
  os.rename(tmp_path, WS_HEALTH_PATH)
  last_health_publish_at_sec = now_sec
end

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(text)
  text = tostring(text or "")
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function websocket_accept(key)
  local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  local cmd = "printf %s " .. shell_quote((key or "") .. guid) .. " | openssl dgst -binary -sha1 | openssl enc -base64 -A"
  local pipe = io.popen(cmd, "r")
  if not pipe then
    return nil
  end
  local output = trim(pipe:read("*a") or "")
  pipe:close()
  return output ~= "" and output or nil
end

local function read_line(sock)
  local recv = method(sock, { "recv", "receive", "read" })
  if not recv then
    return nil, "socket has no recv method"
  end
  local parts = {}
  while true do
    local chunk, err, partial = recv(sock, 1)
    chunk = chunk or partial
    if not chunk or #chunk == 0 then
      return nil, err or "closed"
    end
    if chunk == "\n" then
      return table.concat(parts):gsub("\r$", "")
    end
    parts[#parts + 1] = chunk
  end
end

local function send_all(sock, data)
  local send = method(sock, { "send", "write" })
  if not send then
    return nil, "socket has no send method"
  end
  local sent = 0
  while sent < #data do
    -- Avoid a full JPEG copy on the common single-write path. A slice is
    -- needed only when the socket reports a partial write.
    local chunk = sent == 0 and data or data:sub(sent + 1)
    local wrote, err = send(sock, chunk)
    if wrote == nil or wrote == false or wrote == 0 then
      return nil, err or "send failed"
    end
    sent = sent + (tonumber(wrote) or #chunk)
  end
  return true
end

local function ws_frame_header(opcode, len)
  len = tonumber(len) or 0
  if len < 126 then
    return string.char(0x80 + opcode, len)
  end
  if len < 65536 then
    local hi = math.floor(len / 256) % 256
    local lo = len % 256
    return string.char(0x80 + opcode, 126, hi, lo)
  end
  local bytes = {}
  local n = len
  for i = 8, 1, -1 do
    bytes[i] = n % 256
    n = math.floor(n / 256)
  end
  return string.char(0x80 + opcode, 127, unpack(bytes))
end

local function send_ws_frame(sock, opcode, payload)
  payload = payload or ""
  local ok, err = send_all(sock, ws_frame_header(opcode, #payload))
  if not ok then return nil, err end
  return send_all(sock, payload)
end

local function sleep_ms(ms)
  if ok_nixio and type(nixio.nanosleep) == "function" then
    local sec = math.floor(ms / 1000)
    local nsec = (ms - sec * 1000) * 1000000
    nixio.nanosleep(sec, nsec)
  elseif eco_time and type(eco_time.sleep) == "function" then
    eco_time.sleep(math.max(0, ms) / 1000)
  else
    os.execute("sleep " .. tostring(ms / 1000))
  end
end

local function bind_server(host, port)
  if eco_socket then
    return eco_socket.listen_tcp(host, port, {
      reuseaddr = true,
      backlog = 4,
    })
  end
  local server = nixio.socket("inet", "stream")
  if not server then
    return nil, "socket create failed"
  end
  if not server:setopt("socket", "reuseaddr", 1) then
    pcall(function() server:close() end)
    return nil, "reuseaddr failed"
  end
  if not server:bind(host, port) then
    pcall(function() server:close() end)
    return nil, "bind failed"
  end
  if not server:listen(4) then
    pcall(function() server:close() end)
    return nil, "listen failed"
  end
  return server
end

local function base64_decode(data)
  data = tostring(data or ""):gsub("%s+", "")
  if data == "" then
    return ""
  end
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local lookup = {}
  for i = 1, #alphabet do
    lookup[alphabet:sub(i, i)] = i - 1
  end
  local out = {}
  local i = 1
  while i <= #data do
    local c1 = data:sub(i, i)
    local c2 = data:sub(i + 1, i + 1)
    local c3 = data:sub(i + 2, i + 2)
    local c4 = data:sub(i + 3, i + 3)
    if c1 == "" or c2 == "" then
      break
    end
    local n1 = lookup[c1] or 0
    local n2 = lookup[c2] or 0
    local n3 = c3 == "=" and 0 or (lookup[c3] or 0)
    local n4 = c4 == "=" and 0 or (lookup[c4] or 0)
    local value = n1 * 262144 + n2 * 4096 + n3 * 64 + n4
    out[#out + 1] = string.char(math.floor(value / 65536) % 256)
    if c3 ~= "=" and c3 ~= "" then
      out[#out + 1] = string.char(math.floor(value / 256) % 256)
    end
    if c4 ~= "=" and c4 ~= "" then
      out[#out + 1] = string.char(value % 256)
    end
    i = i + 4
  end
  return table.concat(out)
end

local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local data = handle:read("*a")
  handle:close()
  return data
end

local function wait_for_live_request(sock)
  while not read_file(LIVE_REQUEST_PATH) do
    -- A stale client may reconnect after another client issued LIVE_STOP.
    -- Keep that connection idle instead of repeatedly opening and closing a
    -- direct bridge stream; ping frames also detect clients that went away.
    local ok, err = send_ws_frame(sock, 0x9, "")
    if not ok then
      log_line("idle websocket ended: " .. tostring(err))
      return false
    end
    sleep_ms(1000)
  end
  return true
end

local function read_meta()
  local raw = read_file(FRAME_META)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local meta = {}
  for line in tostring(raw):gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      meta[key] = value
    end
  end
  return meta
end

local function frame_token(meta, blob)
  return table.concat({
    tostring(meta.captureDoneAt or meta.writeDoneAt or meta.startedAt or ""),
    tostring(meta.startedAt or ""),
    tostring(meta.bytes or (type(blob) == "string" and #blob or 0)),
  }, ":")
end

local function read_latest_frame_packet(last_token)
  local meta = read_meta()
  if type(meta) ~= "table" then
    local blob = read_file(FRAME_PATH)
    if type(blob) ~= "string" or #blob == 0 then
      blob = read_file(FRAME_LAST_GOOD)
    end
    if type(blob) ~= "string" or #blob == 0 then
      return nil, "frame payload unavailable"
    end
    local token = table.concat({
      tostring(#blob),
      blob:sub(1, 32),
      blob:sub(-32),
    }, ":")
    if token == last_token then
      return { token = token, unchanged = true, meta = { bytes = #blob } }
    end
    return {
      token = token,
      data = blob,
      meta = { bytes = #blob },
    }
  end
  local token = frame_token(meta)
  if token == last_token then
    return {
      token = token,
      unchanged = true,
      meta = {
        startedAt = tonumber(meta.startedAt),
        prepMs = tonumber(meta.prepMs),
        captureStartedAt = tonumber(meta.captureStartedAt),
        captureDoneAt = tonumber(meta.captureDoneAt),
        writeDoneAt = tonumber(meta.writeDoneAt),
        totalMs = tonumber(meta.totalMs),
        captureMs = tonumber(meta.captureMs),
        writeMs = tonumber(meta.writeMs),
        frameId = tonumber(meta.frameId),
        bytes = tonumber(meta.bytes),
      },
    }
  end
  local blob = read_file(FRAME_PATH)
  if type(blob) ~= "string" or #blob == 0 then
    blob = read_file(FRAME_LAST_GOOD)
  end
  if type(blob) ~= "string" or #blob == 0 then
    return nil, "frame payload unavailable"
  end
  return {
    token = token,
    data = blob,
    meta = {
      startedAt = tonumber(meta.startedAt),
      prepMs = tonumber(meta.prepMs),
      captureStartedAt = tonumber(meta.captureStartedAt),
      captureDoneAt = tonumber(meta.captureDoneAt),
      writeDoneAt = tonumber(meta.writeDoneAt),
      totalMs = tonumber(meta.totalMs),
      captureMs = tonumber(meta.captureMs),
      writeMs = tonumber(meta.writeMs),
      frameId = tonumber(meta.frameId),
      bytes = tonumber(meta.bytes) or #blob,
    },
  }
end

local function connect_direct_stream()
  if eco_socket then
    return eco_socket.connect_tcp(STREAM_HOST, STREAM_PORT)
  end
  local stream = nixio.socket("inet", "stream")
  if not stream then return nil end
  if not stream:connect(STREAM_HOST, STREAM_PORT) then
    pcall(function() stream:close() end)
    return nil
  end
  pcall(function() stream:setblocking(true) end)
  pcall(function() stream:setopt("tcp", "nodelay", 1) end)
  return stream
end

local function read_exact(sock, length)
  local recv = method(sock, { "recv", "receive", "read" })
  if not recv then return nil, "no receive method" end
  local parts, total = {}, 0
  while total < length do
    local chunk, err, partial = recv(sock, length - total)
    chunk = chunk or partial
    if not chunk or #chunk == 0 then return nil, err or "stream closed" end
    parts[#parts + 1] = chunk
    total = total + #chunk
  end
  if #parts == 1 then return parts[1] end
  return table.concat(parts)
end

local function read_direct_frame(stream)
  local header, err = read_exact(stream, 8)
  if not header then return nil, err end
  local b1, b2, b3, b4 = header:byte(1, 4)
  local i1, i2, i3, i4 = header:byte(5, 8)
  local length = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
  local frame_id = i1 * 16777216 + i2 * 65536 + i3 * 256 + i4
  if length <= 0 or length > 4 * 1024 * 1024 then return nil, "invalid frame length" end
  if length < 5 then return nil, "direct frame payload too short" end
  local meta_header, meta_header_err = read_exact(stream, 4)
  if not meta_header then return nil, meta_header_err end
  local m1, m2, m3, m4 = meta_header:byte(1, 4)
  local meta_length = m1 * 16777216 + m2 * 65536 + m3 * 256 + m4
  local frame_length = length - 4 - meta_length
  if meta_length <= 0 or meta_length > 16384 or frame_length <= 0 then
    return nil, "invalid direct frame metadata length"
  end
  local meta_raw, meta_err = read_exact(stream, meta_length)
  if not meta_raw then return nil, meta_err end
  local frame, frame_err = read_exact(stream, frame_length)
  if not frame then return nil, frame_err end
  return frame, nil, frame_id, meta_raw
end


local function handle_client(sock)
  local request_line = read_line(sock)
  if not request_line then
    return
  end

  local headers = {}
  while true do
    local line = read_line(sock)
    if not line or line == "" then
      break
    end
    local key, value = line:match("^([^:]+):%s*(.*)$")
    if key then
      headers[string.lower(key)] = value
    end
  end

  local accept = websocket_accept(headers["sec-websocket-key"])
  if not accept then
    send_all(sock, "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n")
    return
  end

  local response = table.concat({
    "HTTP/1.1 101 Switching Protocols\r\n",
    "Upgrade: websocket\r\n",
    "Connection: Upgrade\r\n",
    "Sec-WebSocket-Accept: ", accept, "\r\n",
    "Cache-Control: no-store\r\n",
    "\r\n",
  })
  local ok, err = send_all(sock, response)
  if not ok then
    log_line("handshake send failed: " .. tostring(err))
    return
  end

  if not wait_for_live_request(sock) then
    return
  end

  local direct_stream = connect_direct_stream()
  if direct_stream then
    log_line("direct bridge stream connected")
    while true do
      local frame, frame_err, _, meta_payload = read_direct_frame(direct_stream)
      if not frame then
        log_line("direct bridge stream ended: " .. tostring(frame_err))
        pcall(function() direct_stream:close() end)
        break
      end
      local ok_meta, meta_err = send_ws_frame(sock, 0x2, meta_payload)
      if not ok_meta then
        log_line("direct meta send failed: " .. tostring(meta_err))
        pcall(function() direct_stream:close() end)
        break
      end
      local ok_bin, bin_err = send_ws_frame(sock, 0x2, frame)
      if not ok_bin then
        log_line("direct frame send failed: " .. tostring(bin_err))
        pcall(function() direct_stream:close() end)
        break
      end
      publish_ws_health(true, false)
    end
  end
  if not read_file(LIVE_REQUEST_PATH) then
    log_line("live intent cleared; closing websocket worker")
    return
  end
  log_line("direct bridge stream unavailable; using frame-file fallback")

  local last_token = nil
  local last_packet_err = nil
  while true do
    if not read_file(LIVE_REQUEST_PATH) then
      log_line("live intent cleared during fallback; closing websocket worker")
      return
    end
    local packet, packet_err = read_latest_frame_packet(last_token)
    if packet then
      last_packet_err = nil
      if not packet.unchanged and packet.token ~= last_token then
        local meta_payload = cjson.encode({
          type = "meta",
          transport = "websocket",
          startedAt = packet.meta.startedAt,
          prepMs = packet.meta.prepMs,
          captureStartedAt = packet.meta.captureStartedAt,
          captureDoneAt = packet.meta.captureDoneAt,
          writeDoneAt = packet.meta.writeDoneAt,
          totalMs = packet.meta.totalMs,
          captureMs = packet.meta.captureMs,
          writeMs = packet.meta.writeMs,
          frameId = packet.meta.frameId,
          bytes = packet.meta.bytes or #packet.data,
        })
        local ok_meta, meta_err = send_ws_frame(sock, 0x1, meta_payload)
        if not ok_meta then
          log_line("meta send failed: " .. tostring(meta_err))
          break
        end
        local ok_bin, bin_err = send_ws_frame(sock, 0x2, packet.data)
        if not ok_bin then
          log_line("frame send failed: " .. tostring(bin_err))
          break
        end
        publish_ws_health(true, false)
        last_token = packet.token
      end
    else
      if packet_err ~= last_packet_err then
        log_line("frame packet failed: " .. tostring(packet_err))
        last_packet_err = packet_err
      end
    end
    if POLL_MS > 0 then
      sleep_ms(POLL_MS)
    end
  end
end

local function run_server()
  local server, err = bind_server(WS_HOST, WS_PORT)
  if not server then
    log_line("server already active or bind failed: " .. tostring(err))
    return
  end
  log_line(string.format("websocket listening on %s:%d", WS_HOST, WS_PORT))
  publish_ws_health(false, true)

  if eco_socket then
    local active_clients = 0
    while true do
      local client = server:accept()
      if client then
        if active_clients >= MAX_WS_CLIENTS then
          send_all(client, "HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n")
          pcall(function() client:close() end)
          log_line("websocket client rejected: capacity reached")
        else
          active_clients = active_clients + 1
          eco.run(function()
            local ok_client, client_err = pcall(handle_client, client)
            if not ok_client then
              log_line("websocket client failed: " .. tostring(client_err))
            end
            pcall(function() client:close() end)
            active_clients = math.max(0, active_clients - 1)
          end)
        end
      end
    end
  end

  pcall(function() server:setblocking(false) end)
  local children = {}

  local function reap_children()
    for pid in pairs(children) do
      local ok_wait, done = pcall(nixio.waitpid, pid, "nohang")
      if not ok_wait or done == nil or done == pid then
        children[pid] = nil
      end
    end
  end

  local function child_count()
    local count = 0
    for _ in pairs(children) do count = count + 1 end
    return count
  end

  while true do
    reap_children()
    local client = server:accept()
    if client then
      pcall(function()
        client:setblocking(true)
      end)
      if child_count() >= MAX_WS_CLIENTS then
        send_all(client, "HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n")
        pcall(function() client:close() end)
        log_line("websocket client rejected: capacity reached")
      else
        local ok_fork, pid = pcall(nixio.fork)
        if ok_fork and pid == 0 then
          pcall(function() server:close() end)
          pcall(handle_client, client)
          pcall(function() client:close() end)
          os.exit(0)
        elseif ok_fork and tonumber(pid) and pid > 0 then
          children[pid] = true
          pcall(function() client:close() end)
        else
          pcall(function() client:close() end)
          log_line("websocket client rejected: fork failed")
        end
      end
    else
      sleep_ms(25)
    end
  end
end

local mode = arg[1] or "daemon"
if mode == "daemon" then
  local ok, err = pcall(run_server)
  if not ok then
    log_line("server crashed: " .. tostring(err))
    error(err)
  end
end
