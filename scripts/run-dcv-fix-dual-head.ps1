<#
.SYNOPSIS
Uploads and runs dcv-fix-dual-head.sh on a remote Ubuntu instance via SSH.

.PARAMETER Host
SSH host (e.g., ubuntu@1.2.3.4 or EC2 Instance Connect style).

.PARAMETER Left
Left monitor resolution (e.g., 2560x1440)

.PARAMETER Right
Right monitor resolution (e.g., 1920x1440)

.PARAMETER SkipKms
Switch to avoid writing nvidia-drm KMS option and initramfs update.

.PARAMETER NoRestart
Switch to avoid restarting gdm3 during the run.

.PARAMETER KeyPath
Path to SSH private key if needed.

.EXAMPLE
./run-dcv-fix-dual-head.ps1 -Host ubuntu@EC2_PUBLIC_IP -Left 2560x1440 -Right 1920x1440

#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SshHost,
    [Parameter(Mandatory = $true)][string]$Left,
    [Parameter(Mandatory = $true)][string]$Right,
    [switch]$SkipKms,
    [switch]$NoRestart,
    [string]$KeyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalScript = Join-Path $ScriptDir 'dcv-fix-dual-head.sh'
if (!(Test-Path $LocalScript)) { throw "Local script not found: $LocalScript" }

# Remote temp path
$RemoteTmp = '/tmp/dcv-fix-dual-head.sh'

# Build SSH/SCP common args
$SshArgs = @()
if ($KeyPath) { $SshArgs += @('-i', $KeyPath) }
$SshArgs += @('-o', 'StrictHostKeyChecking=no')

Write-Host ('Uploading script to {0}:{1}' -f $SshHost, $RemoteTmp)
& scp @SshArgs $LocalScript ('{0}:{1}' -f $SshHost, $RemoteTmp) | Write-Host

Write-Host 'Making script executable'
& ssh @SshArgs $SshHost ('sudo chmod +x {0}' -f $RemoteTmp) | Write-Host

# Build remote command
$RemoteCmd = @('sudo', $RemoteTmp, '--left', $Left, '--right', $Right)
if ($SkipKms) { $RemoteCmd += '--skip-kms' }
if ($NoRestart) { $RemoteCmd += '--no-restart' }

Write-Host ('Running: {0}' -f ($RemoteCmd -join ' '))
& ssh @SshArgs $SshHost ($RemoteCmd -join ' ') | Tee-Object -Variable Output | Write-Host

Write-Host '--- tail Xorg.0.log (last 120 lines) ---'
& ssh @SshArgs $SshHost 'sudo tail -n 120 /var/log/Xorg.0.log' | Write-Host

Write-Host '--- gdm3 status ---'
& ssh @SshArgs $SshHost 'systemctl status gdm3 --no-pager -l | sed -n '\''1, 80p'\''' | Write-Host

Write-Host 'Done. Review output above for xrandr results and errors.'
