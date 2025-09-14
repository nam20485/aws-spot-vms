# Terraform provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6.0, < 2.0.0"
}

provider "aws" {
  region = var.aws_region
}

# Provider alias required for the public SSM parameter lookup.
# It ensures the lookup happens in a region where the parameter is guaranteed to exist.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# 1. NETWORKING RESOURCES
# -------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "ubuntu-Workstation-VPC"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "ubuntu-Workstation-IGW"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = {
    Name = "ubuntu-Workstation-Subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "ubuntu-Workstation-RouteTable"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# 2. SECURITY GROUPS
# --------------------------------------
resource "aws_security_group" "workstation_sg" {
  name        = "ubuntu-workstation-sg"
  description = "Controls access to the EC2 Workstation"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ubuntu-workstation-sg"
  }
}

resource "aws_security_group" "fsx_sg" {
  name        = "ubuntu-fsx-lustre-sg"
  description = "Allow Lustre LNET traffic from within the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Lustre LNET traffic"
    from_port   = 988
    to_port     = 988
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ubuntu-fsx-lustre-sg"
  }
}

# 3. STORAGE: FSx for Lustre File System
# -----------------------------------------------------------
resource "aws_fsx_lustre_file_system" "workstation_fs" {
  storage_capacity          = 1200
  subnet_ids                = [aws_subnet.main.id]
  security_group_ids        = [aws_security_group.fsx_sg.id]
  deployment_type           = "SCRATCH_2"
  file_system_type_version  = "2.15"
  # per_unit_storage_throughput is not valid for SCRATCH_2 deployments

  tags = {
    Name = "ubuntu-WorkstationCache"
  }
}

# 4. COMPUTE: The Ubuntu GPU Workstation Instance
# ------------------------------------------------
# IAM Role and Profile
resource "aws_iam_instance_profile" "workstation_profile" {
  name = "ubuntu-workstation-profile"
  role = aws_iam_role.workstation_role.name
}

resource "aws_iam_role" "workstation_role" {
  name = "ubuntu-workstation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "workstation_ssm_core" {
  role       = aws_iam_role.workstation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow the instance to describe FSx resources for diagnostics
resource "aws_iam_role_policy_attachment" "workstation_fsx_readonly" {
  role       = aws_iam_role.workstation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonFSxReadOnlyAccess"
}

# Find the latest Ubuntu 24.04 LTS AMI (using the robust SSM Parameter method)
data "aws_ssm_parameter" "ubuntu_ami" {
  provider = aws.us-east-1 # Use the provider alias for this public parameter lookup
  name     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "workstation" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.workstation_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.workstation_profile.name
  monitoring                  = true
  user_data_replace_on_change = false

  user_data = templatefile("${path.module}/setup_puppet.sh", {
    puppet_manifest = templatefile("${path.module}/workstation.pp", {
      fsx_dns_name   = aws_fsx_lustre_file_system.workstation_fs.dns_name
      fsx_mount_name = aws_fsx_lustre_file_system.workstation_fs.mount_name
    })
  })

  tags = {
    Name = "Ubuntu-GPU-Workstation"
  }
}

# 5. NETWORKING: Elastic IP for a stable address
# ------------------------------------------------
resource "aws_eip" "workstation_ip" {
  instance = aws_instance.workstation.id
  domain   = "vpc"
  tags = {
    Name = "ubuntu-Workstation-EIP"
  }
}

