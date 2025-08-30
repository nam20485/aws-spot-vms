provider "aws" {
  region = var.aws_region
}

# Fetches all available Availability Zones in the selected region
# This ensures the Auto Scaling Group can search for Spot capacity across the widest possible area.
data "aws_availability_zones" "available" {
  state = "available"
}

# Creates a dedicated Virtual Private Cloud (VPC) for the workstation environment.
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "gpu-workstation-vpc"
  }
}

# Creates a public subnet in each Availability Zone within the region.
resource "aws_subnet" "main" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "gpu-workstation-subnet-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Creates an Internet Gateway to allow communication between the VPC and the internet.
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "gpu-workstation-igw"
  }
}

# Security Group for the workstation instances.
# Allows SSH access from anywhere (you may want to restrict this in production).
resource "aws_security_group" "workstation_sg" {
  name        = "workstation-sg"
  description = "Allow SSH access to workstations"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
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
    Name = "workstation-sg"
  }
}
