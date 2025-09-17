# Start Ubuntu GPU Workstation Instance
# This script provisions an AWS EC2 Spot Instance using Terraform

param(
    [switch]$AutoApprove,
    [switch]$SkipPlan
)

$terraformDir = "d:\src\github\nam20485\aws-spot-vms\terraform-workstations\ubuntu"

Write-Host "Starting Ubuntu GPU workstation instance..." -ForegroundColor Green
Write-Host "Working directory: $terraformDir" -ForegroundColor Yellow

# Change to terraform directory
Set-Location -Path $terraformDir

# Format Terraform files
Write-Host "Formatting Terraform files..." -ForegroundColor Cyan
terraform fmt -recursive

# Validate configuration
Write-Host "Validating Terraform configuration..." -ForegroundColor Cyan
terraform validate

if ($LASTEXITCODE -ne 0) {
    Write-Error "Terraform validation failed. Please fix the errors and try again."
    exit 1
}

# Plan (unless skipped)
if (-not $SkipPlan) {
    Write-Host "Planning Terraform changes..." -ForegroundColor Cyan
    terraform plan

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform plan failed. Please check the plan output."
        exit 1
    }
}

# Apply changes
Write-Host "Applying Terraform changes..." -ForegroundColor Cyan
$applyArgs = @()
if ($AutoApprove) {
    $applyArgs += "-auto-approve"
}

terraform apply @applyArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "Instance started successfully!" -ForegroundColor Green
    Write-Host "Use 'terraform output' to see instance details." -ForegroundColor Green
} else {
    Write-Error "Failed to start instance. Check the Terraform output for details."
    exit 1
}