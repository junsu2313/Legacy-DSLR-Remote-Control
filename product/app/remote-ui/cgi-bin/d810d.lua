#!/usr/bin/lua

local HOST = os.getenv("D810D_DDSERVER_HOST") or "127.0.0.1"
local PORT = tonumber(os.getenv("D810D_DDSERVER_PORT") or "4757")
local BRIDGE_HOST = os.getenv("D810D_BRIDGE_HOST") or "127.0.0.1"
local BRIDGE_PORT = tonumber(os.getenv("D810D_BRIDGE_PORT") or "8089")
local FRAME_PATH = os.getenv("D810D_FRAME_PATH") or "/tmp/d810-live.jpg"
local FRAME_LAST_GOOD = os.getenv("D810D_FRAME_LAST_GOOD") or "/tmp/d810-live-last-good.jpg"
local FRAME_META = os.getenv("D810D_FRAME_META") or "/tmp/d810-live.meta"
local NC = os.getenv("D810D_NC") or "/usr/bin/nc"
local TIMEOUT = os.getenv("D810D_TIMEOUT") or "/usr/bin/timeout"
local GPHOTO = os.getenv("D810D_GPHOTO_BIN") or "/usr/bin/gphoto2"

local CONTAINER_COMMAND = 0x0001
local CONTAINER_DATA = 0x0002
local CONTAINER_RESPONSE = 0x0003

local CMD_GET_DEVICES = 0x0002
local CMD_CONNECT_DEVICE = 0x0001
local CMD_OPEN_SESSION = 0x1002
local CMD_CLOSE_SESSION = 0x1003
local CMD_GET_DEVICE_PROP_DESC = 0x1014
local CMD_GET_DEVICE_PROP_VALUE = 0x1015
local CMD_SET_DEVICE_PROP_VALUE = 0x1016

local NIKON_DEVICE_READY = 0x90C8
local NIKON_AF_DRIVE = 0x90C1
local NIKON_START_LIVE_VIEW = 0x9201
local NIKON_END_LIVE_VIEW = 0x9202
local NIKON_GET_LIVE_VIEW_IMAGE = 0x9203
local NIKON_SHUTTER = 0x9207

local PROP_LIVE_VIEW_STATUS = 0xD1A2
local PROP_RECORDING_MEDIA = 0xD10B
local PROP_AF_MODE_SELECT = 0xD161
local PROP_BATTERY_LEVEL = 0x5001
local PROP_AC_POWER = 0xD101
local MTP_NOT_LIVE_VIEW = 0xA00B
local MTP_RESPONSE_OK = 0x2001

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

local function pack_data_command(code, command_payload, data_payload)
  local command = pack_container(CONTAINER_COMMAND, code, command_payload):sub(5)
  local data = pack_container(CONTAINER_DATA, code, data_payload):sub(5)
  return le_u32(4 + #command + #data) .. command .. data
end

local function shell_quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function tmpname(prefix)
  if prefix then
    return "/tmp/" .. prefix
  end
  return os.tmpname()
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

local function write_file(path, data)
  local handle = assert(io.open(path, "wb"))
  handle:write(data)
  handle:close()
end

local function read_mode_file(path)
  local handle = io.open(path, "rb")
  if not handle then
    return ""
  end
  local data = handle:read("*a") or ""
  handle:close()
  return (data:gsub("%s+$", ""))
end

local function write_mode_file(path, mode)
  local handle = assert(io.open(path, "wb"))
  handle:write(tostring(mode or ""))
  handle:close()
end

local function cleanup(path1, path2)
  if path1 then
    os.remove(path1)
  end
  if path2 then
    os.remove(path2)
  end
end

local function run_session(request)
  local req = tmpname()
  local resp = tmpname()
  write_file(req, request)
  local cmd = string.format(
    "%s -t 10 %s %s %d < %s > %s 2>/dev/null",
    TIMEOUT,
    NC,
    HOST,
    PORT,
    shell_quote(req),
    shell_quote(resp)
  )
  os.execute(cmd)
  local data = read_file(resp)
  cleanup(req, resp)
  return data or ""
end

local function run_bridge_command(command)
  local req = tmpname("d810-bridge-req")
  local resp = tmpname("d810-bridge-resp")
  write_file(req, command .. "\n")
  local cmd = string.format(
    "%s -t 10 %s %s %d < %s > %s 2>/dev/null",
    TIMEOUT,
    NC,
    BRIDGE_HOST,
    BRIDGE_PORT,
    shell_quote(req),
    shell_quote(resp)
  )
  os.execute(cmd)
  local data = read_file(resp)
  cleanup(req, resp)
  return data or ""
end

local function read_prefixed(data, offset)
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

local function parse_container(body)
  if #body < 12 then
    return nil
  end
  local length = u32(body, 1)
  local ctype = body:byte(5) or 0
  local code = u16(body, 7)
  local txid = u32(body, 9)
  local payload = body:sub(13)
  return {
    length = length,
    ctype = ctype,
    code = code,
    txid = txid,
    payload = payload,
  }
end

local function parse_stream(data)
  local offset = 1
  local blocks = {}
  local _, next_offset = read_prefixed(data, offset)
  offset = next_offset
  while offset <= #data do
    local body
    body, offset = read_prefixed(data, offset)
    if not body then
      break
    end
    local container = parse_container(body)
    if container and container.ctype ~= 0x0004 then
      table.insert(blocks, container)
    end
  end
  return blocks
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

local function lower(text)
  return string.lower(text or "")
end

local function select_device(devices)
  if #devices == 0 then
    return {
      vendor_id = 0x04B0,
      product_id = 0x0436,
      vendor_name = "NIKON",
      product_name = "NIKON DSC D810",
    }
  end
  for _, device in ipairs(devices) do
    local haystack = lower((device.vendor_name or "") .. " " .. (device.product_name or ""))
    if haystack:find("d810", 1, true) then
      return device
    end
  end
  return devices[1]
end

local function request_device_list()
  local response = run_session(pack_container(CONTAINER_COMMAND, CMD_GET_DEVICES))
  local blocks = parse_stream(response)
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      local payload = block.payload
      if #payload < 2 then
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
        table.insert(devices, {
          vendor_id = vendor_id,
          product_id = product_id,
          vendor_name = vendor_name,
          product_name = product_name,
        })
      end
      return devices
    end
  end
  return {}
end

local function request_with_device(device, command_packets)
  local request = {}
  table.insert(request, pack_container(CONTAINER_COMMAND, CMD_CONNECT_DEVICE, le_u32(device.vendor_id) .. le_u32(device.product_id)))
  table.insert(request, pack_container(CONTAINER_COMMAND, CMD_OPEN_SESSION, le_u32(1)))
  for _, packet in ipairs(command_packets or {}) do
    table.insert(request, packet)
  end
  table.insert(request, pack_container(CONTAINER_COMMAND, CMD_CLOSE_SESSION))
  local response = run_session(table.concat(request))
  return parse_stream(response)
end

local function command_response_code(blocks)
  local last_code = nil
  for _, block in ipairs(blocks or {}) do
    if block.ctype == CONTAINER_RESPONSE then
      last_code = block.code
    end
  end
  return last_code
end

local function command_response_codes(blocks)
  local codes = {}
  for _, block in ipairs(blocks or {}) do
    if block.ctype == CONTAINER_RESPONSE then
      codes[#codes + 1] = block.code
    end
  end
  return codes
end

local function request_device_prop_value(device, prop_code)
  local blocks = request_with_device(device, {
    pack_container(CONTAINER_COMMAND, CMD_GET_DEVICE_PROP_VALUE, le_u32(prop_code)),
  })
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      return block.payload
    end
  end
  return nil
end

local function read_focus_mode()
  local output_path = tmpname("d810-focus-mode")
  local command = string.format(
    "%s -t 5 %s --get-config focusmode > %s 2>/dev/null",
    shell_quote(TIMEOUT), shell_quote(GPHOTO), shell_quote(output_path)
  )
  os.execute(command)
  local output = read_file(output_path) or ""
  cleanup(output_path)
  local current = output:match("Current:%s*([^\\r\\n]+)")
  if not current then
    return nil
  end
  current = current:gsub("^%s+", ""):gsub("%s+$", "")
  if current:lower() == "manual" then
    return 3, current
  end
  if current:lower() == "af%-s" then
    return 1, current
  end
  if current:lower() == "af%-c" then
    return 2, current
  end
  return nil, current
end

local function request_device_prop_desc(device, prop_code)
  local blocks = request_with_device(device, {
    pack_container(CONTAINER_COMMAND, CMD_GET_DEVICE_PROP_DESC, le_u32(prop_code)),
  })
  for _, block in ipairs(blocks) do
    if block.ctype == CONTAINER_DATA then
      return block.payload
    end
  end
  return nil
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

local function emit_json(payload)
  io.write("Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n")
  io.write(payload)
  io.write("\n")
end

local function emit_error(status, message)
  emit_json(string.format(
    '{"ok":false,"status":"%s","message":"%s"}',
    json_escape(status),
    json_escape(message or "")
  ))
end

local function emit_ok(status, extra)
  local parts = {
    string.format('"ok":true'),
    string.format('"status":"%s"', json_escape(status)),
    '"backend":"ddserver"',
  }
  if extra then
    for k, v in pairs(extra) do
      if type(v) == "boolean" then
        table.insert(parts, string.format('"%s":%s', k, v and "true" or "false"))
      elseif type(v) == "number" then
        table.insert(parts, string.format('"%s":%s', k, tostring(v)))
      else
        table.insert(parts, string.format('"%s":"%s"', k, json_escape(v)))
      end
    end
  end
  emit_json("{" .. table.concat(parts, ",") .. "}")
end

local function frame_write(data)
  local handle = assert(io.open(FRAME_PATH, "wb"))
  handle:write(data)
  handle:close()
  local last_good = io.open(FRAME_LAST_GOOD, "wb")
  if last_good then
    last_good:write(data)
    last_good:close()
  end
  local meta = io.open(FRAME_META, "wb")
  if meta then
    meta:write(string.format("status=%s\n", "updated"))
    meta:write(string.format("frameBytes=%s\n", tostring(#data)))
    meta:write(string.format("framePath=%s\n", FRAME_PATH))
    meta:write(string.format("savedTo=%s\n", FRAME_PATH))
    meta:write("liveView=true\n")
    meta:close()
  end
end

local function collect_frame_from_blocks(blocks)
  local frame
  local last_response = "capture_failed"
  for _, block in ipairs(blocks or {}) do
    if block.ctype == CONTAINER_DATA and type(block.payload) == "string" then
      local candidate = block.payload
      if #candidate > 384 then
        candidate = candidate:sub(385)
      end
      local soi = candidate:find("\255\216", 1, true)
      if soi and soi > 1 then
        candidate = candidate:sub(soi)
      end
      if candidate:sub(1, 2) == "\255\216" then
        local eoi = candidate:find("\255\217", 3, true)
        if eoi then
          candidate = candidate:sub(1, eoi + 1)
        end
        frame = candidate
      end
    end
    if block.ctype == CONTAINER_RESPONSE and block.code == MTP_NOT_LIVE_VIEW then
      last_response = "not_live_view"
    end
  end
  return frame, last_response
end

local function capture_live_frame(device, packets)
  local blocks = request_with_device(device, packets)
  local frame, last_response = collect_frame_from_blocks(blocks)
  local response_codes = command_response_codes(blocks)
  local data_lengths = {}
  for _, block in ipairs(blocks or {}) do
    if block.ctype == CONTAINER_DATA then
      data_lengths[#data_lengths + 1] = tostring(#(block.payload or ""))
    end
  end
  if frame then
    return frame, last_response, response_codes, data_lengths
  end
  return nil, last_response, response_codes, data_lengths
end

local function do_status()
  local devices = request_device_list()
  local device = select_device(devices)
  local live_view = false
  local battery_percent = nil
  local ac_power = nil
  if device then
    local payload = request_device_prop_value(device, PROP_LIVE_VIEW_STATUS)
    if payload == nil then
      emit_error("transport_error", "camera PTP status probe failed")
      return
    end
    live_view = payload ~= nil and #payload > 0 and payload:byte(1) == 1
    local battery_payload = request_device_prop_value(device, PROP_BATTERY_LEVEL)
    if battery_payload ~= nil and #battery_payload > 0 then
      battery_percent = battery_payload:byte(1)
    end
    local ac_payload = request_device_prop_value(device, PROP_AC_POWER)
    if ac_payload ~= nil and #ac_payload > 0 then
      ac_power = ac_payload:byte(1) == 1
    end
  end
  local extra = {
    cameraDetected = device ~= nil,
    connected = device ~= nil,
    liveView = live_view,
    framePath = FRAME_PATH,
  }
  if battery_percent ~= nil then
    extra.batteryPercent = battery_percent
  end
  if ac_power ~= nil then
    extra.acPower = ac_power
  end
  emit_ok("ready", extra)
end

local function do_live_start()
  local devices = request_device_list()
  local device = select_device(devices)
  if not device then
    emit_error("camera_missing", "no imaging device found on ddserver")
    return
  end
  local packets = {
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    -- Nikon requires SDRAM recording before StartLiveView.  The persistent
    -- bridge already does this; keep the active legacy path equivalent.
    pack_data_command(CMD_SET_DEVICE_PROP_VALUE, le_u32(PROP_RECORDING_MEDIA), string.char(1)),
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    pack_container(CONTAINER_COMMAND, NIKON_START_LIVE_VIEW),
  }
  local blocks = request_with_device(device, packets)
  local response_codes = command_response_codes(blocks)
  local media_response_code = response_codes[4]
  local response_code = response_codes[6]
  if media_response_code ~= MTP_RESPONSE_OK then
    emit_error("liveview_start_failed", string.format("camera SDRAM select response 0x%04X", media_response_code or 0))
    return
  end
  if response_code ~= MTP_RESPONSE_OK then
    emit_error("liveview_start_failed", string.format("camera live start response 0x%04X", response_code or 0))
    return
  end
  emit_ok("liveview_on", { cameraDetected = true, connected = true, liveView = true, framePath = FRAME_PATH, responseCode = response_code })
end

local function do_live_stop()
  local devices = request_device_list()
  local device = select_device(devices)
  if not device then
    emit_error("camera_missing", "no imaging device found on ddserver")
    return
  end
  local packets = {
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    pack_container(CONTAINER_COMMAND, NIKON_END_LIVE_VIEW),
  }
  local blocks = request_with_device(device, packets)
  local response_codes = command_response_codes(blocks)
  local response_code = response_codes[4]
  if response_code ~= MTP_RESPONSE_OK then
    emit_error("liveview_stop_failed", string.format("camera live stop response 0x%04X", response_code or 0))
    return
  end
  emit_ok("liveview_off", { cameraDetected = true, connected = true, liveView = false, framePath = FRAME_PATH, responseCode = response_code })
end

local function do_af()
  local devices = request_device_list()
  local device = select_device(devices)
  if not device then
    emit_error("camera_missing", "no imaging device found on ddserver")
    return
  end
  local focus_mode, focus_label = read_focus_mode()
  if focus_mode == 3 or focus_mode == 4 then
    emit_error("focus_manual", "autofocus unavailable: camera focus mode is manual")
    return
  end
  local packets = {
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    pack_container(CONTAINER_COMMAND, NIKON_AF_DRIVE),
  }
  local blocks = request_with_device(device, packets)
  local response_codes = command_response_codes(blocks)
  local response_code = response_codes[4]
  local trailing_response_code = response_codes[5]
  if response_code ~= MTP_RESPONSE_OK then
    local sequence = {}
    for _, code in ipairs(response_codes) do
      sequence[#sequence + 1] = string.format("0x%04X", code)
    end
    emit_error("camera_af_failed", string.format("camera AF response 0x%04X sequence=%s", response_code or 0, table.concat(sequence, ",")))
    return
  end
  emit_ok("ok", {
    cameraDetected = true,
    connected = true,
    liveView = false,
    framePath = FRAME_PATH,
    responseCode = response_code,
    trailingResponseCode = trailing_response_code,
    focusMode = focus_mode,
    focusModeLabel = focus_label,
  })
end

local function do_shutter()
  local devices = request_device_list()
  local device = select_device(devices)
  if not device then
    emit_error("camera_missing", "no imaging device found on ddserver")
    return
  end
  local packets = {
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    pack_container(CONTAINER_COMMAND, NIKON_SHUTTER, le_u32(0xFFFFFFFF) .. le_u32(0x0000)),
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
  }
  request_with_device(device, packets)
  emit_ok("ok", { cameraDetected = true, connected = true, liveView = false, framePath = FRAME_PATH })
end

local function do_frame()
  local devices = request_device_list()
  local device = select_device(devices)
  if not device then
    emit_error("camera_missing", "no imaging device found on ddserver")
    return
  end
  local packets = {
    pack_container(CONTAINER_COMMAND, NIKON_DEVICE_READY),
    pack_container(CONTAINER_COMMAND, NIKON_GET_LIVE_VIEW_IMAGE),
  }
  local frame, last_response, response_codes, data_lengths = capture_live_frame(device, packets)
  if not frame then
    local sequence = {}
    for _, code in ipairs(response_codes or {}) do
      sequence[#sequence + 1] = string.format("0x%04X", code)
    end
    local detail = "live view frame unavailable"
    if #sequence > 0 then
      detail = detail .. " response=" .. table.concat(sequence, ",")
    end
    if #(data_lengths or {}) > 0 then
      detail = detail .. " data=" .. table.concat(data_lengths, ",")
    end
    emit_error(last_response or "capture_failed", detail)
    return
  end
  frame_write(frame)
  emit_ok("updated", {
    cameraDetected = true,
    connected = true,
    liveView = true,
    framePath = FRAME_PATH,
    savedTo = FRAME_PATH,
  })
end

local action = arg[1] or "status"
local mode = arg[2] or "status"

if action ~= "client" then
  mode = action
end

if mode == "status" then
  do_status()
elseif mode == "live-start" then
  do_live_start()
elseif mode == "live-stop" then
  do_live_stop()
elseif mode == "af" then
  do_af()
elseif mode == "shutter" then
  do_shutter()
elseif mode == "frame" then
  do_frame()
elseif mode == "recover" then
  do_status()
else
  emit_error("unknown", "unknown action: " .. tostring(mode))
end
