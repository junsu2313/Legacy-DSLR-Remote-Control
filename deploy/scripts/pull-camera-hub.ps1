param(
  [string]$BaseUrl = "http://127.0.0.1:8787",
  [string]$CameraId = "d810",
  [string]$TargetDir = "E:\Underlab_APP\Camera\CAMERA\d810\JEPG\TEST",
  [string]$StatePath = "E:\Underlab_APP\Camera\CAMERA\d810\JEPG\TEST\.hub-state.json"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

if (Test-Path -LiteralPath $StatePath) {
  $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
} else {
  $state = [pscustomobject]@{
    downloaded = @()
  }
}

$downloadedSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($item in @($state.downloaded)) {
  [void]$downloadedSet.Add([string]$item)
}

$listUrl = "$BaseUrl/api/camera/files?cameraId=$([uri]::EscapeDataString($CameraId))&limit=100"
$response = Invoke-RestMethod -Uri $listUrl -Method Get

foreach ($file in @($response.files)) {
  $id = [string]$file.id
  if ($downloadedSet.Contains($id)) {
    continue
  }

  $safeName = [System.IO.Path]::GetFileName([string]$file.filename)
  if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = [System.IO.Path]::GetFileName([string]$file.key)
  }
  $destination = Join-Path $TargetDir $safeName
  if (Test-Path -LiteralPath $destination) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($safeName)
    $ext = [System.IO.Path]::GetExtension($safeName)
    $destination = Join-Path $TargetDir ("{0}_{1}{2}" -f $base, (Get-Date -Format "yyyyMMdd_HHmmss"), $ext)
  }

  $downloadUrl = "$BaseUrl/api/camera/files/$([uri]::EscapeDataString($id))/download"
  Invoke-WebRequest -Uri $downloadUrl -OutFile $destination
  [void]$downloadedSet.Add($id)
}

$newState = [pscustomobject]@{
  downloaded = @($downloadedSet)
}
$newState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StatePath -Encoding UTF8
