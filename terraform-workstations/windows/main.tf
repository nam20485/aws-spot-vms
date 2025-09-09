# Terraform provider configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ------------------------------------------------------------------
# 1. NETWORKING: VPC, Subnet, and Internet Gateway
#    (Largely unchanged from the Linux setup)
# ------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "Workstation-VPC" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "Workstation-Subnet" }
}

# A second subnet in a different AZ is required for AWS Managed Microsoft AD
resource "aws_subnet" "secondary" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}b"
  tags = { Name = "Workstation-Subnet-Secondary" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "Workstation-IGW" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "Workstation-RouteTable" }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "secondary" {
  subnet_id      = aws_subnet.secondary.id
  route_table_id = aws_route_table.main.id
}

# ------------------------------------------------------------------
# 2. IDENTITY: AWS Managed Microsoft Active Directory
#    (Required for FSx for Windows File Server)
# ------------------------------------------------------------------
# Generate a random password for the Active Directory Admin user.
resource "random_password" "ad_password" {
  length           = 16
  special          = true
  override_special = "!#$&*()-_=+[]{}<>:?"
}

# This resource creates a fully managed Active Directory in your VPC.
resource "aws_directory_service_directory" "main" {
  name     = "corp.example.com"
  password = random_password.ad_password.result
  edition  = "Standard"
  type     = "MicrosoftAD"
  size     = "Small"

  vpc_settings {
    vpc_id     = aws_vpc.main.id
    subnet_ids = [aws_subnet.main.id, aws_subnet.secondary.id]
  }
  tags = { Name = "Workstation-AD" }
}

# ------------------------------------------------------------------
# 3. STORAGE: FSx for Windows File Server
# ------------------------------------------------------------------
resource "aws_fsx_windows_file_system" "main" {
  storage_capacity        = 320 # GiB (must be multiple of 32)
  subnet_ids              = [aws_subnet.main.id]
  throughput_capacity     = 128 # MB/s
  deployment_type         = "SINGLE_AZ_1"
  active_directory_id     = aws_directory_service_directory.main.id
  security_group_ids      = [aws_security_group.fsx_sg.id]
  skip_final_backup       = true

  tags = { Name = "Workstation-FSx" }
}

# ------------------------------------------------------------------
# 4. COMPUTE: The Windows GPU Workstation Instance
# ------------------------------------------------------------------
# Find the latest AWS Windows Server 2022 AMI
data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

# This IAM Role allows the EC2 instance to join itself to the Active Directory.
resource "aws_iam_role" "ec2_domain_join" {
  name = "ec2-domain-join-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_core" {
  role       = aws_iam_role.ec2_domain_join.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_directory_service" {
  role       = aws_iam_role.ec2_domain_join.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess"
}

resource "aws_iam_instance_profile" "main" {
  name = "domain-join-instance-profile"
  role = aws_iam_role.ec2_domain_join.name
}

# Create the EC2 instance that will be our workstation.
resource "aws_instance" "workstation" {
  ami                         = data.aws_ami.windows_server.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.workstation_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.main.name
  key_name                    = var.key_name

  # Pass the script to the instance to run on first boot, injecting FSx DNS
  user_data = <<-EOT
  <powershell>
  ${templatefile("${path.module}/workstation_setup.ps1.tmpl", {
    fsx_dns = aws_fsx_windows_file_system.main.dns_name
  })}
  </powershell>
  EOT
  # Allow Terraform to wait longer for Windows to boot and run user_data
  timeouts {
    create = "30m"
  }

  tags = { Name = "GPU-Cloud-Workstation" }
}

# Join the instance to the AWS Managed Microsoft AD domain via SSM
resource "aws_ssm_association" "domain_join" {
  name = "AWS-JoinDirectoryServiceDomain"
  targets {
    key    = "InstanceIds"
    values = [aws_instance.workstation.id]
  }
  parameters = {
    directoryId   = aws_directory_service_directory.main.id
    directoryName = aws_directory_service_directory.main.name
  }
}

# Assign a static (Elastic) IP address to the workstation.
resource "aws_eip" "workstation_ip" {
  instance = aws_instance.workstation.id
  domain   = "vpc"
  tags     = { Name = "Workstation-EIP" }
}


# ------------------------------------------------------------------
# 5. SECURITY GROUPS: Firewalls for our resources
# ------------------------------------------------------------------
resource "aws_security_group" "workstation_sg" {
  name   = "workstation-sg"
  vpc_id = aws_vpc.main.id

  # Allow RDP for remote desktop access from anywhere.
  # WARNING: For production, you should restrict this to your IP address.
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["50.47.212.98/32"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "fsx_sg" {
  name   = "fsx-sg"
  vpc_id = aws_vpc.main.id

  # Allow the workstation to communicate with the file server.
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.workstation_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

