param(
  [string]$BaseUrl = "http://127.0.0.1:8787",
  [string]$SourceJpeg = "E:\Underlab_APP\Camera\CAMERA\d810\JEPG\2026_06_17\DSC_7465.JPG"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceJpeg)) {
  throw "Missing source jpeg: $SourceJpeg"
}

$headers = @{
  "X-File-Name" = [System.IO.Path]::GetFileName($SourceJpeg)
  "X-Camera-Id" = "d810"
  "X-Captured-At" = (Get-Date).ToUniversalTime().ToString("s") + "Z"
}

& curl.exe `
  -X POST `
  -H "Content-Type: image/jpeg" `
  -H "X-File-Name: $($headers["X-File-Name"])" `
  -H "X-Camera-Id: $($headers["X-Camera-Id"])" `
  -H "X-Captured-At: $($headers["X-Captured-At"])" `
  --data-binary "@$SourceJpeg" `
  "$BaseUrl/api/camera/upload"

& "E:\Underlab_APP\Camera\scripts\pull-camera-hub.ps1" -BaseUrl $BaseUrl
