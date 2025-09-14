<#
.SYNOPSIS
  Minimal helper to check/mount AWS FSx for Lustre on a remote Ubuntu host via SSH.

.EXAMPLES
  # Show FSx/Lustre status (mounts, fstab, df)
  .\scripts\fsx-mount.ps1 -SshHost ubuntugpuws -Action status

  # Mount now (no persistence) with explicit DNS/mount name
  .\scripts\fsx-mount.ps1 -SshHost ubuntugpuws -Action mount -FsxDnsName fs-abcde.fsx.us-east-1.amazonaws.com -FsxMountName fs-12345678

  # Mount and persist to /etc/fstab
  .\scripts\fsx-mount.ps1 -SshHost ubuntugpuws -Action mount -FsxDnsName fs-abcde.fsx.us-east-1.amazonaws.com -FsxMountName fs-12345678 -Persist

.NOTES
  - Keeps it simple; no advanced error handling
  - Host can be SSH alias or user@host
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$SshHost,

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
        "grep -nEi 'lustre|@tcp:/' /etc/fstab || true",
        "echo '--- findmnt /fsx ---'",
        'findmnt -no SOURCE,TARGET,OPTIONS /fsx || true',
        "echo '--- df /fsx ---'",
        'df -h /fsx || true'
      ) -join ' '
    }
    'mount' {
      if (-not $FsxDnsName -or -not $FsxMountName) {
        throw 'For -Action mount, you must provide -FsxDnsName and -FsxMountName.'
      }
      $fstabLine = "$FsxDnsName@tcp:/$FsxMountName /fsx lustre nofail,_netdev,noatime,flock,x-systemd.requires=network-online.target,x-systemd.mount-timeout=30 0 0"
      $persistCmd = if ($Persist) { @(
        "if ! grep -q '^$FsxDnsName@tcp:/$FsxMountName[ ]\+/fsx[ ]\+lustre' /etc/fstab; then echo '$fstabLine' | sudo tee -a /etc/fstab >/dev/null; echo 'Persisted to /etc/fstab'; else echo 'fstab entry already present'; fi;"
      ) -join ' ' } else { '' }
      return @(
        'set -e;',
        'sudo mkdir -p /fsx;',
        "if mountpoint -q /fsx; then echo '/fsx already mounted'; else echo 'Mounting: $FsxDnsName@tcp:/$FsxMountName -> /fsx'; sudo mount -t lustre -o noatime,flock $FsxDnsName@tcp:/$FsxMountName /fsx; fi;",
        $persistCmd,
        "echo 'findmnt /fsx:'",
        'findmnt -no SOURCE,TARGET,OPTIONS /fsx || true',
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

Write-Host "[fsx-mount.ps1] ssh $SshHost -- $Action" -ForegroundColor Cyan

# Prefer native invocation for Windows PowerShell compatibility
$cmdArgs = @($SshHost, $remote)
& ssh @cmdArgs
$exitCode = $LASTEXITCODE
exit $exitCode
