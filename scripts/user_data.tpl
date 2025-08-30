#!/bin/bash
set -ex

# Install the Lustre client using amazon-linux-extras
amazon-linux-extras install -y lustre

# Create the mount point directory
mkdir -p ${fsx_mount_point}

# Mount the FSx for Lustre file system
# The '_netdev' option ensures the instance waits for the network to be available before mounting.
# The 'flock' option is a best practice for Lustre mounts.
mount -t lustre -o noatime,flock ${fsx_dns_name}@tcp:/${fsx_mount_name} ${fsx_mount_point}

# Add an entry to /etc/fstab to make the mount persistent across reboots
echo "${fsx_dns_name}@tcp:/${fsx_mount_name} ${fsx_mount_point} lustre defaults,noatime,flock,_netdev 0 0" >> /etc/fstab

# (Optional) Create a developer user and set ownership
# This part can be expanded or moved into your golden AMI creation process.
if ! id "developer" &>/dev/null; then
    useradd developer
fi
chown -R developer:developer ${fsx_mount_point}
