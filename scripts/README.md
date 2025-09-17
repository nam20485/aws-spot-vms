# Testing Guide for start-existing-instance.ps1

This directory contains comprehensive Pester tests for the `start-existing-instance.ps1` script.

## Prerequisites

- PowerShell 5.1 or later
- Pester 5.0+ (will be auto-installed if missing)
- PSScriptAnalyzer (optional, for code analysis)

## Quick Start

### Run All Tests
```powershell
# Simple test run
.\Run-Tests.ps1

# With code coverage
.\Run-Tests.ps1 -Coverage

# Run specific test
.\Run-Tests.ps1 -TestName "Test-AWSAuth*"
```

### Build Script (includes tests + analysis)
```powershell
# Install PSake if needed
Install-Module -Name psake -Force

# Run full build pipeline
Invoke-psake .\build.ps1

# Run just tests
Invoke-psake .\build.ps1 -taskList Test

# Run analysis only
Invoke-psake .\build.ps1 -taskList Analyze
```

## Test Structure

### Files
- `start-existing-instance.Tests.ps1` - Main test suite
- `Run-Tests.ps1` - Test runner with coverage options
- `build.ps1` - PSake build script with full pipeline
- `README.md` - This file

### Test Categories

#### Unit Tests
- **Test-AWSAuth Function** - Authentication and SSO login handling
- **Get-InstanceIdByName Function** - Instance name resolution
- **Get-InstanceState Function** - Instance state checking
- **Get-InstanceSelection Function** - Interactive instance selection
- **Open-AWSConsole Function** - Browser console integration

#### Integration Tests
- **Main Script Logic** - Parameter handling and workflow
- **Terraform Integration** - Terraform state reading
- **Error Handling** - Graceful failure scenarios
- **Parameter Validation** - Input validation and format checking

#### End-to-End Tests
- **Complete Workflow** - Full script execution simulation

## Test Features

### Mocking Strategy
- **AWS CLI calls** - Mocked to avoid actual AWS API calls
- **Terraform calls** - Mocked to avoid state file dependencies
- **User input** - Mocked for automated testing
- **External processes** - Mocked browser launching, etc.

### Coverage Areas
- ✅ Authentication flows (SSO login, token refresh)
- ✅ Instance discovery (by ID, name, interactive selection)
- ✅ State management (checking, starting instances)
- ✅ Error handling (network failures, invalid inputs)
- ✅ Console integration (URL generation, browser launching)
- ✅ Terraform integration (state reading, path handling)
- ✅ Parameter validation (instance ID format, region names)

### Test Data
Tests use realistic mock data including:
- Valid instance IDs (`i-1234567890abcdef0`)
- Instance states (`stopped`, `running`, `starting`)
- Instance types (`t3.micro`, `g4dn.xlarge`)
- IP addresses (public/private)
- AWS regions (`us-east-1`, `us-west-2`)

## Running Tests in CI/CD

### GitHub Actions Example
```yaml
- name: Run PowerShell Tests
  shell: pwsh
  run: |
    .\scripts\Run-Tests.ps1 -Coverage
    
- name: Upload Coverage
  uses: codecov/codecov-action@v3
  with:
    file: ./scripts/coverage.xml
```

### Azure DevOps Example
```yaml
- task: PowerShell@2
  displayName: 'Run Pester Tests'
  inputs:
    targetType: 'filePath'
    filePath: 'scripts/Run-Tests.ps1'
    arguments: '-Coverage'
    
- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'JUnit'
    testResultsFiles: 'scripts/TestResults.xml'
```

## Test Configuration

### Coverage Thresholds
- **Target**: 80% code coverage
- **Minimum**: 70% (warning threshold)
- **Current**: Run tests to see actual coverage

### Test Categories by Priority
1. **Critical** - Authentication, instance starting
2. **High** - Instance discovery, state management  
3. **Medium** - Console integration, error handling
4. **Low** - Parameter validation, URL generation

## Development Workflow

### Adding New Tests
1. Add test cases to `start-existing-instance.Tests.ps1`
2. Update mocks if needed for new external dependencies
3. Run tests locally: `.\Run-Tests.ps1`
4. Ensure coverage remains above threshold

### Debugging Test Failures
1. Run specific failing test: `.\Run-Tests.ps1 -TestName "FailingTest*"`
2. Check mock configurations in test file
3. Verify test data matches expected formats
4. Use `-PassThru` for detailed Pester output

### Mock Guidelines
- Mock all external calls (AWS CLI, Terraform, etc.)
- Use realistic return data that matches actual API responses
- Set appropriate `$LASTEXITCODE` values for error scenarios
- Mock user interactions (`Read-Host`, `Write-Host`) for automation

## Troubleshooting

### Common Issues
- **Pester not found**: Auto-installs on first run
- **Mock failures**: Check function names and parameter filters
- **Coverage low**: Add tests for uncovered code paths
- **CI failures**: Ensure all dependencies are available

### Mock Verification
```powershell
# Verify mocks are being called correctly
Assert-MockCalled aws -ParameterFilter { $Command -eq "ec2" }
Assert-MockCalled terraform -ParameterFilter { $Args -contains "-chdir" }
```

### Test Isolation
Each test runs in isolation with fresh mocks to prevent test interdependence.

## Best Practices

1. **Test both success and failure paths**
2. **Mock external dependencies completely**
3. **Use realistic test data**
4. **Keep tests focused and atomic**
5. **Document complex test scenarios**
6. **Maintain good coverage of critical paths**

Happy testing! 🧪✨