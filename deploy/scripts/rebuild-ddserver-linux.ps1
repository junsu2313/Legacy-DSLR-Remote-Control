param(
  [Parameter(Mandatory = $true)]
  [string]$ServerUser,

  [Parameter(Mandatory = $false)]
  [string]$ServerHost = '192.168.0.23',

  [Parameter(Mandatory = $true)]
  [string]$RemoteRepoRoot,

  [Parameter(Mandatory = $true)]
  [string]$RemoteSdkRoot,

  [Parameter(Mandatory = $false)]
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

  [Parameter(Mandatory = $false)]
  [string]$LocalSdkRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'siflower\openwrt-sdk-siflower-1806')
)

$ErrorActionPreference = 'Stop'

$stageScript = Join-Path $PSScriptRoot 'stage-ddserver-openwrt.ps1'
if (-not (Test-Path $stageScript)) {
  throw "Missing staging script: $stageScript"
}

if (-not (Test-Path $RepoRoot)) {
  throw "Repo root does not exist: $RepoRoot"
}

if (-not (Test-Path $LocalSdkRoot)) {
  throw "Local SDK root does not exist: $LocalSdkRoot"
}

$remote = "$ServerUser@$ServerHost"

Write-Host "Staging ddserver package into local OpenWrt SDK copy..."
& $stageScript -SdkRoot $LocalSdkRoot | Out-Null

Write-Host "Syncing repository to $remote:$RemoteRepoRoot ..."
ssh $remote "mkdir -p '$RemoteRepoRoot'"
scp -r "$RepoRoot\openwrt" "$RepoRoot\_tmp_ddserver" "$RepoRoot\scripts" "${remote}:${RemoteRepoRoot}"

Write-Host "Preparing remote OpenWrt SDK tree..."
ssh $remote "mkdir -p '$RemoteSdkRoot/package/ddserver'"
ssh $remote "cp -r '$RemoteRepoRoot/openwrt/ddserver/.' '$RemoteSdkRoot/package/ddserver/'"
ssh $remote "cp '$RemoteRepoRoot/_tmp_ddserver/CMakeLists.txt' '$RemoteSdkRoot/package/ddserver/'"
ssh $remote "cp -r '$RemoteRepoRoot/_tmp_ddserver/files/.' '$RemoteSdkRoot/package/ddserver/files/'"
ssh $remote "cp -r '$RemoteRepoRoot/_tmp_ddserver/src/.' '$RemoteSdkRoot/package/ddserver/src/'"

Write-Host "Running remote OpenWrt package build..."
ssh $remote "cd '$RemoteSdkRoot' && make package/ddserver/compile V=s"

Write-Host "Done. Check the remote OpenWrt package output for the rebuilt ddserver ipk."
