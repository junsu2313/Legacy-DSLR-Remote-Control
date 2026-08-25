$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$bridge = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\d810bridge.lua') -Raw -Encoding utf8
$bridgeCommon = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\bridge-common.sh') -Raw -Encoding utf8
$action = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\action-v21') -Raw -Encoding utf8
$cameraApi = Get-Content -LiteralPath (Join-Path $repoRoot 'app\flutter_camera\lib\camera_api.dart') -Raw -Encoding utf8
$flutterMain = Get-Content -LiteralPath (Join-Path $repoRoot 'app\flutter_camera\lib\main.dart') -Raw -Encoding utf8
$sessionManager = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\session-manager') -Raw -Encoding utf8
$runtimeGuardian = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\runtime-guardian') -Raw -Encoding utf8
$diagnoseRecover = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\diagnose-recover') -Raw -Encoding utf8
$statusV21 = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\status-v21') -Raw -Encoding utf8
$projectTransport = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\project-ddserver-runtime') -Raw -Encoding utf8
$projectDependencies = Get-Content -LiteralPath (Join-Path $repoRoot 'app\remote-ui\cgi-bin\project-runtime-dependencies.sh') -Raw -Encoding utf8

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw "FAIL: $Message" }
  Write-Output "PASS: $Message"
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text.Contains($Needle)) { throw "FAIL: $Message" }
  Write-Output "PASS: $Message"
}

Assert-Contains $bridge 'function BridgeSession:update_readiness(extra)' 'bridge owns one unified readiness state machine'
Assert-Contains $bridge 'if extra[key] ~= nil then' 'explicit false response fields override stale internal true values'
Assert-Contains $bridge 'appReady = state == "ready" or state == "limited"' 'normal and manufacturer-limited states remain operational'
Assert-Contains $bridge 'liveViewLimited = capability_certified and self.live_view_limited == true' 'status distinguishes a manufacturer restriction from a live-view fault'
Assert-Contains $bridge 'fail("liveview_limited", "low_battery")' 'low battery blocks LIVE without fabricating a transport failure'
Assert-Contains $bridge 'if status == "liveview_limited" or status == "operation_limited" then' 'restricted operations do not revoke capability certification'
Assert-Contains $bridge 'readinessAverageMs = average_ms' 'bridge reports measured average readiness time'
Assert-Contains $bridge 'D810D_READINESS_STATS_PATH' 'readiness timing survives session and daemon replacement'
Assert-Contains $bridge 'self.live_view_faulted = true' 'failed live-view verification latches a readiness fault'
Assert-Contains $bridge 'self.live_view_faulted = false' 'a verified live frame clears the fault latch'
Assert-Contains $bridge 'function BridgeSession:certify_capabilities()' 'READY requires a session-scoped capability certification'
Assert-Contains $bridge 'wire:wait_device_ready(3000, 20)' 'certification proves immediate command readiness'
Assert-Contains $bridge 'wire:get_storage_info(storage_ids[1])' 'certification proves camera storage access'
Assert-Contains $bridge 'wire:get_object_handles(storage_ids[1], PTP_ALL_OBJECT_FORMATS, PTP_ROOT_PARENT)' 'certification proves captured-file listing access'
Assert-Contains $bridge 'local frame = wire:live_view_frame()' 'certification receives a real live-view JPEG'
Assert-Contains $bridge 'self:invalidate_capability_certification("transport_closed")' 'transport replacement invalidates stale capability evidence'
Assert-Contains $bridge 'function BridgeSession:record_capability_failure(command_name, err)' 'core command failures revoke stale READY evidence'
Assert-Contains $bridge 'if command_name == "AF" and status == "focus_failed" then' 'scene focus failure does not falsely condemn the runtime'
Assert-Contains $bridge 'status:match("^invalid_")' 'invalid user input does not falsely condemn the runtime'
Assert-Contains $bridge 'capabilityCertified = capability_certified' 'status publishes capability certification evidence'
Assert-Contains $bridge 'Persisted state is diagnostic history, not current readiness evidence.' 'daemon restart cannot trust stale READY evidence'
Assert-NotContains $bridge 'elseif legacy_ready then' 'hardware detection cannot fabricate transport readiness'
Assert-Contains $bridge 'live_start transport failed; reconnecting and retrying once' 'live start retries one safe transport recovery'
Assert-Contains $bridge 'AF transport failed; reconnecting and retrying once' 'AF retries one safe transport recovery'
Assert-NotContains $bridge 'shutter transport failed; reconnecting and retrying once' 'shutter is never retransmitted after an ambiguous transport failure'
Assert-Contains $bridgeCommon 'bridge_app_ready()' 'shell actions consume the unified readiness declaration'
Assert-Contains $bridgeCommon 'project_ddserver_start()' 'project runtime owns direct ddserver startup'
Assert-Contains $bridgeCommon 'project_ddserver_owned_pid()' 'project runtime tracks only its owned ddserver process'
Assert-Contains $bridgeCommon 'project_ddserver_existing_pid()' 'project runtime can identify one exact orphaned ddserver after pidfile loss'
Assert-Contains $bridgeCommon '"$executable" "$@"' 'direct daemon startup preserves the selected interpreter'
Assert-Contains $bridgeCommon 'bridge_declares_healthy' 'an active bridge connection is authoritative transport evidence'
Assert-Contains $bridgeCommon 'adopted healthy project transport' 'guardian adopts the healthy project process instead of spawning competitors'
Assert-Contains $projectTransport 'project_ddserver_restart' 'bridge recovery uses the project runtime transport controller'
Assert-Contains $sessionManager 'boot_transport_stage' 'project boot serializes transport before PTP boot'
Assert-Contains $sessionManager 'boot_runtime_dependency_stage' 'project boot prepares optional native runtime dependencies on demand'
Assert-Contains $sessionManager 'camera_contract_ready()' 'camera startup has a pre-delivery readiness barrier'
Assert-Contains $sessionManager 'if camera_contract_ready "$status_out"' 'camera startup does not require websocket delivery before workers start'
Assert-Contains $sessionManager 'if status_contract_ready "$final_status_out"' 'final startup still requires the complete app readiness contract'
Assert-Contains $sessionManager '"stage":"delivery"' 'existing runtime reports final delivery failure at the correct stage'
Assert-Contains $projectDependencies 'project_nixio_prepare()' 'project runtime owns nixio preparation'
Assert-Contains $projectDependencies 'sha256sum' 'project runtime verifies the pinned nixio artifact'
Assert-Contains $projectDependencies '/tmp/d810-project-runtime/lua/5.1' 'nixio is loaded from volatile project runtime state'
Assert-NotContains $projectDependencies 'opkg install' 'nixio preparation never mutates the stock package database'
Assert-Contains $sessionManager '*''"capabilityCertified":true''*' 'project boot waits for capability certification'
Assert-Contains $sessionManager '*''"captureReady":true''*' 'project boot waits for the capture route'
Assert-Contains $sessionManager '*''"storageReady":true''*' 'project boot waits for storage access'
Assert-Contains $sessionManager '*''"fileRouteReady":true''*' 'project boot waits for captured-file access'
Assert-Contains $sessionManager '*''"liveViewReady":true''*|*''"liveViewLimited":true''*' 'project boot accepts an explicit manufacturer-limited LV path'
Assert-Contains $sessionManager 'final_delivery_stage()' 'project boot waits for the application frame-delivery path'
Assert-Contains $sessionManager '*''"deliveryReady":true''*' 'project boot cannot report READY before delivery is healthy'
Assert-Contains $runtimeGuardian 'project_ddserver_ready' 'runtime guardian observes project transport health'
Assert-Contains $sessionManager 'stage=ptp_boot attempt=1/1' 'app launch issues exactly one camera boot attempt'
Assert-NotContains $sessionManager 'restarting bridge stage only' 'startup failure never rewinds the bridge stage'
Assert-Contains $sessionManager 'recoveryScheduled":true' 'a failed one-shot boot hands recovery to the session guardian'
Assert-Contains $runtimeGuardian 'request_diagnosis project_transport_unavailable' 'guardian delegates transport judgment to DIAG'
Assert-Contains $runtimeGuardian 'request_diagnosis live_view_not_ready' 'guardian delegates live-view judgment to DIAG'
Assert-Contains $runtimeGuardian '*''"liveViewLimited":true''*' 'guardian does not repair a manufacturer-enforced restriction'
Assert-Contains $statusV21 '\"faultActive\"' 'status exposes the active diagnosed fault'
Assert-Contains $diagnoseRecover 'MODE=${1:-auto}' 'DIAG defaults to automatic diagnosis and recovery'
Assert-Contains $diagnoseRecover 'request_treatment()' 'DIAG requests treatment without executing runtime mutations'
Assert-Contains $diagnoseRecover 'executor=session-manager' 'DIAG assigns every automatic treatment to session-manager'
Assert-Contains $sessionManager 'execute_treatment()' 'session-manager owns the treatment execution table'
Assert-Contains $sessionManager 'role=executor treatment=' 'session-manager logs diagnosis-linked treatment execution'
Assert-NotContains $diagnoseRecover 'bridge_stop ' 'DIAG never stops the bridge directly'
Assert-NotContains $diagnoseRecover 'bridge_request RECOVER' 'DIAG never mutates the PTP session directly'
Assert-NotContains $runtimeGuardian 'bridge_request RECOVER' 'guardian never repairs the PTP session directly'
Assert-NotContains $runtimeGuardian 'ws_start ' 'guardian never restarts workers directly'
Assert-Contains $action 'diagnose-recover" auto' 'the single DIAG action delegates recovery selection internally'
Assert-Contains $flutterMain 'Icons.error' 'the failed readiness circle becomes a red alert'
Assert-NotContains $flutterMain '_showDiagnosticControls()' 'DIAG does not ask the user to choose a recovery operation'
Assert-NotContains $bridge '/etc/init.d/ddserver' 'bridge recovery never depends on an OpenWrt boot service'
Assert-Contains $action 'REQUIRES_APP_READY=1' 'camera mutations are gated until app readiness'
Assert-Contains $cameraApi "json.containsKey('appReady')" 'Flutter prefers the server readiness contract'
Assert-Contains $cameraApi 'final bool liveViewLimited;' 'Flutter models limited LV separately from failure'
Assert-Contains $cameraApi 'Future<CameraRuntimeStatus> bootstrapRuntime()' 'Flutter explicitly starts the project runtime'
Assert-Contains $flutterMain '_bootstrapProjectRuntime()' 'app startup invokes project boot without Opal boot hooks'
Assert-Contains $flutterMain 'const _BouncingEllipsis()' 'Flutter displays active preparation instead of false READY'

Write-Output 'PASS: Opal unified readiness contract'
