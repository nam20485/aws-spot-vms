# Security Group for the FSx for Lustre file system.
# It allows the specific Lustre protocol traffic from the workstation instances.
resource "aws_security_group" "fsx_sg" {
  name        = "fsx-lustre-sg"
  description = "Allow Lustre traffic from workstations"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow Lustre traffic from workstations"
    from_port       = 988
    to_port         = 1023
    protocol        = "tcp"
    security_groups = [aws_security_group.workstation_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "fsx-lustre-sg"
  }
}

# Creates the FSx for Lustre file system.
# PERSISTENT_1 deployment type ensures data is replicated and highly available.
# 1200 GiB is the minimum size for a persistent SSD-based Lustre file system.
resource "aws_fsx_lustre_file_system" "developer_storage" {
  storage_capacity            = 1200
  subnet_ids                 = [aws_subnet.main[0].id] # Deploys in the first AZ for simplicity
  security_group_ids         = [aws_security_group.fsx_sg.id]
  deployment_type            = "PERSISTENT_1"
  per_unit_storage_throughput = 125 # MB/s per TiB of storage

  tags = {
    Name = "Developer-Persistent-Storage"
  }
}
