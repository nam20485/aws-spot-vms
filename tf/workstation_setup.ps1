# This script is run automatically on the Windows instance's first boot.
# It installs necessary software, mounts the FSx file system, and installs GPU drivers.

# Create a transcript for debugging startup issues. You can find this log in C:\
Start-Transcript -Path "C:\transcript.log" -Append

Write-Host "Starting workstation setup..."

# 1. Install the AWS PowerShell module to interact with AWS services.
# This is needed to get the file system's network path automatically.
Write-Host "Installing AWS PowerShell Tools..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name AWSPowerShell.NetCore -Force -Confirm:$false
Write-Host "AWS PowerShell Tools installed."

# 2. Get the AWS Region from the instance's metadata.
$Region = (Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/placement/region)

# 3. Find the FSx for Windows File System's DNS Name.
# This script assumes it's the only FSx file system in the account/region.
Write-Host "Finding FSx for Windows File System..."
$FSxFileSystem = (Get-FSXFileSystem -Region $Region).FileSystems[0]
if (-not $FSxFileSystem)
{
    Write-Host "Error: Could not find an FSx for Windows File System."
    exit 1
}
$FSxDNSName = $FSxFileSystem.DNSName
Write-Host "Found FSx DNS Name: $FSxDNSName"

# 4. Map the FSx file share to the F: drive to make it persistent.
# The default share name on an FSx for Windows file system is 'share'.
$SharePath = "\\$($FSxDNSName)\share"
Write-Host "Mapping network drive F: to $SharePath..."
New-SmbMapping -LocalPath "F:" -RemotePath $SharePath -Persistent $true
Write-Host "Successfully mapped F: drive."

# 5. Download and install the appropriate NVIDIA GRID drivers for the GPU instance.
# This example uses a driver for a g4dn instance. Change if you use a different instance family.
Write-Host "Downloading NVIDIA GRID drivers..."
$Bucket = "ec2-windows-nvidia-drivers"
$Key = "latest/GRID-WINDOWS-SERVER-2019-2022/NVIDIA-GRID-WINDOWS-537.13.exe"
$DriverFile = "C:\NVIDIA-GRID-driver.exe"

# The S3 bucket with drivers is in us-east-1.
Read-S3Object -BucketName $Bucket -Key $Key -File $DriverFile -Region "us-east-1"
Write-Host "Download complete."

Write-Host "Installing NVIDIA drivers silently..."
# These arguments tell the installer to run silently and not to reboot immediately.
$InstallerArgs = "-s -noreboot"
Start-Process -FilePath $DriverFile -ArgumentList $InstallerArgs -Wait
Write-Host "NVIDIA driver installation complete."

# 6. Restart the computer to finalize the driver installation and apply all settings.
Write-Host "Setup complete. Restarting computer in 1 minute..."
Stop-Transcript
Restart-Computer -Force
