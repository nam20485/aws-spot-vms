output "workstation_public_ip" {
  description = "The public IP address of the EC2 workstation."
  value       = aws_eip.workstation_ip.public_ip
}

output "rdp_connection_info" {
  description = "RDP connection string for the Windows workstation."
  value       = "mstsc /v:${aws_eip.workstation_ip.public_ip}"
}

output "fsx_share_path" {
  description = "The UNC path to the FSx for Windows file share (default share)."
  value       = "\\\\${aws_fsx_windows_file_system.main.dns_name}\\share"
}

