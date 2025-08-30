# Architecture

## System Architecture

The system is designed to provide a cost-effective, persistent GPU-powered cloud workstation using AWS Spot Instances. The architecture consists of several key components:

1. **Networking Layer**:
   - A dedicated Virtual Private Cloud (VPC) is created for isolation.
   - Public subnets are created in all available Availability Zones (AZs) within the selected region to maximize Spot capacity diversity for the Auto Scaling Group (ASG).
   - An Internet Gateway enables communication between the VPC and the internet.

2. **Storage Layer**:
   - An FSx for Lustre file system provides persistent storage.
   - A security group (`fsx_sg`) is configured to allow Lustre protocol traffic (ports 988-1023 TCP) exclusively from the workstation security group.

3. **Compute Layer**:
   - An Auto Scaling Group (ASG) manages a single EC2 instance, acting as the developer's workstation.
   - The ASG is configured with a minimum size of 0, maximum size of 1, and a desired capacity of 0 by default, meaning the workstation is "off" and not incurring compute costs unless explicitly started.
   - The ASG uses a launch template (`gpu_workstation_tpl`) to define the instance configuration.
   - Spot Instances are prioritized using a "price-capacity-optimized" allocation strategy across a diversified list of GPU instance types (e.g., `g5.xlarge`, `g4dn.xlarge`, `g6.xlarge`).
   - Capacity rebalancing is enabled to proactively replace Spot Instances at elevated risk of termination.
   - A security group (`workstation_sg`) controls inbound SSH access to the instances.

4. **Automation and Notifications**:
   - An EventBridge rule captures EC2 Spot Instance Interruption Warnings.
   - An SNS topic (`interruption_notifications`) is used to send notifications about impending interruptions.
   - The EventBridge rule is configured to send events to the SNS topic.

5. **Management Scripts**:
   - A bash script (`workstation.sh`) provides a simple interface for developers to start and stop their workstation by adjusting the ASG's desired capacity.

## Source Code Paths

- `tf/`: Contains all Terraform configuration files.
  - `1_main.tf`: Provider configuration, AZ data source, VPC, subnets, and Internet Gateway.
  - `2_storage.tf`: FSx for Lustre file system and its security group.
  - `3_compute.tf`: AMI data source, launch template (including user data), and Auto Scaling Group.
  - `4_automation.tf`: EventBridge rule, SNS topic, and event target for Spot interruption notifications.
  - `5_variables.tf`: Input variables for the Terraform configuration.
  - `6_outputs.tf`: Output values for the ASG name, FSx file system ID, and SNS topic ARN.
- `scripts/workstation.sh`: Bash script for starting and stopping the workstation.

## Key Technical Decisions

- **Spot Instances**: Chosen for significant cost savings over On-Demand instances for occasional GPU compute needs.
- **FSx for Lustre**: Selected for high-performance, persistent storage that survives instance termination.
- **Auto Scaling Group**: Used to manage a single instance as a "workstation" with simple start/stop semantics via desired capacity.
- **User Data Script**: Used to automatically mount the FSx file system on instance boot.
- **Price-Capacity-Optimized**: Allocation strategy for Spot Instances to balance cost and the likelihood of getting an instance from a deep capacity pool.

## Design Patterns in Use

- **Infrastructure as Code (IaC)**: Terraform is used to define and provision all AWS resources.
- **Separation of Concerns**: Terraform configuration is split into multiple files based on resource type (networking, storage, compute, automation).
- **Declarative Management**: The desired state of the infrastructure is declared, and Terraform handles the creation and updates.

## Component Relationships

- The VPC contains the subnets and Internet Gateway.
- The FSx file system is associated with a subnet and uses the `fsx_sg` security group.
- The ASG launches instances based on the `gpu_workstation_tpl` launch template into the VPC subnets and uses the `workstation_sg` security group.
- The launch template references the user data script to mount the FSx file system.
- The EventBridge rule monitors for Spot interruption events related to instances in the ASG.
- The SNS topic receives events from the EventBridge rule.
- The `workstation.sh` script interacts with the ASG via the AWS CLI to change its desired capacity.

## Critical Implementation Paths

- **Instance Launch**: When the ASG launches an instance, it must successfully mount the FSx file system. This depends on the user data script and correct security group configuration.
- **Interruption Handling**: When a Spot interruption occurs, the EventBridge rule must capture the event and send it to the SNS topic. This requires correct IAM permissions and EventBridge rule configuration.