**How to Use These Files**

1. **Prerequisites**: Ensure you have Terraform and the AWS CLI installed and configured with appropriate permissions.
2. **Initialize Terraform**: Open a terminal in the directory containing these files and run `terraform init`.
3. **Plan Deployment**: Run `terraform plan` to see a preview of the resources that will be created.
4. **Apply Configuration**: Run `terraform apply`. Terraform will provision the VPC, FSx file system, and the Auto Scaling Group. It will output the name of the ASG.
5. **Configure Script**: Edit the `workstation.sh` script and replace `YOUR_AUTOSCALING_GROUP_NAME_HERE` with the actual ASG name from the Terraform output.
6. **Start/Stop Workstation**: Developers can now run `./workstation.sh start` to power on their environment and `./workstation.sh stop` to shut it down and stop incurring compute costs.
7. **Subscribe to Notifications**: In the AWS Console, navigate to SNS (Simple Notification Service), find the `spot-interruption-notifications` topic, and create a subscription to receive email alerts for Spot interruptions.

Sources and related content
Mounting your Amazon FSx file system automatically - FSx for Lustre - AWS Documentation
