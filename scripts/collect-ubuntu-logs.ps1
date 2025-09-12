param(
  [Parameter(Mandatory=$true)]
  [string]$KeyPath,

  [Parameter(Mandatory=$false)]
  [string]$RemoteHost,

  [Parameter(Mandatory=$false)]
  [string]$User = 'ubuntu',

  [Parameter(Mandatory=$false)]
  [string]$LocalDiagScript = "../terraform-workstations/ubuntu/instance_diagnostics.sh",

  [Parameter(Mandatory=$false)]
  [string]$OutDir = "../terraform-workstations/ubuntu"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[collect] $msg" }

function Test-Command([string]$name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Required command '$name' not found in PATH. Install OpenSSH Client or ensure it's available."
  }
}

Test-Command ssh
Test-Command scp

# Resolve paths relative to this script file
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path -Path (Join-Path $ScriptDir "..")
$LocalDiagScriptPath = Resolve-Path -Path (Join-Path $ScriptDir $LocalDiagScript)
$OutDirPath = Resolve-Path -Path (Join-Path $ScriptDir $OutDir) -ErrorAction SilentlyContinue
if (-not $OutDirPath) { $OutDirPath = New-Item -ItemType Directory -Path (Join-Path $ScriptDir $OutDir) -Force | Select-Object -ExpandProperty FullName }

if (-not (Test-Path $LocalDiagScriptPath)) {
  throw "Diagnostics script not found at: $LocalDiagScriptPath"
}

if (-not (Test-Path $KeyPath)) {
  throw "SSH key not found at: $KeyPath"
}

if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
  # Try to read Terraform output for workstation_public_ip
  Test-Command terraform
  $tfFolder = Resolve-Path -Path (Join-Path $RepoRoot "terraform-workstations/ubuntu")
  Write-Info "Discovering public IP via Terraform output in $tfFolder ..."
  $RemoteHost = & terraform -chdir=$tfFolder output -raw workstation_public_ip
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RemoteHost)) {
    throw "Failed to determine Host. Provide -Host or ensure 'workstation_public_ip' Terraform output exists."
  }
}

Write-Info "Using Host: $RemoteHost, User: $User"
Write-Info "Uploading diagnostics script to remote home directory..."
& scp -i $KeyPath $LocalDiagScriptPath "${User}@${RemoteHost}:~/instance_diagnostics.sh"
if ($LASTEXITCODE -ne 0) { throw "scp upload failed." }

Write-Info "Executing diagnostics script on remote (with sudo)..."
& ssh -i $KeyPath "${User}@${RemoteHost}" 'chmod +x ~/instance_diagnostics.sh && sudo ~/instance_diagnostics.sh'
if ($LASTEXITCODE -ne 0) { Write-Info "Remote diagnostics returned non-zero exit; continuing to fetch tar if present." }

Write-Info "Locating latest diagnostics tarball on remote..."
$remoteTar = (& ssh -i $KeyPath "${User}@${RemoteHost}" 'ls -1t ~/setup-logs-*.tgz 2>/dev/null | head -1').Trim()
if ([string]::IsNullOrWhiteSpace($remoteTar)) {
  throw "No diagnostics tarball found on remote. Check /var/log/user-data.log and cloud-init logs manually."
}
Write-Info "Found tarball: $remoteTar"

Write-Info "Downloading tarball to $OutDirPath ..."
& scp -i $KeyPath "${User}@${RemoteHost}:${remoteTar}" "$OutDirPath/"
if ($LASTEXITCODE -ne 0) { throw "scp download failed." }

$downloaded = Join-Path $OutDirPath (Split-Path -Leaf $remoteTar)
Write-Host "`nSUCCESS: Downloaded diagnostics to: $downloaded" -ForegroundColor Green
