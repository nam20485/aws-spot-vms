# PSake build script for start-existing-instance.ps1
# Run with: Invoke-psake .\build.ps1

#Requires -Modules @{ ModuleName="Pester"; ModuleVersion="5.0.0" }

Properties {
    $ProjectRoot = $PSScriptRoot
    $ScriptName = "start-existing-instance.ps1"
    $TestScript = "start-existing-instance.Tests.ps1"
    $ScriptPath = Join-Path $ProjectRoot $ScriptName
    $TestPath = Join-Path $ProjectRoot $TestScript
    $CoverageThreshold = 80
}

Task Default -Depends Test

Task Clean {
    Write-Host "Cleaning up test artifacts..." -ForegroundColor Yellow
    
    $artifactsToRemove = @(
        "coverage.xml",
        "TestResults.xml",
        "*.log"
    )
    
    foreach ($pattern in $artifactsToRemove) {
        $files = Get-ChildItem -Path $ProjectRoot -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            Remove-Item $file.FullName -Force
            Write-Host "Removed: $($file.Name)" -ForegroundColor Gray
        }
    }
}

Task Analyze {
    Write-Host "Running PSScriptAnalyzer..." -ForegroundColor Yellow
    
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Write-Warning "PSScriptAnalyzer not found. Installing..."
        Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck
    }
    
    Import-Module PSScriptAnalyzer -Force
    
    $analysisResults = Invoke-ScriptAnalyzer -Path $ScriptPath -Severity Warning, Error
    
    if ($analysisResults.Count -gt 0) {
        Write-Host "PSScriptAnalyzer found $($analysisResults.Count) issues:" -ForegroundColor Red
        foreach ($result in $analysisResults) {
            Write-Host "  [$($result.Severity)] Line $($result.Line): $($result.Message)" -ForegroundColor Yellow
            Write-Host "    Rule: $($result.RuleName)" -ForegroundColor Gray
        }
        throw "PSScriptAnalyzer found issues that need to be resolved."
    } else {
        Write-Host "PSScriptAnalyzer: No issues found ✓" -ForegroundColor Green
    }
}

Task Test -Depends Clean, Analyze {
    Write-Host "Running Pester tests..." -ForegroundColor Yellow
    
    if (-not (Test-Path $TestPath)) {
        throw "Test file not found: $TestPath"
    }
    
    if (-not (Test-Path $ScriptPath)) {
        throw "Script file not found: $ScriptPath"
    }
    
    # Import Pester
    if (-not (Get-Module -ListAvailable -Name Pester)) {
        Write-Warning "Pester not found. Installing..."
        Install-Module -Name Pester -Force -SkipPublisherCheck
    }
    
    Import-Module Pester -Force
    
    # Configure Pester
    $pesterConfig = [PesterConfiguration]::Default
    $pesterConfig.Run.Path = $TestPath
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.CodeCoverage.Enabled = $true
    $pesterConfig.CodeCoverage.Path = $ScriptPath
    $pesterConfig.CodeCoverage.OutputFormat = 'JaCoCo'
    $pesterConfig.CodeCoverage.OutputPath = Join-Path $ProjectRoot "coverage.xml"
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = Join-Path $ProjectRoot "TestResults.xml"
    
    # Run tests
    $testResults = Invoke-Pester -Configuration $pesterConfig
    
    # Check results
    if ($testResults.FailedCount -gt 0) {
        throw "$($testResults.FailedCount) tests failed"
    }
    
    # Check coverage
    $coveragePercent = [math]::Round($testResults.CodeCoverage.CoveragePercent, 2)
    Write-Host "Code Coverage: $coveragePercent%" -ForegroundColor Cyan
    
    if ($coveragePercent -lt $CoverageThreshold) {
        Write-Warning "Code coverage ($coveragePercent%) is below threshold ($CoverageThreshold%)"
        # Don't fail build for coverage in this case, just warn
    }
    
    Write-Host "All tests passed! ✓" -ForegroundColor Green
}

Task Build -Depends Test {
    Write-Host "Build completed successfully!" -ForegroundColor Green
    Write-Host "Script is ready for use: $ScriptPath" -ForegroundColor Cyan
}

Task CI -Depends Build {
    Write-Host "CI pipeline completed successfully!" -ForegroundColor Green
    
    # Export test results for CI systems
    if (Test-Path (Join-Path $ProjectRoot "TestResults.xml")) {
        Write-Host "Test results available: TestResults.xml" -ForegroundColor Cyan
    }
    
    if (Test-Path (Join-Path $ProjectRoot "coverage.xml")) {
        Write-Host "Coverage report available: coverage.xml" -ForegroundColor Cyan
    }
}