$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$docPath = Join-Path $repoRoot 'docs\diagnostic-taxonomy-2026-08-26.md'
$bridgePath = Join-Path $repoRoot 'app\remote-ui\cgi-bin\d810bridge.lua'
$diagnoseRecoverPath = Join-Path $repoRoot 'app\remote-ui\cgi-bin\diagnose-recover'
$catalogPath = Join-Path $repoRoot 'app\remote-ui\cgi-bin\diagnostic-catalog.tsv'
$cgiRoot = Join-Path $repoRoot 'app\remote-ui\cgi-bin'

$doc = Get-Content -LiteralPath $docPath -Raw -Encoding utf8
$bridge = Get-Content -LiteralPath $bridgePath -Raw -Encoding utf8
$diagnoseRecover = Get-Content -LiteralPath $diagnoseRecoverPath -Raw -Encoding utf8
$catalog = Get-Content -LiteralPath $catalogPath -Encoding utf8

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
  if (-not $Text.Contains($Needle)) { throw "FAIL: $Message ($Needle)" }
  Write-Output "PASS: $Message"
}

foreach ($state in @('NORMAL', 'LIMITED', 'FAULT', 'UNKNOWN', 'TRANSIENT')) {
  Assert-Contains $doc $state "taxonomy defines $state"
}

foreach ($field in @('id', 'domain', 'component', 'state', 'evidenceState',
    'reason', 'observedValue', 'expectedValue', 'source', 'observedAtMs',
    'impact', 'blockedBy', 'response', 'owner', 'retryable', 'confidence',
    'displayColor')) {
  Assert-Contains $doc "``$field``" "diagnostic result requires $field"
}

foreach ($domainPrefix in @('CAMERA.', 'POWER.', 'RUNTIME.', 'PTP.', 'SESSION.',
    'COMMAND.', 'LV.', 'DELIVERY.', 'APP.', 'STORAGE.', 'CAPTURE.')) {
  Assert-Contains $doc "``$domainPrefix" "taxonomy contains $domainPrefix findings"
}

$bridgeErrors = [regex]::Matches($bridge, 'fail\("([a-z0-9_]+)"') |
  ForEach-Object { $_.Groups[1].Value } |
  Sort-Object -Unique

$statusTokens = foreach ($file in Get-ChildItem -LiteralPath $cgiRoot -File) {
  $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  [regex]::Matches($text, '"status"\s*:\s*"([a-z0-9_]+)"') |
    ForEach-Object { $_.Groups[1].Value }
}

$nonErrorStatuses = @(
  'captured_images_ready', 'detected', 'fault_found', 'live_fallback_ready',
  'logged', 'probe', 'ready', 'recovered', 'restarting', 'stopping',
  'stream_only', 'user_action_required'
)
$cgiErrors = $statusTokens |
  Where-Object { $_ -notin $nonErrorStatuses } |
  Sort-Object -Unique

$allCurrentErrors = @($bridgeErrors) + @($cgiErrors) | Sort-Object -Unique
foreach ($errorToken in $allCurrentErrors) {
  Assert-Contains $doc $errorToken "current error token is classified"
}

foreach ($broadStatus in @('transport_error', 'camera_missing', 'capture_failed',
    'boot_failed', 'worker_failed')) {
  Assert-Contains $doc $broadStatus "legacy broad status is explicitly mapped"
}

Assert-Contains $doc 'UNKNOWN + blockedBy' 'downstream checks preserve causal blocking'
Assert-Contains $doc 'POLICY.MINIMUM_SCOPE_RECOVERY' 'responses use minimum-scope recovery'
Assert-Contains $doc 'POLICY.NON_DESTRUCTIVE_DIAG' 'ordinary diagnosis is non-destructive'
Assert-Contains $doc 'POLICY.STATE_FROM_FIELDS_ONLY' 'UI does not infer state from display text'
Assert-Contains $doc 'USER_NOTIFY' 'user-action findings notify without automatic mutation'
Assert-Contains $doc 'autoRecovery=false' 'user-action findings disable automatic recovery'
Assert-Contains $doc 'owner=USER' 'user-action findings identify the user as owner'

foreach ($contractToken in @('diagnosis_log()', 'confirm_diagnosis()',
    'diagnosisPhase', 'diagnosisConfirmed', 'treatmentAllowed',
    'phase=confirmation', 'phase=treatment', '"diagnosisPhase":"verification"',
    'emit_limited')) {
  Assert-Contains $diagnoseRecover $contractToken "DIAG execution contract contains $contractToken"
}

$diagnosticRows = foreach ($line in ($doc -split "`r?`n") ) {
  if ($line -match '^\| `([A-Z]+\.[A-Z0-9_]+)` \| (NORMAL|LIMITED|FAULT|TRANSIENT|UNKNOWN) \|') {
    [pscustomobject]@{ Id = $matches[1]; State = $matches[2] }
  }
}
$stateCounts = @{}
foreach ($row in $diagnosticRows) {
  if ($stateCounts.ContainsKey($row.State)) {
    $stateCounts[$row.State]++
  } else {
    $stateCounts[$row.State] = 1
  }
}
if ($diagnosticRows.Count -ne 87) { throw "FAIL: expected 87 diagnostic IDs, found $($diagnosticRows.Count)" }
if ($stateCounts.FAULT -ne 64 -or $stateCounts.LIMITED -ne 6 -or
    $stateCounts.NORMAL -ne 3 -or $stateCounts.TRANSIENT -ne 9 -or
    $stateCounts.UNKNOWN -ne 5) {
  throw "FAIL: unexpected diagnostic color/state distribution"
}
Write-Output 'PASS: 87 diagnoses have fixed state/color distribution'

$currentArea = ''
$areaRows = foreach ($line in ($doc -split "`r?`n")) {
  if ($line -match '^### .+ \[AREA:(CAMERA|PTP|COMMAND|LV|APP)\]') {
    $currentArea = $matches[1]
    continue
  }
  if ($currentArea -and $line -match '^\| ([A-Z]+) \| `([A-Z]+\.[A-Z0-9_]+)` \| ([^|]+) \|') {
    [pscustomobject]@{ Area = $currentArea; Source = $matches[1]; Id = $matches[2]; Color = $matches[3] }
  }
}
if ($areaRows.Count -ne 84) { throw "FAIL: expected 84 problem-area mappings, found $($areaRows.Count)" }
$duplicateAreaIds = $areaRows | Group-Object Id | Where-Object Count -ne 1
if ($duplicateAreaIds) { throw 'FAIL: a problem diagnosis is mapped to more than one primary area' }
foreach ($areaCount in @{ CAMERA = 23; PTP = 17; COMMAND = 6; LV = 17; APP = 21 }.GetEnumerator()) {
  $actual = @($areaRows | Where-Object Area -eq $areaCount.Key).Count
  if ($actual -ne $areaCount.Value) {
    throw "FAIL: $($areaCount.Key) expected $($areaCount.Value) mappings, found $actual"
  }
}
foreach ($normalId in @('COMMAND.INVALID_INPUT', 'COMMAND.FOCUS_NOT_ACQUIRED', 'LV.PRECONDITION_INACTIVE')) {
  if ($areaRows.Id -contains $normalId) { throw "FAIL: normal event was included as a problem mapping: $normalId" }
}
Write-Output 'PASS: 84 problem diagnoses have one primary area mapping'

$catalogRows = @($catalog | Where-Object { $_ -match '^([A-Z]+\.[A-Z0-9_]+)\t(.+)$' })
if ($catalogRows.Count -ne 84) { throw "FAIL: expected 84 diagnostic catalog entries, found $($catalogRows.Count)" }
$catalogIds = @($catalogRows | ForEach-Object { ($_ -split "`t", 2)[0] })
if (@($catalogIds | Sort-Object -Unique).Count -ne 84) { throw 'FAIL: diagnostic catalog contains duplicate IDs' }
foreach ($problemId in $areaRows.Id) {
  if ($catalogIds -notcontains $problemId) { throw "FAIL: problem diagnosis has no user message: $problemId" }
}
Write-Output 'PASS: 84 problem diagnoses are connected to the message catalog'

Write-Output "PASS: diagnostic taxonomy contract ($($allCurrentErrors.Count) current error tokens)"
