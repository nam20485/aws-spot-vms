variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type for the workstation (must be a GPU instance)."
  type        = string
  default     = "g4dn.xlarge" # Good starting point with NVIDIA T4 GPU
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the Subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "key_name" {
  description = "The name of your AWS EC2 key pair for SSH access."
  type        = string
  # IMPORTANT: You must change this to the name of a key pair that exists in your account.
  default = "aws-spot-vms2"
}

# CIDR blocks allowed to access DCV (TCP 8443 and optional UDP 8443)
variable "allowed_dcv_cidrs" {
  description = "List of CIDR blocks allowed to access NICE DCV (port 8443)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# CIDR blocks allowed to access SSH
variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to access SSH (port 22)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Enable UDP QUIC for DCV (UDP 8443)
variable "enable_dcv_udp_quic" {
  description = "Whether to allow UDP 8443 for DCV QUIC."
  type        = bool
  default     = true
}
