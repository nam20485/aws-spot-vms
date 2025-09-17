# Test Runner for start-existing-instance.ps1
# This script sets up the test environment and runs all Pester tests

param(
    [switch]$Coverage,
    [switch]$CodeCoverage,
    [string]$TestName = "*",
    [switch]$PassThru
)

# Ensure Pester is installed
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Installing Pester module..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

# Import Pester
Import-Module Pester -Force

# Set up test configuration
$testPath = Join-Path $PSScriptRoot "start-existing-instance.Tests.ps1"
$scriptPath = Join-Path $PSScriptRoot "start-existing-instance.ps1"

# Configure Pester
$pesterConfig = @{
    Run = @{
        Path = $testPath
        PassThru = $PassThru
    }
    Output = @{
        Verbosity = 'Detailed'
    }
    Should = @{
        ErrorAction = 'Stop'
    }
}

# Add code coverage if requested
if ($Coverage -or $CodeCoverage) {
    $pesterConfig.CodeCoverage = @{
        Enabled = $true
        Path = $scriptPath
        OutputFormat = 'JaCoCo'
        OutputPath = Join-Path $PSScriptRoot "coverage.xml"
    }
}

# Filter tests if specific test name provided
if ($TestName -ne "*") {
    $pesterConfig.Filter = @{
        Tag = $TestName
    }
}

Write-Host "Running Pester tests for start-existing-instance.ps1..." -ForegroundColor Green
Write-Host "Test file: $testPath" -ForegroundColor Cyan
Write-Host "Script file: $scriptPath" -ForegroundColor Cyan

# Run the tests
$testResults = Invoke-Pester -Configuration ([PesterConfiguration]$pesterConfig)

# Display results summary
Write-Host "`n" -NoNewline
Write-Host "=" * 80 -ForegroundColor Gray
Write-Host "TEST RESULTS SUMMARY" -ForegroundColor Yellow
Write-Host "=" * 80 -ForegroundColor Gray

if ($testResults) {
    Write-Host "Total Tests: $($testResults.TotalCount)" -ForegroundColor Cyan
    Write-Host "Passed: $($testResults.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($testResults.FailedCount)" -ForegroundColor Red
    Write-Host "Skipped: $($testResults.SkippedCount)" -ForegroundColor Yellow
    Write-Host "Duration: $($testResults.Duration)" -ForegroundColor Cyan
    
    if ($Coverage -or $CodeCoverage) {
        Write-Host "Code Coverage: $([math]::Round($testResults.CodeCoverage.CoveragePercent, 2))%" -ForegroundColor Cyan
        Write-Host "Coverage Report: $(Join-Path $PSScriptRoot 'coverage.xml')" -ForegroundColor Cyan
    }
    
    if ($testResults.FailedCount -gt 0) {
        Write-Host "`nFAILED TESTS:" -ForegroundColor Red
        foreach ($test in $testResults.Failed) {
            Write-Host "  - $($test.FullName)" -ForegroundColor Red
            Write-Host "    $($test.ErrorRecord.Exception.Message)" -ForegroundColor DarkRed
        }
        exit 1
    } else {
        Write-Host "`nAll tests passed! ✓" -ForegroundColor Green
        exit 0
    }
} else {
    Write-Warning "No test results returned"
    exit 1
}