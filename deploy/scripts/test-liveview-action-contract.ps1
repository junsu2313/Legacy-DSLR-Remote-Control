$ErrorActionPreference = 'Stop'

$bridge = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\d810bridge.lua" -Raw -Encoding utf8
$action = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\action-v21" -Raw -Encoding utf8
$sessionManager = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\session-manager" -Raw -Encoding utf8
$capturedPreview = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\captured-preview" -Raw -Encoding utf8
$capturedObject = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\captured-object" -Raw -Encoding utf8
$capturedNef = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\captured-nef" -Raw -Encoding utf8
$bridge = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\d810bridge.lua" -Raw -Encoding utf8
$ui = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\0716-1.html" -Raw -Encoding utf8
$variantEnv = Get-Content -LiteralPath "$PSScriptRoot\..\remote-ui\cgi-bin\variant-v21-env.sh" -Raw -Encoding utf8

function Assert-Contains([string]$text, [string]$pattern, [string]$message) {
  if ($text -notmatch [regex]::Escape($pattern)) {
    throw "FAIL: $message"
  }
  Write-Output "PASS: $message"
}

Assert-Contains $bridge 'function BridgeSession:restore_live_view_after_connect()' 'session recovery has a live-view restore path'
Assert-Contains $bridge 'self.live_session_id, self.live_session_label = ensure_live_session()' 'live session identity is restored from the existing session'
Assert-Contains $bridge 'function BridgeSession:af()' 'bridge exposes AF as an independent action'
Assert-Contains $bridge 'function BridgeSession:shutter()' 'bridge exposes SHOT as an independent action'
Assert-Contains $bridge 'self:execute(NIKON_CHANGE_CAMERA_MODE, { 1 })' 'program shutter enters Nikon PC control mode'
Assert-Contains $bridge 'function DdServerWire:release_camera_control()' 'program shutter can return camera controls to the body'
Assert-Contains $bridge 'self:release_camera_control()' 'program shutter releases camera controls after capture'
Assert-Contains $bridge 'function BridgeSession:raw_mode()' 'bridge exposes RAW mode as an independent action'
Assert-Contains $bridge 'PROP_COMPRESSION_SETTING, string.char(COMPRESSION_RAW)' 'RAW mode explicitly sets Nikon compression to RAW only'
Assert-Contains $bridge 'local data_container = pack_container(CONTAINER_DATA, code, payload):sub(5)' 'property writes use a separate PTP data container'
Assert-Contains $bridge 'le_u32(4 + #command_container + #data_container)' 'ddserver receives command and data in one framed packet'
Assert-Contains $bridge 'acquire_lock(COMMAND_ACTION_LOCK, COMMAND_LOCK_TIMEOUT_MS)' 'camera actions share the command lock'
Assert-Contains $action 'recover)' 'action endpoint exposes session recovery'
Assert-Contains $action 'OUT=$(bridge_request RECOVER)' 'session recovery forwards to the existing bridge session'
Assert-Contains $action 'OUT=$(bridge_request RAW_MODE)' 'RAW action forwards to the existing bridge session'
Assert-Contains $action 'OUT=$(bridge_request UNLOCK)' 'unlock action returns control to the camera body'
Assert-Contains $action 'restoring live session after recovery' 'action endpoint restores live mode after recovery'
Assert-Contains $sessionManager 'HARD_RESET_REQUEST" -eq 0' 'new browser sessions do not inherit the previous live session'
Assert-Contains $sessionManager 'new browser session requested; clearing prior live session' 'new browser sessions clear live-session state'
Assert-Contains $sessionManager 'purge_runtime_tmp' 'new browser sessions clear runtime caches'
Assert-Contains $capturedPreview '. "$SCRIPT_DIR/variant-v21-env.sh"' 'captured JPEG preview uses the v21 runtime environment'
Assert-Contains $capturedObject 'CAPTURED_OBJECT_JPEG' 'full-size JPEG endpoint streams the captured object'
Assert-Contains $capturedObject 'LOCK_PATH=${D810D_CAPTURED_OBJECT_LOCK:-/tmp/d810-captured-object-download.lock}' 'full-size JPEG endpoint serializes object downloads'
Assert-Contains $capturedObject 'dd bs=65536' 'full-size JPEG endpoint forwards the binary stream without buffering it'
Assert-Contains $capturedNef 'CAPTURED_OBJECT_NEF' 'NEF endpoint requests the latest raw object'
Assert-Contains $capturedNef 'dd bs=65536' 'NEF endpoint forwards the raw stream without buffering it'
Assert-Contains $bridge 'function BridgeSession:select_latest_nef_object()' 'bridge can select a recent NEF object'
Assert-Contains $bridge 'session:captured_object_stream(conn, "nef")' 'bridge reuses chunk streaming for NEF delivery'
Assert-Contains $bridge 'self:_wire():stop_live_view()' 'full-size JPEG pauses live view during object transfer'
Assert-Contains $bridge 'self:_wire():start_live_view()' 'full-size JPEG restores live view after object transfer'
Assert-Contains $bridge 'object_wire.timeout = CAPTURED_OBJECT_TIMEOUT' 'full-size JPEG uses an object-transfer timeout'
Assert-Contains $bridge 'captured object size mismatch' 'full-size JPEG validates the completed object size'
Assert-Contains $bridge 'CMD_GET_PARTIAL_OBJECT = 0x101B' 'full-size JPEG uses PTP partial-object transfer'
Assert-Contains $variantEnv 'D810D_CAPTURED_OBJECT_CHUNK_SIZE=2097152' 'full-size JPEG uses the measured 2MB transfer sweet spot'
Assert-Contains $variantEnv 'D810D_CAPTURED_OBJECT_SINGLE_CHUNK_LIMIT=4194304' 'small full-size JPEG uses one bounded transfer chunk'
Assert-Contains $bridge 'return self.last_captured_object_info' 'full-size JPEG reuses the object selected by captured preview'
Assert-Contains $bridge 'effective_chunk_size = expected_size' 'small full-size JPEG is requested as one bounded chunk'
Assert-Contains $bridge 'delivery = "http_stream"' 'full-size JPEG is delivered without a tmp image file'
Assert-Contains $bridge 'conn:write(chunk)' 'full-size JPEG streams chunks directly to HTTP'
Assert-Contains $bridge 'pcall(function() conn:close() end)' 'full-size JPEG response closes before live-view restoration'
Assert-Contains $bridge 'wireMs = wire_ms' 'full-size JPEG measures PTP wire time separately'
Assert-Contains $bridge 'writeMs = socket_write_ms' 'full-size JPEG measures socket write time separately'
Assert-Contains $bridge 'chunkAvgMs = chunk_count > 0' 'full-size JPEG records per-chunk latency'
Assert-Contains $bridge 'captured object JPEG markers were invalid' 'full-size JPEG validates JPEG boundaries before publish'
Assert-Contains $ui 'capturedObject: "/cgi-bin/captured-object"' 'full-size viewer uses the captured object endpoint'
Assert-Contains $ui 'const keepLiveForCameraAction = ["af", "shutter"].includes(action);' 'UI keeps live view for AF and SHOT'
Assert-Contains $ui '!keepLiveForCameraAction && liveMode' 'UI does not stop live view before AF or SHOT'
Assert-Contains $ui 'async function recoverSession(reason = "runtime health check")' 'UI has an automatic recovery loop'
Assert-Contains $ui 'scheduleSessionRecovery("WebSocket disconnected", false)' 'WebSocket failures trigger recovery without refresh'
Assert-Contains $ui 'scheduleSessionRecovery("live frame unavailable", false)' 'frame failures trigger recovery without refresh'
Assert-Contains $ui 'backendState === "degraded" || backendState === "recovering"' 'degraded backend status triggers recovery without refresh'
Assert-Contains $ui 'capturedPreview: "/cgi-bin/captured-preview"' 'shot preview uses the captured JPEG endpoint'
Assert-Contains $ui 'class="shot-preview"' 'shot preview is rendered in the live-view corner'
Assert-Contains $ui 'async function requestPortraitViewer()' 'full-size shot viewer requests portrait mode'
Assert-Contains $ui 'screen.orientation.lock("portrait")' 'shot viewer requests a portrait orientation lock'
Assert-Contains $ui 'shotViewer.requestFullscreen' 'shot viewer requests full-screen presentation'
Assert-Contains $ui 'void requestPortraitViewer();' 'shot viewer requests full-screen immediately from the thumbnail tap'
Assert-Contains $ui 'shotViewerImage.src = shotThumbImage.src;' 'shot viewer displays the thumbnail immediately while the full JPEG loads'
Assert-Contains $ui 'shotViewerImage.src = `${API.capturedObject}?t=${Date.now()}`;' 'mobile viewer streams the full JPEG directly into the image element'
Assert-Contains $ui 'width: min(94vw, calc(94vh * 7360 / 4912));' 'portrait viewer gives the JPEG long edge three-percent side margins'
Assert-Contains $ui 'aspect-ratio: 7360 / 4912;' 'portrait viewer preserves the D810 JPEG aspect ratio'
Assert-Contains $ui 'shotViewerImage.addEventListener("click", () => void hideShotViewer());' 'tapping the full-size JPEG returns to live view'
Assert-Contains $ui 'const retryDelays = [0, 450, 900, 1800, 3000];' 'shot preview retries while the camera finishes saving'

Write-Output 'PASS: live-view AF/shutter contract checks completed'
