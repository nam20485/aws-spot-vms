param(
    [string]$KeyName = "aws-spot-vms",
    [string]$Region = $env:AWS_REGION ?? $env:AWS_DEFAULT_REGION ?? "us-west-2",
    [string]$OutFile = "$PSScriptRoot\$($KeyName).pem",
    [string]$ProfileName = $env:AWS_PROFILE
)

# Ensure AWS PowerShell modules are available
if (-not (Get-Module -ListAvailable -Name AWS.Tools.EC2)) {
    Write-Host "AWS.Tools.EC2 not found. Installing for CurrentUser..." -ForegroundColor Yellow
    try {
        if (-not (Get-Module -ListAvailable -Name AWS.Tools.Installer)) {
            Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -Force -ErrorAction Stop
        }
        Install-AWSToolsModule -Name AWS.Tools.Common, AWS.Tools.EC2 -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to install AWS PowerShell modules: $($_.Exception.Message)"
        exit 1
    }
}

Import-Module AWS.Tools.EC2 -ErrorAction Stop

# Create output directory if needed
$outDir = Split-Path -Path $OutFile -Parent
if ($outDir -and -not (Test-Path -Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

# Prevent accidental overwrite
if (Test-Path -Path $OutFile) {
    Write-Error "Output file already exists: $OutFile. Refusing to overwrite. Delete it or specify -OutFile to a new path."
    exit 1
}

try {
    # Try via AWS PowerShell module first (supports profile/region)
    $params = @{ KeyName = $KeyName; KeyType = 'rsa'; KeyFormat = 'pem'; Region = $Region; ErrorAction = 'Stop' }
    if ($ProfileName) { $params.ProfileName = $ProfileName }
    $kp = New-EC2KeyPair @params
    $keyMaterial = $kp.KeyMaterial
} catch {
    $errMsg = $_.Exception.Message
    $isDuplicate = $errMsg -match "already exists"
    if ($isDuplicate) {
        Write-Error "An EC2 key pair named '$KeyName' already exists in region '$Region'. Choose a different -KeyName or delete the existing key pair."
        exit 1
    }
    Write-Warning "PowerShell module failed to create key pair ($errMsg). Falling back to AWS CLI..."

    # Fallback to AWS CLI (often already authenticated via SSO)
    $aws = Get-Command aws -ErrorAction SilentlyContinue
    if (-not $aws) {
        Write-Error "AWS CLI is not installed or not in PATH. Install AWS CLI v2 or configure credentials for AWS Tools for PowerShell."
        exit 1
    }

    $cliArgs = @('ec2','create-key-pair','--key-name', $KeyName,'--key-type','rsa','--key-format','pem','--region', $Region,'--query','KeyMaterial','--output','text')
    if ($ProfileName) { $cliArgs += @('--profile', $ProfileName) }

    $keyMaterial = & aws @cliArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AWS CLI failed to create key pair. ExitCode=$LASTEXITCODE Output: $keyMaterial"
        exit 1
    }
}

# Save key material to file
$keyMaterial | Out-File -Encoding ascii -FilePath $OutFile -NoNewline

# Make the file read-only for the current user
try { Set-ItemProperty -Path $OutFile -Name IsReadOnly -Value $true } catch { }

Write-Host "Created EC2 key pair '$KeyName' in region '$Region' and saved private key to:" -ForegroundColor Green
Write-Host "    $OutFile" -ForegroundColor Cyan
Write-Host "Keep this file secure. You'll need it to decrypt Windows passwords or SSH to instances." -ForegroundColor Yellow