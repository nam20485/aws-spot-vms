output "workstation_public_ip" {
  description = "The public IP address of your Ubuntu GPU workstation."
  value       = aws_eip.workstation_ip.public_ip
}

output "ssh_command" {
  description = "The command to SSH into your workstation. Replace 'path/to/key.pem' with your actual private key file path."
  value       = "ssh -i path/to/key.pem ubuntu@${aws_eip.workstation_ip.public_ip}"
}
