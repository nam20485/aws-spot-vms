# Project Brief

## Core Requirements and Goals

This project aims to create a cost-effective, persistent GPU-powered cloud workstation solution using AWS Spot Instances. The core requirements are:

1. **Cost Optimization**: Utilize AWS Spot Instances to minimize compute costs for occasional GPU compute needs.
2. **Data Persistence**: Implement a persistent storage solution (FSx for Lustre) to ensure that work is never lost, even when the Spot Instance is terminated or interrupted.
3. **Simple Management**: Provide easy-to-use automation scripts (`workstation.sh`) for developers to start and stop their workstation environment.
4. **Interruption Awareness**: Implement a notification system (EventBridge + SNS) to alert developers of impending Spot Instance interruptions.
5. **Infrastructure as Code**: Define all AWS resources using Terraform to ensure reproducibility and version control of the infrastructure.

The primary goal is to offer developers an affordable and reliable cloud-based GPU workstation that feels as simple to manage as a local machine, while being significantly more cost-effective than using On-Demand instances for the same purpose.