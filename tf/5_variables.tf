variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "asg_name_prefix" {
  description = "The prefix for the Auto Scaling Group name. Used by the start/stop script."
  type        = string
  default     = "gpu-workstation-asg-"
}
