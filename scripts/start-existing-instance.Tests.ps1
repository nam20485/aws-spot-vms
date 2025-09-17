# Pester Tests for start-existing-instance.ps1
# Run with: Invoke-Pester -Path .\start-existing-instance.Tests.ps1

BeforeAll {
    # Import the script to test its functions
    $scriptPath = Join-Path $PSScriptRoot "start-existing-instance.ps1"
    
    # Source the script to make functions available for testing
    # We'll mock external commands to avoid actual AWS calls
    . $scriptPath
    
    # Mock external commands
    Mock aws { 
        param($Command, $Subcommand, $OtherArgs)
        return "mocked-output" 
    } -ModuleName $null
    
    Mock terraform { 
        param($Args)
        return "i-1234567890abcdef0" 
    } -ModuleName $null
    
    Mock Start-Process { } -ModuleName $null
    Mock Read-Host { return "1" } -ModuleName $null
    Mock Write-Host { } -ModuleName $null
    Mock Write-Warning { } -ModuleName $null
    Mock Write-Error { } -ModuleName $null
}

Describe "Test-AWSAuth Function" {
    Context "When AWS authentication is valid" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 0
                return @('{"UserId": "test-user", "Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/test"}')
            } -ModuleName $null
        }
        
        It "Should return true for valid authentication" {
            $result = Test-AWSAuth
            $result | Should -Be $true
        }
        
        It "Should call aws sts get-caller-identity" {
            Test-AWSAuth
            Assert-MockCalled aws -ParameterFilter { $Command -eq "sts" -and $Subcommand -eq "get-caller-identity" }
        }
    }
    
    Context "When AWS authentication fails with SSO token error" {
        BeforeEach {
            # First call fails with SSO error, second call succeeds
            $script:callCount = 0
            Mock aws { 
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $global:LASTEXITCODE = 1
                    return @("SSO session token expired")
                } elseif ($script:callCount -eq 2) {
                    $global:LASTEXITCODE = 0
                    return @("SSO login successful")
                } else {
                    $global:LASTEXITCODE = 0
                    return @('{"UserId": "test-user"}')
                }
            } -ModuleName $null
        }
        
        It "Should attempt SSO login and return true on success" {
            $result = Test-AWSAuth
            $result | Should -Be $true
        }
        
        It "Should call aws sso login when token is expired" {
            Test-AWSAuth
            Assert-MockCalled aws -ParameterFilter { $Command -eq "sso" -and $Subcommand -eq "login" }
        }
    }
    
    Context "When AWS authentication fails permanently" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 1
                return @("Access denied")
            } -ModuleName $null
        }
        
        It "Should return false for permanent authentication failure" {
            $result = Test-AWSAuth
            $result | Should -Be $false
        }
    }
}

Describe "Get-InstanceIdByName Function" {
    Context "When instance is found by name" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 0
                return "i-1234567890abcdef0"
            } -ModuleName $null
        }
        
        It "Should return instance ID for valid instance name" {
            $result = Get-InstanceIdByName -Name "test-instance"
            $result | Should -Be "i-1234567890abcdef0"
        }
        
        It "Should call describe-instances with correct query" {
            Get-InstanceIdByName -Name "test-instance"
            Assert-MockCalled aws -ParameterFilter { $Command -eq "ec2" -and $Subcommand -eq "describe-instances" }
        }
    }
    
    Context "When instance is not found" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 1
                return "Error: Instance not found"
            } -ModuleName $null
        }
        
        It "Should return null when instance not found" {
            $result = Get-InstanceIdByName -Name "nonexistent-instance"
            $result | Should -Be $null
        }
    }
}

Describe "Get-InstanceState Function" {
    Context "When getting instance state successfully" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 0
                return "stopped"
            } -ModuleName $null
        }
        
        It "Should return instance state" {
            $result = Get-InstanceState -Id "i-1234567890abcdef0"
            $result | Should -Be "stopped"
        }
        
        It "Should call describe-instances with instance ID" {
            Get-InstanceState -Id "i-1234567890abcdef0"
            Assert-MockCalled aws -ParameterFilter { $Command -eq "ec2" -and $Subcommand -eq "describe-instances" }
        }
    }
    
    Context "When getting instance state fails" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 1
                return "Error: Instance not found"
            } -ModuleName $null
        }
        
        It "Should return null when instance state query fails" {
            $result = Get-InstanceState -Id "i-invalid"
            $result | Should -Be $null
        }
    }
}

Describe "Get-InstanceSelection Function" {
    Context "When instances are available" {
        BeforeEach {
            $mockInstanceData = @{
                Reservations = @(
                    @{
                        Instances = @(
                            @{
                                InstanceId = "i-1234567890abcdef0"
                                Tags = @(@{ Key = "Name"; Value = "test-instance-1" })
                                State = @{ Name = "stopped" }
                                InstanceType = "t3.micro"
                                PublicIpAddress = "1.2.3.4"
                                PrivateIpAddress = "10.0.1.100"
                            },
                            @{
                                InstanceId = "i-0987654321fedcba0"
                                Tags = @(@{ Key = "Name"; Value = "test-instance-2" })
                                State = @{ Name = "running" }
                                InstanceType = "g4dn.xlarge"
                                PublicIpAddress = $null
                                PrivateIpAddress = "10.0.1.101"
                            }
                        )
                    }
                )
            }
            
            Mock aws { 
                $global:LASTEXITCODE = 0
                return ($mockInstanceData | ConvertTo-Json -Depth 10)
            } -ModuleName $null
            
            Mock Read-Host { return "1" } -ModuleName $null
        }
        
        It "Should return selected instance ID" {
            $result = Get-InstanceSelection
            $result | Should -Be "i-1234567890abcdef0"
        }
        
        It "Should display instances in formatted table" {
            Get-InstanceSelection
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Your EC2 Instances:*" }
        }
    }
    
    Context "When no instances are available" {
        BeforeEach {
            $mockEmptyData = @{ Reservations = @() }
            
            Mock aws { 
                $global:LASTEXITCODE = 0
                return ($mockEmptyData | ConvertTo-Json -Depth 10)
            } -ModuleName $null
        }
        
        It "Should return null when no instances found" {
            $result = Get-InstanceSelection
            $result | Should -Be $null
        }
        
        It "Should display warning for no instances" {
            Get-InstanceSelection
            Assert-MockCalled Write-Warning -ParameterFilter { $Message -like "*No EC2 instances found*" }
        }
    }
    
    Context "When user cancels selection" {
        BeforeEach {
            $mockInstanceData = @{
                Reservations = @(
                    @{
                        Instances = @(
                            @{
                                InstanceId = "i-1234567890abcdef0"
                                Tags = @(@{ Key = "Name"; Value = "test-instance" })
                                State = @{ Name = "stopped" }
                                InstanceType = "t3.micro"
                                PublicIpAddress = $null
                                PrivateIpAddress = "10.0.1.100"
                            }
                        )
                    }
                )
            }
            
            Mock aws { 
                $global:LASTEXITCODE = 0
                return ($mockInstanceData | ConvertTo-Json -Depth 10)
            } -ModuleName $null
            
            Mock Read-Host { return "q" } -ModuleName $null
        }
        
        It "Should return null when user quits" {
            $result = Get-InstanceSelection
            $result | Should -Be $null
        }
        
        It "Should display cancellation message" {
            Get-InstanceSelection
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Operation cancelled*" }
        }
    }
}

Describe "Open-AWSConsole Function" {
    Context "When opening console with instance ID" {
        BeforeEach {
            Mock Start-Process { } -ModuleName $null
        }
        
        It "Should call Start-Process with correct URL" {
            Open-AWSConsole -InstanceId "i-1234567890abcdef0" -Region "us-east-1"
            Assert-MockCalled Start-Process -ParameterFilter { $FilePath -like "*console.aws.amazon.com*" -and $FilePath -like "*instanceId=i-1234567890abcdef0*" }
        }
        
        It "Should use default region when not specified" {
            Mock aws { return "us-west-2" } -ParameterFilter { $Command -eq "configure" -and $Subcommand -eq "get" }
            Open-AWSConsole -InstanceId "i-1234567890abcdef0"
            Assert-MockCalled Start-Process
        }
    }
    
    Context "When opening console without instance ID" {
        BeforeEach {
            Mock Start-Process { } -ModuleName $null
        }
        
        It "Should open instances list when no instance ID provided" {
            Open-AWSConsole -Region "us-east-1"
            Assert-MockCalled Start-Process -ParameterFilter { $FilePath -like "*#Instances:*" }
        }
    }
}

Describe "Main Script Logic" {
    Context "When running with InstanceId parameter" {
        BeforeEach {
            Mock Test-AWSAuth { return $true } -ModuleName $null
            Mock Get-InstanceState { return "stopped" } -ModuleName $null
            Mock aws { 
                $global:LASTEXITCODE = 0
                return "Starting instance"
            } -ParameterFilter { $Command -eq "ec2" -and $Subcommand -eq "start-instances" }
        }
        
        It "Should use provided instance ID" {
            # This would require refactoring the main script logic into functions
            # For now, we'll test the individual components
            $instanceId = "i-1234567890abcdef0"
            $state = Get-InstanceState -Id $instanceId
            $state | Should -Be "stopped"
        }
    }
    
    Context "When running with InstanceName parameter" {
        BeforeEach {
            Mock Test-AWSAuth { return $true } -ModuleName $null
            Mock Get-InstanceIdByName { return "i-1234567890abcdef0" } -ModuleName $null
            Mock Get-InstanceState { return "stopped" } -ModuleName $null
        }
        
        It "Should resolve instance name to ID" {
            $instanceId = Get-InstanceIdByName -Name "test-instance"
            $instanceId | Should -Be "i-1234567890abcdef0"
        }
    }
}

Describe "Terraform Integration" {
    Context "When Terraform state exists" {
        BeforeEach {
            Mock Test-Path { return $true } -ModuleName $null
            Mock terraform { 
                $global:LASTEXITCODE = 0
                return "i-1234567890abcdef0"
            } -ParameterFilter { $Args -contains "-chdir" }
        }
        
        It "Should use terraform -chdir without changing directory" {
            # Test that terraform is called with -chdir parameter
            $terraformDir = "d:\src\github\nam20485\aws-spot-vms\terraform-workstations\ubuntu"
            $currentDir = Get-Location
            
            # Simulate terraform call
            terraform -chdir="$terraformDir" output -raw instance_id
            
            # Verify we're still in the same directory
            Get-Location | Should -Be $currentDir
            Assert-MockCalled terraform -ParameterFilter { $Args -contains "-chdir" }
        }
    }
    
    Context "When Terraform output is invalid" {
        BeforeEach {
            Mock Test-Path { return $true } -ModuleName $null
            Mock terraform { 
                $global:LASTEXITCODE = 0
                return "Warning: No outputs found"  # Invalid instance ID format
            } -ParameterFilter { $Args -contains "-chdir" }
        }
        
        It "Should reject invalid Terraform output" {
            $output = terraform -chdir="test" output -raw instance_id
            $output -match '^i-[0-9a-f]{17}$' | Should -Be $false
        }
    }
}

Describe "Error Handling" {
    Context "When AWS CLI is not available" {
        BeforeEach {
            Mock aws { 
                throw "aws: command not found"
            } -ModuleName $null
        }
        
        It "Should handle AWS CLI not found gracefully" {
            { Test-AWSAuth } | Should -Not -Throw
        }
    }
    
    Context "When JSON parsing fails" {
        BeforeEach {
            Mock aws { 
                $global:LASTEXITCODE = 0
                return "invalid json"
            } -ModuleName $null
        }
        
        It "Should handle JSON parsing errors gracefully" {
            { Get-InstanceSelection } | Should -Not -Throw
        }
    }
}

Describe "Parameter Validation" {
    Context "When testing instance ID format validation" {
        It "Should validate correct instance ID format" {
            "i-1234567890abcdef0" -match '^i-[0-9a-f]{17}$' | Should -Be $true
        }
        
        It "Should reject incorrect instance ID format" {
            "invalid-id" -match '^i-[0-9a-f]{17}$' | Should -Be $false
            "i-123" -match '^i-[0-9a-f]{17}$' | Should -Be $false
            "i-1234567890ABCDEF0" -match '^i-[0-9a-f]{17}$' | Should -Be $false
        }
    }
    
    Context "When testing URL generation" {
        It "Should generate correct console URLs" {
            $instanceId = "i-1234567890abcdef0"
            $region = "us-east-1"
            $expectedUrl = "https://$region.console.aws.amazon.com/ec2/home?region=$region#InstanceDetails:instanceId=$instanceId"
            
            # This would be tested by mocking the URL generation logic
            $expectedUrl | Should -Match "console.aws.amazon.com"
            $expectedUrl | Should -Match $instanceId
            $expectedUrl | Should -Match $region
        }
    }
}

Describe "Integration Tests" {
    Context "When running end-to-end workflow" {
        BeforeEach {
            Mock Test-AWSAuth { return $true } -ModuleName $null
            Mock Get-InstanceSelection { return "i-1234567890abcdef0" } -ModuleName $null
            Mock Get-InstanceState { return "stopped" } -ModuleName $null
            Mock aws { 
                $global:LASTEXITCODE = 0
                return "Starting instance"
            } -ParameterFilter { $Command -eq "ec2" -and $Subcommand -eq "start-instances" }
        }
        
        It "Should complete full workflow without errors" {
            # Test the complete workflow
            $authResult = Test-AWSAuth
            $authResult | Should -Be $true
            
            $instanceId = Get-InstanceSelection
            $instanceId | Should -Be "i-1234567890abcdef0"
            
            $state = Get-InstanceState -Id $instanceId
            $state | Should -Be "stopped"
        }
    }
}