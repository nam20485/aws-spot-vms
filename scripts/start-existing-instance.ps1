# Start Existing EC2 Instance
# This script starts an already created EC2 instance using AWS CLI

param(
    [Parameter(Mandatory=$false)]
    [string]$InstanceId,
    
    [Parameter(Mandatory=$false)]
    [string]$InstanceName,
    
    [switch]$WaitForRunning,
    
    [switch]$ShowOutput,
    
    [switch]$OpenConsole
)

# Function to open AWS Console
function Open-AWSConsole {
    param(
        [string]$InstanceId = $null,
        [string]$Region = $null
    )
    
    # Get current AWS region if not provided
    if (-not $Region) {
        $Region = aws configure get region 2>$null
        if (-not $Region) {
            $Region = "us-east-1"  # Default fallback
        }
    }
    
    # Build console URL
    $baseUrl = "https://$Region.console.aws.amazon.com/ec2/home?region=$Region"
    
    if ($InstanceId) {
        # Open directly to the specific instance
        $consoleUrl = "$baseUrl#InstanceDetails:instanceId=$InstanceId"
        Write-Host "Opening AWS Console for instance $InstanceId..." -ForegroundColor Cyan
    } else {
        # Open to instances list
        $consoleUrl = "$baseUrl#Instances:"
        Write-Host "Opening AWS Console EC2 Instances view..." -ForegroundColor Cyan
    }
    
    try {
        Start-Process $consoleUrl
        Write-Host "AWS Console opened in your default browser" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to open browser automatically. Please visit: $consoleUrl"
    }
}
function Test-AWSAuth {
    Write-Host "Checking AWS authentication..." -ForegroundColor Cyan
    
    # Test with a simple STS call
    $stsResult = aws sts get-caller-identity 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "AWS authentication is valid" -ForegroundColor Green
        return $true
    }
    
    # Check if it's an SSO token issue
    $errorOutput = $stsResult -join "`n"
    if ($errorOutput -match "SSO session" -or $errorOutput -match "token" -or $errorOutput -match "credentials") {
        Write-Warning "AWS SSO token expired or invalid"
        Write-Host "Running 'aws sso login' to refresh credentials..." -ForegroundColor Yellow
        
        aws sso login
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AWS SSO login successful" -ForegroundColor Green
            return $true
        } else {
            Write-Error "AWS SSO login failed"
            return $false
        }
    } else {
        Write-Error "AWS authentication failed: $errorOutput"
        return $false
    }
}

# Function to get and display instances for selection
function Get-InstanceSelection {
    Write-Host "Fetching your EC2 instances..." -ForegroundColor Cyan
    
    # Get instances with useful information - filter out terminated instances
    $instancesJson = aws ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped,rebooting" --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch instances: $instancesJson"
        return $null
    }
    
    try {
        $ec2Data = $instancesJson | ConvertFrom-Json
        
        # Extract instances from the reservations
        $instances = @()
        foreach ($reservation in $ec2Data.Reservations) {
            foreach ($instance in $reservation.Instances) {
                # Skip terminated instances
                if ($instance.State.Name -eq "terminated") {
                    continue
                }
                
                # Find the Name tag
                $nameTag = $instance.Tags | Where-Object { $_.Key -eq "Name" } | Select-Object -First 1
                $name = if ($nameTag) { $nameTag.Value } else { $null }
                
                $instances += @{
                    InstanceId = $instance.InstanceId
                    Name = $name
                    State = $instance.State.Name
                    InstanceType = $instance.InstanceType
                    PublicIpAddress = $instance.PublicIpAddress
                    PrivateIpAddress = $instance.PrivateIpAddress
                }
            }
        }
    } catch {
        Write-Error "Failed to parse instance data: $_"
        return $null
    }
    
    if (-not $instances -or $instances.Count -eq 0) {
        Write-Warning "No EC2 instances found in your account (excluding terminated instances)"
        Write-Host "This could mean:" -ForegroundColor Yellow
        Write-Host "  - All instances are terminated" -ForegroundColor Yellow
        Write-Host "  - Instances are in a different region" -ForegroundColor Yellow
        Write-Host "  - AWS credentials don't have EC2 permissions" -ForegroundColor Yellow
        return $null
    }
    
    # Display instances in a table format
    Write-Host "`nYour EC2 Instances:" -ForegroundColor Green
    Write-Host ("=" * 120) -ForegroundColor Gray
    Write-Host ("{0,-3} {1,-19} {2,-25} {3,-10} {4,-13} {5,-15} {6,-15}" -f "No.", "Instance ID", "Name", "State", "Type", "Public IP", "Private IP") -ForegroundColor Yellow
    Write-Host ("=" * 120) -ForegroundColor Gray
    
    $validInstances = @()
    $index = 1
    
    foreach ($instance in $instances) {
        $instanceId = $instance.InstanceId
        $name = if ($instance.Name) { $instance.Name } else { "(no name)" }
        $state = $instance.State
        $type = $instance.InstanceType
        $publicIp = if ($instance.PublicIpAddress) { $instance.PublicIpAddress } else { "(none)" }
        $privateIp = if ($instance.PrivateIpAddress) { $instance.PrivateIpAddress } else { "(none)" }
        
        # Color code by state
        $stateColor = switch ($state) {
            "running" { "Green" }
            "stopped" { "Yellow" }
            "stopping" { "Red" }
            "pending" { "Cyan" }
            "starting" { "Cyan" }
            "rebooting" { "Magenta" }
            "shutting-down" { "DarkRed" }
            "terminated" { "DarkGray" }
            default { "White" }
        }
        
        Write-Host ("{0,-3} {1,-19} {2,-25} " -f $index, $instanceId, $name) -NoNewline
        Write-Host ("{0,-10} " -f $state) -ForegroundColor $stateColor -NoNewline
        Write-Host ("{0,-13} {1,-15} {2,-15}" -f $type, $publicIp, $privateIp)
        
        $validInstances += @{
            Index = $index
            InstanceId = $instanceId
            Name = $name
            State = $state
        }
        $index++
    }
    
    Write-Host ("=" * 120) -ForegroundColor Gray
    
    # Get user selection
    while ($true) {
        Write-Host "`nSelect an instance to start (enter number), or 'q' to quit: " -ForegroundColor Cyan -NoNewline
        $selection = Read-Host
        
        if ($selection -eq 'q' -or $selection -eq 'quit') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return $null
        }
        
        try {
            $selectedIndex = [int]$selection
            if ($selectedIndex -ge 1 -and $selectedIndex -le $validInstances.Count) {
                $selectedInstance = $validInstances[$selectedIndex - 1]
                Write-Host "Selected: $($selectedInstance.InstanceId) ($($selectedInstance.Name))" -ForegroundColor Green
                return $selectedInstance.InstanceId
            } else {
                Write-Warning "Please enter a number between 1 and $($validInstances.Count)"
            }
        } catch {
            Write-Warning "Please enter a valid number or 'q' to quit"
        }
    }
}

# Function to check AWS authentication and refresh if needed
function Get-InstanceIdByName {
    param([string]$Name)
    
    $query = "Reservations[].Instances[?Tags[?Key=='Name' && Value=='$Name']].InstanceId"
    $result = aws ec2 describe-instances --query $query --output text 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to query instances by name: $result"
        return $null
    }
    
    return $result.Trim()
}

# Function to get instance state
function Get-InstanceState {
    param([string]$Id)
    
    $state = aws ec2 describe-instances --instance-ids $Id --query "Reservations[0].Instances[0].State.Name" --output text 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get instance state: $state"
        return $null
    }
    
    return $state.Trim()
}

# Main script
Write-Host "Starting existing EC2 instance..." -ForegroundColor Green

# Check and refresh AWS authentication if needed
if (-not (Test-AWSAuth)) {
    Write-Error "AWS authentication failed. Please check your credentials."
    exit 1
}

# Determine instance ID
$targetInstanceId = $null

if ($InstanceId) {
    $targetInstanceId = $InstanceId
    Write-Host "Using provided Instance ID: $targetInstanceId" -ForegroundColor Yellow
} elseif ($InstanceName) {
    Write-Host "Looking up Instance ID for name: $InstanceName" -ForegroundColor Yellow
    $targetInstanceId = Get-InstanceIdByName -Name $InstanceName
    
    if (-not $targetInstanceId) {
        Write-Error "Could not find instance with name: $InstanceName"
        exit 1
    }
    
    Write-Host "Found Instance ID: $targetInstanceId" -ForegroundColor Green
} else {
    # Try to get from Terraform output first
    $terraformDir = "d:\src\github\nam20485\aws-spot-vms\terraform-workstations\ubuntu"
    
    if (Test-Path $terraformDir) {
        Write-Host "Checking Terraform output..." -ForegroundColor Yellow
        
        # Use -chdir instead of changing directory to preserve user's current location
        $terraformOutput = terraform -chdir="$terraformDir" output -raw instance_id 2>$null
        
        # Only use terraform output if it's a valid instance ID format (i-xxxxxxxxxxxxxxxxx)
        if ($LASTEXITCODE -eq 0 -and $terraformOutput -and $terraformOutput -match '^i-[0-9a-f]{17}$') {
            $targetInstanceId = $terraformOutput.Trim()
            Write-Host "Found Instance ID from Terraform: $targetInstanceId" -ForegroundColor Green
        } else {
            Write-Host "No valid Terraform instance found" -ForegroundColor Yellow
        }
    }
    
    # If no Terraform instance found, show interactive selection
    if (-not $targetInstanceId) {
        Write-Host "No instance specified. Showing available instances for selection..." -ForegroundColor Yellow
        $targetInstanceId = Get-InstanceSelection
        
        if (-not $targetInstanceId) {
            Write-Host "No instance selected. Exiting." -ForegroundColor Yellow
            exit 0
        }
    }
}

# Check current state
Write-Host "Checking current instance state..." -ForegroundColor Cyan
$currentState = Get-InstanceState -Id $targetInstanceId

if (-not $currentState) {
    Write-Error "Failed to check instance state"
    exit 1
}

Write-Host "Current state: $currentState" -ForegroundColor Yellow

# Handle different EC2 instance states:
# - running: Instance is up and ready
# - stopped: Instance is shut down and can be started
# - pending: Instance is starting up (transitional state)
# - stopping: Instance is shutting down (transitional state)
# - rebooting: Instance is restarting (transitional state)
# - shutting-down: Instance is being terminated (transitional state)
# - terminated: Instance has been destroyed

# Start instance if not already running
if ($currentState -eq "running") {
    Write-Host "Instance is already running!" -ForegroundColor Green
} elseif ($currentState -eq "pending") {
    Write-Host "Instance is already starting up (state: pending)..." -ForegroundColor Cyan
    
    if ($WaitForRunning) {
        Write-Host "Waiting for instance to reach 'running' state..." -ForegroundColor Cyan
        
        aws ec2 wait instance-running --instance-ids $targetInstanceId
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Instance is now running!" -ForegroundColor Green
        } else {
            Write-Warning "Wait command failed, but instance may still be starting"
        }
    } else {
        Write-Host "Instance is starting. Use -WaitForRunning to wait for completion." -ForegroundColor Yellow
    }
} elseif ($currentState -eq "stopped") {
    Write-Host "Starting instance..." -ForegroundColor Cyan
    
    $startResult = aws ec2 start-instances --instance-ids $targetInstanceId 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        # Check if it's an auth issue and retry once
        if ($startResult -match "SSO session" -or $startResult -match "token" -or $startResult -match "credentials") {
            Write-Warning "Authentication expired during operation, retrying..."
            if (Test-AWSAuth) {
                $startResult = aws ec2 start-instances --instance-ids $targetInstanceId 2>&1
            }
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start instance: $startResult"
            exit 1
        }
    }
    
    Write-Host "Start command sent successfully!" -ForegroundColor Green
    
    if ($WaitForRunning) {
        Write-Host "Waiting for instance to reach 'running' state..." -ForegroundColor Cyan
        
        aws ec2 wait instance-running --instance-ids $targetInstanceId
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Instance is now running!" -ForegroundColor Green
        } else {
            Write-Warning "Wait command failed, but instance may still be starting"
        }
    }
} elseif ($currentState -eq "stopping") {
    Write-Warning "Instance is currently stopping. Please wait for it to reach 'stopped' state before starting."
    Write-Host "Current state: $currentState" -ForegroundColor Yellow
    exit 1
} elseif ($currentState -eq "rebooting") {
    Write-Host "Instance is rebooting and will be running shortly..." -ForegroundColor Cyan
    
    if ($WaitForRunning) {
        Write-Host "Waiting for instance to reach 'running' state..." -ForegroundColor Cyan
        
        aws ec2 wait instance-running --instance-ids $targetInstanceId
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Instance is now running!" -ForegroundColor Green
        } else {
            Write-Warning "Wait command failed, but instance may still be rebooting"
        }
    } else {
        Write-Host "Instance is rebooting. Use -WaitForRunning to wait for completion." -ForegroundColor Yellow
    }
} else {
    Write-Warning "Instance is in state '$currentState'. Cannot start from this state."
    Write-Host "Valid states for starting: stopped" -ForegroundColor Yellow
    Write-Host "States that indicate startup in progress: pending, rebooting" -ForegroundColor Yellow
    exit 1
}

# Show instance details if requested
if ($ShowOutput -or $WaitForRunning) {
    Write-Host "`nInstance Details:" -ForegroundColor Cyan
    
    $instanceInfo = aws ec2 describe-instances --instance-ids $targetInstanceId --query "Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,InstanceType:InstanceType}" --output table
    
    if ($LASTEXITCODE -eq 0) {
        Write-Output $instanceInfo
    }
}

Write-Host "`nDone!" -ForegroundColor Green
Write-Host "Instance ID: $targetInstanceId" -ForegroundColor Yellow

# Open AWS Console if requested
if ($OpenConsole) {
    $currentRegion = aws configure get region 2>$null
    if (-not $currentRegion) {
        $currentRegion = "us-east-1"
    }
    
    Open-AWSConsole -InstanceId $targetInstanceId -Region $currentRegion
}