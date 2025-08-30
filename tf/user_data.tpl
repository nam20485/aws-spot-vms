#!/bin/bash

# Install Lustre client (if not already installed in the AMI)
# This command is for Amazon Linux 2
yum update -y
yum install -y lustre-client

# Create the mount point
mkdir -p ${fsx_mount_point}

# Mount the FSx for Lustre file system
mount -t lustre ${fsx_dns_name}@tcp:/${fsx_mount_name} ${fsx_mount_point}

# Add entry to /etc/fstab for automatic mounting on reboot
echo "${fsx_dns_name}@tcp:/${fsx_mount_name} ${fsx_mount_point} lustre defaults,noatime,flock 0 0" >> /etc/fstab

# Create a developer user (optional)
# adduser developer
# chown -R developer:developer ${fsx_mount_point}