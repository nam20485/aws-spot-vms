# Finds the latest official AWS-provided Amazon Linux 2 AMI with GPU drivers.
# For production, you should replace this with the ID of your own "golden AMI".
data "aws_ami" "latest_amazon_linux_gpu" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-gpu-hvm-*-x86_64-ebs"]
  }
}

# Renders the user_data.tpl script, injecting the necessary values from our storage configuration.
data "template_file" "user_data" {
  template = file("${path.module}/user_data.tpl")
  vars = {
    fsx_dns_name    = aws_fsx_lustre_file_system.developer_storage.dns_name
    fsx_mount_name  = aws_fsx_lustre_file_system.developer_storage.mount_name
    fsx_mount_point = "/fsx/home/developer" # Example home directory path
  }
}

# Defines the blueprint for our workstation instances.
# Note that instance_type is omitted here, as it will be controlled by the ASG.
resource "aws_launch_template" "gpu_workstation_tpl" {
  name_prefix   = "gpu-workstation-"
  image_id      = data.aws_ami.latest_amazon_linux_gpu.id
  
  vpc_security_group_ids = [aws_security_group.workstation_sg.id]
  user_data              = base64encode(data.template_file.user_data.rendered)

  # This allows the ASG to control the purchasing option (Spot vs On-Demand).
  instance_market_options {
    market_type = "spot"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "GPU-Dev-Workstation"
    }
  }
}

# The Auto Scaling Group that manages the single workstation instance.
# It is configured with a min/max/desired of 0/1/0 so it's off by default.
resource "aws_autoscaling_group" "workstation_asg" {
  name_prefix        = var.asg_name_prefix
  min_size           = 0
  max_size           = 1
  desired_capacity   = 0 # Default to off to save costs
  vpc_zone_identifier = [for s in aws_subnet.main : s.id]
  capacity_rebalance = true # Enable proactive replacement of at-risk Spot instances

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.gpu_workstation_tpl.id
        version            = "$Latest"
      }

      # Defines a list of instance types for diversification.
      # The ASG will try to launch these in order if using a prioritized strategy,
      # or from the deepest capacity pools if using price-capacity-optimized.
      override {
        instance_type = "g5.xlarge"
      }
      override {
        instance_type = "g4dn.xlarge"
      }
      override {
        instance_type = "g6.xlarge"
      }
    }

    instances_distribution {
      on_demand_base_capacity                  = 0
      on_demand_percentage_above_base_capacity = 0 # Prioritize Spot entirely.
      spot_allocation_strategy                 = "price-capacity-optimized"
      on_demand_allocation_strategy            = "prioritized" # Fallback to On-Demand using the override list order.
    }
  }
}
