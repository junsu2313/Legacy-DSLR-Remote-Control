param(
  [string]$BaseUrl = 'http://100.123.59.97',
  [string]$DestinationDirectory = (Join-Path $PSScriptRoot '..\CAMERA\d810\incoming')
)

$ErrorActionPreference = 'Stop'
$destination = [System.IO.Path]::GetFullPath($DestinationDirectory)
[System.IO.Directory]::CreateDirectory($destination) | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$partial = Join-Path $destination "D810-$stamp.NEF.part"
$final = Join-Path $destination "D810-$stamp.NEF"

try {
  Invoke-WebRequest -Uri "$BaseUrl/cgi-bin/captured-nef" -OutFile $partial -TimeoutSec 180
  $item = Get-Item -LiteralPath $partial
  if ($item.Length -lt 4194304) { throw "Received file is too small for a D810 NEF: $($item.Length) bytes" }
  $stream = [System.IO.File]::OpenRead($partial)
  try {
    $header = [byte[]]::new(4)
    if ($stream.Read($header, 0, 4) -ne 4) { throw 'Received object has no TIFF/NEF header' }
  } finally {
    $stream.Dispose()
  }
  $littleTiff = $header[0] -eq 0x49 -and $header[1] -eq 0x49 -and $header[2] -eq 0x2A -and $header[3] -eq 0x00
  $bigTiff = $header[0] -eq 0x4D -and $header[1] -eq 0x4D -and $header[2] -eq 0x00 -and $header[3] -eq 0x2A
  if (-not ($littleTiff -or $bigTiff)) { throw 'Received object does not have a TIFF/NEF header' }
  Move-Item -LiteralPath $partial -Destination $final
  Get-Item -LiteralPath $final | Select-Object FullName,Length,LastWriteTime
} catch {
  if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
  throw
}
