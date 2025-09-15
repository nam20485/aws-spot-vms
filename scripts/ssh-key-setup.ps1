#requires -version 7.0
<#!
.SYNOPSIS
Generates a passphrase-protected Ed25519 SSH key, optionally exports a .ppk for Pageant, prints fingerprints and a suggested Pageant startup command, and can copy the public key to a remote host's authorized_keys.

.EXAMPLE
./scripts/ssh-key-setup.ps1 -KeyName aws-spot-vms-ed25519 -ExportPpk -CopyToHost ubuntugpuws -ConnectIdentityFile ~/.ssh/aws-spot-vms2.pem

.EXAMPLE
./scripts/ssh-key-setup.ps1 -KeyName mykey -PageantPath "C:\\Program Files\\PuTTY\\pageant.exe" -PuttygenPath "C:\\Program Files\\PuTTY\\puttygen.exe" -ExportPpk

.NOTES
- If -CopyToHost is provided, this script will append the public key to ~/.ssh/authorized_keys on the remote.
- For the copy step, ensure you can connect with an existing key (e.g., AWS .pem) via -ConnectIdentityFile or an SSH alias that already works.
#>

param(
  [string]$KeyName = "aws-spot-vms-ed25519",
  [string]$Comment = "$env:USERNAME@$(hostname) $(Get-Date -Format s)",
  [switch]$Force,
  [securestring]$Passphrase,
  [string]$PuttygenPath,
  [switch]$ExportPpk,
  [string]$PageantPath,
  [string]$CopyToHost,
  [int]$Port = 22,
  [string]$ConnectIdentityFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Binary([string]$nameOrPath, [string[]]$fallbacks) {
  if ($nameOrPath) {
    if (Test-Path $nameOrPath) { return (Resolve-Path $nameOrPath).Path }
    $cmd = Get-Command $nameOrPath -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  foreach ($f in $fallbacks) {
    if (Test-Path $f) { return (Resolve-Path $f).Path }
    $cmd = Get-Command $f -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  return $null
}

function Get-PlainText([securestring]$sec) {
  if (-not $sec) { return '' }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$userHome = [Environment]::GetFolderPath('UserProfile')
$sshDir = Join-Path $userHome '.ssh'
if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

$priv = Join-Path $sshDir $KeyName
$pub  = "$priv.pub"

if ((Test-Path $priv) -and -not $Force) {
  Write-Error "Key '$priv' already exists. Use -Force to overwrite or choose a different -KeyName."
}

$sshKeygen = Resolve-Binary -nameOrPath 'ssh-keygen' -fallbacks @('C:\\Windows\\System32\\OpenSSH\\ssh-keygen.exe','ssh-keygen.exe')
if (-not $sshKeygen) { throw "ssh-keygen not found in PATH or standard locations." }

if (-not $Passphrase) {
  $Passphrase = Read-Host -AsSecureString -Prompt 'Enter passphrase for the new key (recommended)'
}
$pass = Get-PlainText $Passphrase

if (Test-Path $priv) { Remove-Item -Force $priv }
if (Test-Path $pub)  { Remove-Item -Force $pub }

Write-Host "[1/5] Generating Ed25519 key: $priv"
& $sshKeygen -t ed25519 -a 100 -C $Comment -f $priv -N $pass | Out-Null

if (-not (Test-Path $priv) -or -not (Test-Path $pub)) { throw "Key generation failed." }

Write-Host "[2/5] Computing fingerprints"
$fpMd5 = (& $sshKeygen -lf $priv) -join ''
$fpSha = (& $sshKeygen -E sha256 -lf $priv) -join ''

Write-Host "`nKey created:"
Write-Host "  Private: $priv"
Write-Host "  Public : $pub"
Write-Host "  MD5    : $fpMd5"
Write-Host "  SHA256 : $fpSha"

$ppk = $null
if ($ExportPpk) {
  $puttygen = Resolve-Binary -nameOrPath $PuttygenPath -fallbacks @('puttygen','C:\\Program Files\\PuTTY\\puttygen.exe','C:\\Program Files (x86)\\PuTTY\\puttygen.exe')
  if ($puttygen) {
    $ppk = "$priv.ppk"
    Write-Host "[3/5] Converting to .ppk for Pageant: $ppk"
    # PuTTYgen CLI will prompt for passphrase if -P is given; we run interactively so the user can confirm.
    & $puttygen $priv -O private -o $ppk -P
    if (-not (Test-Path $ppk)) { Write-Warning "Failed to create PPK. You can convert manually with PuTTYgen GUI."; $ppk = $null }
  } else {
    Write-Warning "PuTTYgen not found. Skipping .ppk export. Install PuTTY or specify -PuttygenPath."
  }
}

if ($CopyToHost) {
  Write-Host "[4/5] Copying public key to $CopyToHost (port $Port)"
  $pubText = Get-Content -Raw -Path $pub
  $ssh = Resolve-Binary -nameOrPath 'ssh' -fallbacks @('C:\\Windows\\System32\\OpenSSH\\ssh.exe','ssh.exe')
  if (-not $ssh) { throw "ssh not found in PATH or standard locations." }
  $idArg = @()
  if ($ConnectIdentityFile) { $idArg = @('-i', (Resolve-Path $ConnectIdentityFile).Path) }
  $cmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && printf '%s\n' '$pubText' >> ~/.ssh/authorized_keys"
  & $ssh @idArg -p $Port $CopyToHost $cmd
  Write-Host ("Public key appended to {0}:~/.ssh/authorized_keys" -f $CopyToHost)
}

Write-Host "[5/5] Agent integration"

# Suggest a Pageant startup command
$pageant = Resolve-Binary -nameOrPath $PageantPath -fallbacks @('pageant','C:\\Program Files\\PuTTY\\pageant.exe','C:\\Program Files (x86)\\PuTTY\\pageant.exe')
$pageantCmd = $null
if ($pageant) {
  if ($ppk) {
    $pageantCmd = '"' + $pageant + '" ' + '"' + (Resolve-Path $ppk).Path + '"'
  } else {
    # Newer Pageant versions can load OpenSSH keys; if yours cannot, use the .ppk instead.
    $pageantCmd = '"' + $pageant + '" ' + '"' + (Resolve-Path $priv).Path + '"'
  }
}

Write-Host ""
Write-Host "Suggested SSH config Host entry:" -ForegroundColor Cyan
Write-Host @"
Host example
  HostName <ip-or-dns>
  User ubuntu
  IdentityFile $priv
  IdentitiesOnly yes
"@

if ($pageantCmd) {
  Write-Host "Suggested Pageant startup command (add to a shortcut or startup task):" -ForegroundColor Cyan
  Write-Host $pageantCmd
} else {
  Write-Host "Install Pageant to auto-load the key at login, or use the built-in Windows ssh-agent:" -ForegroundColor Yellow
  Write-Host "  Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent"
  Write-Host "  ssh-add $priv"
}

Write-Host ""
Write-Host "Key fingerprint (SHA256):" -NoNewline; Write-Host " $fpSha" -ForegroundColor Green
Write-Host "Use this as a human-readable key ID. Pageant itself uses file paths as startup arguments." -ForegroundColor DarkGray
