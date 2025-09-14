#!/bin/bash
set -e -x

# Create a detailed log file for debugging future issues
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Workstation Setup ---"

# --- 1. System Preparation ---
# NOTE: This script is executed by cloud-init (user-data). Do NOT wait on cloud-init status here,
# or it will deadlock. Proceed directly with setup.

echo "Updating package lists..."
apt-get update -y

echo "Installing prerequisite packages..."
apt-get install -y software-properties-common curl wget gnupg lsb-release "linux-headers-$(uname -r) unzip"

# install aws cli
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# --- 2. Install NVIDIA Drivers (GRID Driver) ---
echo "Updating package cache and getting package updates..."
apt-get update -y

echo "Installing gcc and make..."
apt-get install -y gcc make

echo "Upgrading linux-aws package..."
apt-get upgrade -y linux-aws

echo "A reboot is required to load the latest kernel version. Please reboot the instance manually after this script completes."
# sudo reboot # Omitted for automated script execution

echo "Installing kernel headers package..."
apt-get install -y "linux-headers-$(uname -r)" "linux-modules-extra-$(uname -r)"

echo "Disabling nouveau open source driver..."
cat << EOF | tee --append /etc/modprobe.d/blacklist.conf
blacklist vga16fb
blacklist nouveau
blacklist rivafb
blacklist nvidiafb
blacklist rivatv
EOF

echo "Editing /etc/default/grub and rebuilding Grub configuration..."
# This sed command adds the line if it doesn't exist, or replaces it if it does.
# It ensures GRUB_CMDLINE_LINUX is set correctly.
sed -i '/^GRUB_CMDLINE_LINUX=/c\GRUB_CMDLINE_LINUX="rdblacklist=nouveau"' /etc/default/grub
update-grub

echo "Downloading the GRID driver installation utility..."
aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ .

echo "Adding execute permissions to the driver installation utility..."
chmod +x NVIDIA-Linux-x86_64*.run

echo "Running the self-install script for GRID driver. Follow prompts if any."
/bin/sh ./NVIDIA-Linux-x86_64*.run

echo "Confirming driver functionality (output will be logged)."
nvidia-smi -q | head

echo "Disabling GSP for NVIDIA vGPU software version 14.x or greater (if applicable)..."
touch /etc/modprobe.d/nvidia.conf
echo "options nvidia NVreg_EnableGpuFirmware=0" | tee --append /etc/modprobe.d/nvidia.conf

echo "NVIDIA GRID driver installation complete. Another reboot is required to apply all changes. Please reboot the instance manually after this script completes."
# sudo reboot # Omitted for automated script execution

# --- 3. Install FSx for Lustre Client ---
echo "Installing FSx for Lustre client..."
# Add the AWS repository for the Lustre client (Ubuntu 24.04 noble) using signed-by keyring
install -m 0755 -d /usr/share/keyrings
curl -fsSL https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-main-repo-public-key.asc | gpg --dearmor | tee /usr/share/keyrings/fsx-lustre.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/fsx-lustre.gpg] https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu noble main" > /etc/apt/sources.list.d/fsx-lustre-client-repo.list
apt-get update -y

# Install the client and its dependencies if available for the running kernel
if apt-cache show "lustre-client-modules-$(uname -r)" >/dev/null 2>&1; then
  apt-get install -y "lustre-client-modules-$(uname -r)" lustre-client-utils
  echo "FSx client installation complete."
else
  echo "FSx client for kernel $(uname -r) is not available in the FSx repo yet. Skipping install to avoid failure."
fi

# --- 4. Mount the FSx File System ---
echo "Mounting the FSx file system..."
mkdir -p /fsx

# Only attempt to mount if the Lustre client is present
if lsmod | grep -q lustre || modinfo lustre >/dev/null 2>&1; then
  if ! grep -q "/fsx " /proc/mounts; then
    # shellcheck disable=SC2154 # fsx_dns_name & fsx_mount_name are provided via Terraform template interpolation
    for attempt in 1 2 3 4 5 6 7 8; do
      echo "FSx mount attempt $${attempt}..."
      if mount -t lustre -o noatime,flock "${fsx_dns_name}@tcp:/${fsx_mount_name}" /fsx; then
        echo "FSx mounted successfully."
        break
      else
        rc=$?
        echo "Mount failed (exit $${rc}). Retrying in 15s..."
        sleep 15
      fi
    done
  fi
else
  echo "Lustre client kernel module not present; skipping FSx mount."
fi

if ! grep -q "/fsx " /proc/mounts; then
  echo "WARNING: FSx still not mounted after retries." >&2
else
  # Ensure single fstab entry
  if ! grep -q "${fsx_dns_name}@tcp:/${fsx_mount_name} /fsx lustre" /etc/fstab; then
    echo "${fsx_dns_name}@tcp:/${fsx_mount_name} /fsx lustre noatime,flock,_netdev 0 0" >> /etc/fstab
  fi
  echo "Verifying FSx mount..."
  df -h | grep /fsx || true
fi

echo "--- Workstation Setup Complete ---"
