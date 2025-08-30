# Technology Stack and Development Setup

## Technologies Used

- **Terraform**: Infrastructure as Code (IaC) tool used to provision and manage AWS resources.
- **AWS Services**:
  - EC2 (Spot Instances, Auto Scaling Groups, Launch Templates)
  - VPC (Virtual Private Cloud, Subnets, Internet Gateway, Security Groups)
  - FSx for Lustre (Persistent high-performance file storage)
  - EventBridge (Event routing for Spot interruption warnings)
  - SNS (Simple Notification Service for sending alerts)
  - AMI (Amazon Machine Images for the base OS with GPU drivers)
- **Bash**: Scripting language used for the workstation management script (`workstation.sh`).
- **AWS CLI**: Command-line tool used by the management script to interact with AWS services.

## Development Setup

1. **Prerequisites**:
   - Install Terraform.
   - Install the AWS CLI.
   - Configure the AWS CLI with appropriate credentials and default region.

2. **Initialize Terraform**:
   - Navigate to the `tf/` directory.
   - Run `terraform init` to initialize the Terraform working directory and download providers.

3. **Plan and Apply**:
   - Run `terraform plan` to review the execution plan.
   - Run `terraform apply` to create the infrastructure.

4. **Configure Management Script**:
   - After applying Terraform, obtain the Auto Scaling Group name from the output.
   - Edit `scripts/workstation.sh` and replace `YOUR_AUTOSCALING_GROUP_NAME_HERE` with the actual ASG name.

5. **Subscribe to Notifications**:
   - In the AWS Console, find the SNS topic named `spot-interruption-notifications`.
   - Create a subscription (e.g., email) to receive interruption alerts.

## Technical Constraints

- **AWS Region**: The infrastructure is deployed to a single AWS region (default: `us-east-1`).
- **AZ Diversity**: While subnets are created in all available AZs, the FSx file system is deployed in only the first AZ for simplicity.
- **Instance Types**: The list of GPU instance types for Spot diversification is fixed in the ASG configuration.
- **User Data**: The user data script for mounting FSx is currently missing from the codebase but is referenced in the launch template.

## Dependencies

- **Terraform Providers**:
  - `hashicorp/aws`
  - `hashicorp/template` (for rendering user data)
- **AWS Services**:
  - The solution depends on the availability and correct configuration of EC2, VPC, FSx, EventBridge, and SNS services.
  - The workstation instances depend on the availability of Spot capacity for the specified instance types.

## Tool Usage Patterns

- **Terraform Commands**:
  - `terraform init`: Initialize the working directory.
  - `terraform plan`: Preview changes before applying.
  - `terraform apply`: Create or update infrastructure.
  - `terraform output`: Display output values after apply.
- **AWS CLI Commands**:
  - `aws autoscaling set-desired-capacity`: Used by `workstation.sh` to start/stop the workstation.