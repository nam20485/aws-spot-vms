<#
.SYNOPSIS
  Basic helper to hold/unhold NVIDIA driver packages on a remote Ubuntu host via SSH, and show candidate versions.

.EXAMPLE
  # Show held packages and candidates (default packages)
  .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action show

.EXAMPLE
  # Hold the default server driver pair
  .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action hold

.EXAMPLE
  # Unhold and then you can upgrade manually
  .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action unhold

.EXAMPLE
  # Specify explicit package names
  .\scripts\nvidia-driver.ps1 -Host ubuntu@52.1.238.145 -Action hold -Packages nvidia-driver-570-server,nvidia-utils-570-server

.NOTES
  - Assumes you can SSH to the host (Host can be a user@ip or an alias from ~/.ssh/config)
  - Keeps things simple—no fancy error handling, just the essentials
#>
param(
  [Parameter(Mandatory = $true, HelpMessage = 'SSH target: alias from ~/.ssh/config or user@host')]
  [string]$Host,

  [ValidateSet('hold','unhold','show')]
  [string]$Action = 'show',

  [string[]]$Packages = @('nvidia-driver-570-server','nvidia-utils-570-server')
)

# Build the remote command based on action
$pkgList = ($Packages | Where-Object { $_ -and $_.Trim() -ne '' }) -join ' '
if (-not $pkgList) {
  Write-Error 'No package names provided.'
  exit 1
}

switch ($Action) {
  'hold' {
    $remote = "set -e; sudo apt-mark hold $pkgList; echo '--- Held packages ---'; apt-mark showhold; echo '--- Policy ---'; apt policy $pkgList"
  }
  'unhold' {
    $remote = "set -e; sudo apt-mark unhold $pkgList; echo '--- Held packages ---'; apt-mark showhold; echo '--- Policy ---'; apt policy $pkgList"
  }
  'show' {
    $remote = "echo '--- Held packages ---'; apt-mark showhold; echo '--- Policy ---'; apt policy $pkgList"
  }
}

Write-Host "[nvidia-driver.ps1] ssh $Host -- $Action for: $pkgList" -ForegroundColor Cyan

# Invoke SSH with the remote command. PowerShell will pass remaining args as a single command string to ssh.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'ssh'
$psi.ArgumentList.Add($Host)
$psi.ArgumentList.Add($remote)
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($stdout) { Write-Output $stdout }
if ($stderr) { Write-Error $stderr }

exit $proc.ExitCode
