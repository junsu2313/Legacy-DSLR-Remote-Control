#!/usr/bin/lua

local ok_nixio, nixio = pcall(require, "nixio")
if not ok_nixio then
  error("nixio is required")
end

local ok_cjson, cjson = pcall(require, "cjson")
if not ok_cjson then
  error("cjson is required")
end

local WS_HOST = os.getenv("WS_HOST") or "0.0.0.0"
local WS_PORT = tonumber(os.getenv("WS_PORT") or "8091")
local DEBUG_LOG = os.getenv("D810D_WS_LOG") or "/tmp/d810-ws-debug.log"
local POLL_MS = tonumber(os.getenv("D810D_WS_POLL_MS") or "33")
local FRAME_PATH = os.getenv("D810D_FRAME_PATH") or "/tmp/d810-live.jpg"
local FRAME_LAST_GOOD = os.getenv("D810D_FRAME_LAST_GOOD") or "/tmp/d810-live-last-good.jpg"
local FRAME_META = os.getenv("D810D_FRAME_META") or "/tmp/d810-live.meta"
local STREAM_HOST = os.getenv("D810D_STREAM_HOST") or "127.0.0.1"
local STREAM_PORT = tonumber(os.getenv("D810D_STREAM_PORT") or "8190")
local TRACE_FRAMES = tostring(os.getenv("D810D_TRACE_FRAMES") or "0") == "1"

local function method(obj, names)
  for _, name in ipairs(names) do
    if type(obj[name]) == "function" then
      return obj[name]
    end
  end
  return nil
end

local function log_line(message)
  local handle = io.open(DEBUG_LOG, "a")
  if handle then
    handle:write("[d810ws] " .. tostring(message) .. "\n")
    handle:close()
  end
end

local function now_ms()
  if type(nixio.gettimeofday) == "function" then
    local sec, usec = nixio.gettimeofday()
    return (tonumber(sec) or 0) * 1000 + math.floor((tonumber(usec) or 0) / 1000)
  end
  return os.time() * 1000
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
    local wrote, err = send(sock, data:sub(sent + 1))
    if not wrote or wrote <= 0 then
      return nil, err or "send failed"
    end
    sent = sent + wrote
  end
  return true
end

local function ws_frame(opcode, payload)
  payload = payload or ""
  local len = #payload
  if len < 126 then
    return string.char(0x80 + opcode, len) .. payload
  end
  if len < 65536 then
    local hi = math.floor(len / 256) % 256
    local lo = len % 256
    return string.char(0x80 + opcode, 126, hi, lo) .. payload
  end
  local bytes = {}
  local n = len
  for i = 8, 1, -1 do
    bytes[i] = n % 256
    n = math.floor(n / 256)
  end
  return string.char(0x80 + opcode, 127, unpack(bytes)) .. payload
end

local function sleep_ms(ms)
  if type(nixio.nanosleep) == "function" then
    local sec = math.floor(ms / 1000)
    local nsec = (ms - sec * 1000) * 1000000
    nixio.nanosleep(sec, nsec)
  else
    os.execute("sleep " .. tostring(ms / 1000))
  end
end

local function bind_server(host, port)
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
  local stream = nixio.socket("inet", "stream")
  if not stream then return nil end
  if not stream:connect(STREAM_HOST, STREAM_PORT) then
    pcall(function() stream:close() end)
    return nil
  end
  pcall(function() stream:setblocking(true) end)
  return stream
end

local function read_exact(sock, length)
  local recv = method(sock, { "recv", "receive", "read" })
  if not recv then return nil, "no receive method" end
  local parts, total = {}, 0
  while total < length do
    local chunk, err, partial = recv(sock, 1)
    chunk = chunk or partial
    if not chunk or #chunk == 0 then return nil, err or "stream closed" end
    parts[#parts + 1] = chunk
    total = total + #chunk
  end
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
  local frame, frame_err = read_exact(stream, length)
  if not frame then return nil, frame_err end
  return frame, nil, frame_id
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

  local last_token = nil
  local last_packet_err = nil
  while true do
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
        local ok_meta, meta_err = send_all(sock, ws_frame(0x1, meta_payload))
        if not ok_meta then
          log_line("meta send failed: " .. tostring(meta_err))
          break
        end
        local ok_bin, bin_err = send_all(sock, ws_frame(0x2, packet.data))
        if not ok_bin then
          log_line("frame send failed: " .. tostring(bin_err))
          break
        end
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
  while true do
    local client = server:accept()
    if client then
      pcall(function()
        client:setblocking(true)
      end)
      pcall(handle_client, client)
      pcall(function()
        client:close()
      end)
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
