<#
.SYNOPSIS
  Minimal helper to check/mount AWS FSx for Lustre on a remote Ubuntu host via SSH.

.EXAMPLES
  # Show FSx/Lustre status (mounts, fstab, df)
  .\scripts\fsx-mount.ps1 -Host ubuntugpuws -Action status

  # Mount now (no persistence) with explicit DNS/mount name
  .\scripts\fsx-mount.ps1 -Host ubuntugpuws -Action mount -FsxDnsName fs-abcde.fsx.us-east-1.amazonaws.com -FsxMountName fs-12345678

  # Mount and persist to /etc/fstab
  .\scripts\fsx-mount.ps1 -Host ubuntugpuws -Action mount -FsxDnsName fs-abcde.fsx.us-east-1.amazonaws.com -FsxMountName fs-12345678 -Persist

.NOTES
  - Keeps it simple; no advanced error handling
  - Host can be SSH alias or user@host
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Host,

  [ValidateSet('status','mount')]
  [string]$Action = 'status',

  [string]$FsxDnsName,
  [string]$FsxMountName,
  [switch]$Persist
)

function Build-RemoteCommand {
  param(
    [string]$Action,
    [string]$FsxDnsName,
    [string]$FsxMountName,
    [switch]$Persist
  )

  switch ($Action) {
    'status' {
      return @(
        'set -e;',
        "echo '--- Lustre packages ---'",
        "dpkg -l | grep -E 'lustre|lnet' || true",
        "echo '--- Current mounts (lustre) ---'",
        "mount | grep -i lustre || true",
        "echo '--- /etc/fstab entries (lustre) ---'",
        "grep -iE 'lustre|@tcp:/' /etc/fstab || true",
        "echo '--- df /fsx ---'",
        'df -h /fsx || true'
      ) -join ' '
    }
    'mount' {
      if (-not $FsxDnsName -or -not $FsxMountName) {
        throw 'For -Action mount, you must provide -FsxDnsName and -FsxMountName.'
      }
      $fstabLine = "$FsxDnsName@tcp:/$FsxMountName /fsx lustre defaults,_netdev,noatime,flock 0 0"
      $persistCmd = if ($Persist) { "echo '$fstabLine' | sudo tee -a /etc/fstab >/dev/null; echo 'Persisted to /etc/fstab';" } else { '' }
      return @(
        'set -e;',
        'sudo mkdir -p /fsx;',
        "echo 'Mounting: $FsxDnsName@tcp:/$FsxMountName -> /fsx'",
        "sudo mount -t lustre -o noatime,flock $FsxDnsName@tcp:/$FsxMountName /fsx",
        $persistCmd,
        "echo 'df -h /fsx:'",
        'df -h /fsx'
      ) -join ' '
    }
  }
}

try {
  $remote = Build-RemoteCommand -Action $Action -FsxDnsName $FsxDnsName -FsxMountName $FsxMountName -Persist:$Persist
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}

Write-Host "[fsx-mount.ps1] ssh $Host -- $Action" -ForegroundColor Cyan

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
