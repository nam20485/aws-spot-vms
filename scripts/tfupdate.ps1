# Example: restrict DCV and SSH to your current IP
$MyIp = (Invoke-RestMethod -UseBasicParsing 'https://checkip.amazonaws.com').Trim()
$dcvCidrs = "[`"$MyIp/32`"]"
$sshCidrs = "[`"$MyIp/32`"]"

aws sso login

Set-Location -Path 'E:\src\github\nam20485\aws-spot-vms\terraform-workstations\ubuntu'
terraform fmt -recursive
terraform validate
terraform plan -var "allowed_dcv_cidrs=$dcvCidrs" -var "allowed_ssh_cidrs=$sshCidrs" -var "enable_dcv_udp_quic=true"
terraform apply -var "allowed_dcv_cidrs=$dcvCidrs" -var "allowed_ssh_cidrs=$sshCidrs" -var "enable_dcv_udp_quic=true"

$ip = (terraform output -raw workstation_public_ip)
Test-NetConnection -ComputerName $ip -Port 8443

#
# Allow QUIC (> perfor mance than TCP 8443)
#   (test and open UDP)
#

