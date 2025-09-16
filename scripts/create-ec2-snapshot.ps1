Param(
  [Parameter(Mandatory=$true)] [string] $InstanceId,
  [Parameter(Mandatory=$false)] [string] $Name = "aws-spot-vms-checkpoint",
  [Parameter(Mandatory=$false)] [string] $Description = "Checkpoint AMI created by aws-spot-vms script",
  [Parameter(Mandatory=$false)] [string] $Region = "us-east-1"
)

# Requires: AWS CLI v2 authenticated with permissions: ec2:CreateImage, ec2:CreateTags, ec2:DescribeImages

Write-Host "Creating AMI from instance $InstanceId in $Region..."
$date = Get-Date -Format "yyyyMMdd-HHmmss"
$amiName = "$Name-$date"

$createCmd = @(
  "ec2",
  "create-image",
  "--instance-id", $InstanceId,
  "--name", $amiName,
  "--description", $Description,
  "--no-reboot",
  "--region", $Region
)

$create = aws @createCmd | ConvertFrom-Json
if (-not $create.ImageId) {
  Write-Error "Failed to create AMI"
  exit 1
}
$imageId = $create.ImageId
Write-Host "AMI creation initiated: $imageId"

Write-Host "Tagging AMI..."
aws ec2 create-tags --region $Region --resources $imageId --tags Key=Name,Value=$amiName Key=Project,Value=aws-spot-vms | Out-Null

Write-Host "Waiting for AMI to become available (this may take several minutes)..."
aws ec2 wait image-available --region $Region --image-ids $imageId

$newImageUrl = "https://$Region.console.aws.amazon.com/ec2/v2/home?region=$Region#ImageDetails:imageId=$imageId"
Write-Host "AMI Ready: ($imageId) $newImageUrl"

# create git tag with the AMI ID
git tag -a $imageId -m "AMI created: $amiName"
git push origin $imageId --tags
Write-Host "Git tag '$imageId' pushed to origin."
