#!/bin/bash
set -e -x

# Create a log file for debugging user_data script issues
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting workstation setup..."

# Wait for cloud-init to finish
sleep 20

# Update package lists and install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -yq build-essential "linux-headers-$(uname -r)" awscli jq

# Install Lustre client for Ubuntu
# See: https://docs.aws.amazon.com/fsx/latest/LustreGuide/install-lustre-client.html
wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-lustre-client-repo-public-key.asc
apt-key add fsx-lustre-client-repo-public-key.asc
add-apt-repository "deb https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu/$(lsb_release -sc)/ main"
apt-get update
apt-get install -y lustre-client-utils

# Install NVIDIA drivers
# See: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/install-nvidia-drivers.html#ubuntu-nvidia-drivers
apt-get install -y ubuntu-drivers-common
ubuntu-drivers autoinstall

# Create mount point for the FSx file system
mkdir -p /fsx

# Mount the file system using variables passed by Terraform
# Note: Terraform populates these variables using the templatefile() function.
mount -t lustre "${fsx_dns_name}@tcp:/${fsx_mount_name}" /fsx

# Make the mount persistent across reboots
echo "${fsx_dns_name}@tcp:/${fsx_mount_name} /fsx lustre defaults,flock,_netdev 0 0" >> /etc/fstab

echo "Setup complete. Rebooting to load NVIDIA drivers..."
reboot

