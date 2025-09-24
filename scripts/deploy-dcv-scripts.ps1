# Deploy DCV dual monitor scripts to EC2 instance
param(
    [string]$InstanceId = "i-07b22f877ffaf84cb"
)

$scripts = @{
    "dcv-setup-extended-desktop.sh" = "d:\src\github\nam20485\aws-spot-vms\scripts\dcv-setup-extended-desktop.sh"
    "dcv-rollback.sh" = "d:\src\github\nam20485\aws-spot-vms\scripts\dcv-rollback.sh"
    "dcv-backup-manager.sh" = "d:\src\github\nam20485\aws-spot-vms\scripts\dcv-backup-manager.sh"
}

Write-Host "🚀 Deploying DCV dual monitor scripts to instance $InstanceId" -ForegroundColor Green

foreach ($scriptName in $scripts.Keys) {
    $scriptPath = $scripts[$scriptName]
    
    Write-Host "📤 Deploying $scriptName..." -ForegroundColor Cyan
    
    # Read the script content
    $content = Get-Content $scriptPath -Raw
    
    # Escape single quotes and backslashes for shell
    $escapedContent = $content -replace "'", "'\'''" -replace '\\', '\\\\'
    
    # Create the command to write the file
    $command = @"
echo 'Creating $scriptName...'
cat > /tmp/$scriptName << 'SCRIPT_EOF'
$content
SCRIPT_EOF
chmod +x /tmp/$scriptName
echo 'Created and made executable: /tmp/$scriptName'
"@
    
    # Send command via SSM
    try {
        $result = aws ssm send-command `
            --instance-ids $InstanceId `
            --document-name "AWS-RunShellScript" `
            --parameters "commands=`"$command`"" `
            --output json | ConvertFrom-Json
        
        $commandId = $result.Command.CommandId
        Write-Host "   ✓ Command sent (ID: $commandId)" -ForegroundColor Green
        
        # Wait a moment and check status
        Start-Sleep 3
        $status = aws ssm get-command-invocation `
            --command-id $commandId `
            --instance-id $InstanceId `
            --output json | ConvertFrom-Json
        
        if ($status.Status -eq "Success") {
            Write-Host "   ✅ $scriptName deployed successfully" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️ Status: $($status.Status)" -ForegroundColor Yellow
            if ($status.StandardErrorContent) {
                Write-Host "   Error: $($status.StandardErrorContent)" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "   ❌ Failed to deploy $scriptName`: $_" -ForegroundColor Red
    }
}

Write-Host "`n🎯 Next steps:" -ForegroundColor Yellow
Write-Host "1. Connect to instance: aws ssm start-session --target $InstanceId" -ForegroundColor Cyan
Write-Host "2. Run setup: sudo /tmp/dcv-setup-extended-desktop.sh" -ForegroundColor Cyan
Write-Host "3. If needed, rollback: sudo /tmp/dcv-rollback.sh" -ForegroundColor Cyan