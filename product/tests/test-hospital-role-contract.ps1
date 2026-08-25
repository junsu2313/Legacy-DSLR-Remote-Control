$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$cgiRoot = Join-Path $repoRoot 'app\remote-ui\cgi-bin'
$flutterMain = Get-Content -LiteralPath (Join-Path $repoRoot 'app\flutter_camera\lib\main.dart') -Raw -Encoding utf8
$batteryWorker = Get-Content -LiteralPath (Join-Path $cgiRoot 'battery-worker') -Raw -Encoding utf8
$sessionHealth = Get-Content -LiteralPath (Join-Path $cgiRoot 'session-health') -Raw -Encoding utf8
$runtimeGuardian = Get-Content -LiteralPath (Join-Path $cgiRoot 'runtime-guardian') -Raw -Encoding utf8
$diagnose = Get-Content -LiteralPath (Join-Path $cgiRoot 'diagnose-recover') -Raw -Encoding utf8
$sessionManager = Get-Content -LiteralPath (Join-Path $cgiRoot 'session-manager') -Raw -Encoding utf8
$action = Get-Content -LiteralPath (Join-Path $cgiRoot 'action-v21') -Raw -Encoding utf8
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'deploy\openwrt\d810-minimal-overlay.manifest') -Raw -Encoding utf8

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw "FAIL: $Message" }
  Write-Output "PASS: $Message"
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Message) {
  if ($Text.Contains($Needle)) { throw "FAIL: $Message" }
  Write-Output "PASS: $Message"
}

Assert-NotContains $flutterMain '_forceLowBatteryTest' 'S10 uses the measured camera battery'
Assert-Contains $flutterMain 'batteryPercent = status.batteryPercent' 'S10 displays the server battery observation'
Assert-Contains $batteryWorker 'bridge_request_timed BATTERY_STATUS 5' 'battery monitor requests a fresh read through the shared PTP bridge'
Assert-NotContains $batteryWorker 'gphoto2' 'battery monitor cannot open a competing gphoto session'
Assert-Contains $sessionHealth 'bridge_request STATUS' 'session-health emits a read-only observation'
Assert-NotContains $sessionHealth 'bridge_request MAINTAIN' 'session-health cannot mutate bridge runtime state'
Assert-Contains $runtimeGuardian 'request_diagnosis()' 'guardian reports abnormal observations to DIAG'
Assert-NotContains $runtimeGuardian 'bridge_request RECOVER' 'guardian cannot execute PTP treatment'
Assert-NotContains $runtimeGuardian 'ws_start ' 'guardian cannot restart a worker'
Assert-Contains $diagnose 'confirm_diagnosis()' 'DIAG owns disease confirmation'
Assert-Contains $diagnose 'request_treatment()' 'DIAG sends an authorized treatment request'
Assert-Contains $diagnose 'D810D_DIAGNOSTIC_LOG' 'DIAG keeps a dedicated bounded medical record'
Assert-NotContains $diagnose 'bridge_stop ' 'DIAG cannot stop the bridge directly'
Assert-Contains $sessionManager 'execute_treatment()' 'session-manager owns treatment execution'
Assert-Contains $sessionManager 'treatment=$TREATMENT_CODE diagnosisId=$TREATMENT_DIAGNOSIS_ID' 'treatment logs retain the diagnosis ID'
Assert-Contains $sessionManager 'treatment_log()' 'session-manager writes treatment into the medical record'
Assert-Contains $action 'delegating recovery judgment to DIAG' 'manual recovery cannot bypass DIAG'
Assert-NotContains $action 'action_bridge_request RECOVER' 'action ingress cannot execute treatment directly'
Assert-NotContains $manifest '/www/cgi-bin/stack-guardian' 'legacy self-healing guardian is outside the active runtime'

Write-Output 'PASS: hospital role contract'
