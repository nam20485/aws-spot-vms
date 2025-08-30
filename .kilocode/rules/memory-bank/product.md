2# Product Overview

## Purpose

This project provides a cost-effective solution for developers who need occasional access to GPU-powered cloud workstations. It leverages AWS Spot Instances to significantly reduce compute costs compared to On-Demand instances, while using persistent storage (FSx for Lustre) to ensure work is never lost when the instance is terminated.

## Problems Solved

1. **High Cost of GPU Instances**: GPU instances on AWS can be very expensive for developers who only need them occasionally. Spot Instances can offer up to 90% savings.
2. **Data Persistence**: When a Spot Instance is interrupted, work can be lost. This solution uses a persistent file system (FSx for Lustre) that remains available even when the instance is terminated.
3. **Manual Management**: Manually starting and stopping instances can be cumbersome. This project includes automation scripts to simplify the process.

## How It Works

1. **Infrastructure**: Terraform is used to create the necessary AWS resources:
   - A dedicated VPC with public subnets.
   - An FSx for Lustre file system for persistent storage.
   - An Auto Scaling Group (ASG) configured to manage a single Spot Instance as a "workstation".
   - Security groups to control access.
   - EventBridge rule and SNS topic for Spot interruption notifications.

2. **Workstation Management**:
   - A simple bash script (`workstation.sh`) allows developers to start and stop their workstation by adjusting the desired capacity of the ASG.
   - When started, the ASG launches a Spot Instance using a launch template.
   - The instance automatically mounts the FSx file system on boot via user data.
   - When stopped (or interrupted), the instance is terminated, but the file system persists.

3. **Spot Interruption Handling**:
   - AWS sends a 2-minute warning before terminating a Spot Instance.
   - An EventBridge rule captures this event and sends a notification via SNS.
   - Developers can subscribe to the SNS topic to receive email alerts about impending interruptions.

## User Experience Goals

- **Cost-Effective**: Minimize compute costs by using Spot Instances.
- **Persistent**: Ensure no work is lost due to instance termination.
- **Simple**: Provide easy-to-use scripts for common operations.
- **Reliable**: Handle Spot interruptions gracefully with notifications.