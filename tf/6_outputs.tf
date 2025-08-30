output "autoscaling_group_name" {
  description = "The name of the ASG managing the workstation. Use this with the workstation.sh script."
  value       = aws_autoscaling_group.workstation_asg.name
}

output "fsx_file_system_id" {
  description = "The ID of the persistent FSx for Lustre file system."
  value       = aws_fsx_lustre_file_system.developer_storage.id
}

output "notification_topic_arn" {
  description = "The ARN of the SNS topic for interruption notifications. Subscribe an email to this topic."
  value       = aws_sns_topic.interruption_notifications.arn
}
