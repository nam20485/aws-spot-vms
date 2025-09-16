output "workstation_public_ip" {
  description = "The public IP address of your Ubuntu GPU workstation."
  value       = aws_eip.workstation_ip.public_ip
}

output "ssh_command" {
  description = "The command to SSH into your workstation. Replace 'path/to/key.pem' with your actual private key file path."
  value       = "ssh -i path/to/key.pem ubuntu@${aws_eip.workstation_ip.public_ip}"
}

output "dcv_client_url" {
  description = "Use this URL in DCV Viewer to connect."
  value       = "https://${aws_eip.workstation_ip.public_ip}:8443"
}

output "workstation_instance_id" {
  description = "EC2 Instance ID of the Ubuntu workstation (for snapshot/AMI)."
  value       = aws_instance.workstation.id
}
