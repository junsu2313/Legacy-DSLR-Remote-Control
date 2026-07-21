param(
  [Parameter(Mandatory = $true)]
  [string]$SdkRoot
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageSrc = Join-Path $repoRoot 'openwrt\ddserver'
$cmakeSrc = Join-Path $repoRoot '_tmp_ddserver\CMakeLists.txt'
$filesSrc = Join-Path $repoRoot '_tmp_ddserver\files'
$sourceSrc = Join-Path $repoRoot '_tmp_ddserver\src'
$targetPkg = Join-Path $SdkRoot 'package\ddserver'
$targetSrc = Join-Path $targetPkg 'src'

if (-not (Test-Path $packageSrc)) {
  throw "Missing package source: $packageSrc"
}

if (-not (Test-Path $sourceSrc)) {
  throw "Missing ddserver source: $sourceSrc"
}

if (-not (Test-Path $SdkRoot)) {
  throw "SDK root does not exist: $SdkRoot"
}

New-Item -ItemType Directory -Force -Path $targetPkg | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $targetPkg 'files') | Out-Null
Copy-Item -Path (Join-Path $packageSrc '*') -Destination $targetPkg -Recurse -Force
Copy-Item -Path $cmakeSrc -Destination $targetPkg -Force
Copy-Item -Path (Join-Path $filesSrc '*') -Destination (Join-Path $targetPkg 'files') -Recurse -Force
New-Item -ItemType Directory -Force -Path $targetSrc | Out-Null
Copy-Item -Path (Join-Path $sourceSrc '*') -Destination $targetSrc -Recurse -Force

Write-Host "Staged ddserver package into $targetPkg"
Write-Host "Next step: run `make package/ddserver/compile V=s` from the OpenWrt SDK root."
