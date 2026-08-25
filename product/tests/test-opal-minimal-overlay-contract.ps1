$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $repo 'deploy\openwrt\d810-minimal-overlay.manifest'
$deployPath = Join-Path $repo 'deploy\scripts\opal-deploy-manual-controls.sh'

$section = ''
$required = @()
$forbidden = @()
foreach ($line in Get-Content $manifestPath) {
  if ($line -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
  if (-not $line -or $line.StartsWith('#')) { continue }
  if ($section -eq 'required-runtime') { $required += $line }
  if ($section -eq 'forbidden-at-boot') { $forbidden += $line }
}

if ($required.Count -eq 0) { throw 'minimal manifest has no required runtime files' }
if ($forbidden.Count -eq 0) { throw 'minimal manifest has no forbidden boot paths' }

$requiredForbidden = $required | Where-Object { $forbidden -contains $_ }
if ($requiredForbidden) {
  throw "path is both required and forbidden: $($requiredForbidden -join ', ')"
}

$deploy = Get-Content $deployPath -Raw
foreach ($needle in @(
  'MINIMAL_PROFILE_REQUIRED',
  'pidof ddserver',
  '/tmp/bridge-common.sh.new',
  '/www/cgi-bin/bridge-common.sh'
)) {
  if ($deploy.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
    throw "minimal deployment guard missing: $needle"
  }
}

Write-Output "MINIMAL_OVERLAY_CONTRACT_OK required=$($required.Count) forbidden=$($forbidden.Count)"
