#!/bin/bash
set -e -x

# Create a detailed log file for debugging future issues
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Workstation Setup ---"

# --- 1. System Preparation ---
# Wait for cloud-init to finish its own setup
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  echo 'Waiting for cloud-init to finish...'
  sleep 1
done

echo "Updating package lists..."
apt-get update -y

echo "Installing prerequisite packages..."
apt-get install -y software-properties-common curl wget gnupg lsb-release "linux-headers-$(uname -r)"

# --- 2. Install NVIDIA Drivers ---
echo "Checking for GPU hardware..."
if lspci | grep -i -E 'NVIDIA|3D controller: Amazon'; then
  echo "GPU detected. Beginning driver install sequence..."
  set +e
  echo "Adding NVIDIA CUDA repository key & repo (idempotent)..."
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
  dpkg -i /tmp/cuda-keyring.deb >/dev/null 2>&1 || true
  if ! grep -q 'developer.download.nvidia.com' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /" -y || true
  fi
  echo "Updating apt cache (with retries)..."
  for attempt in 1 2 3 4 5; do
    if apt-get update -y; then
      break
    fi
    echo "apt-get update failed (attempt ${attempt}); retrying in 10s..."
    sleep 10
  done
  echo "Attempting cuda-drivers meta-package install..."
  apt-get install -y cuda-drivers || {
    echo "cuda-drivers failed, falling back to a specific driver version (535 or latest available)."
    apt-cache policy | grep -i nvidia || true
    apt-get install -y nvidia-driver-535 || apt-get install -y nvidia-driver-550 || true
  }
  echo "Verifying NVIDIA driver (non-fatal if not yet loaded)..."
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || echo "nvidia-smi executed but reported an issue. Continuing."
  else
    echo "nvidia-smi not yet available (driver install may require reboot)."
  fi
  set -e
  echo "NVIDIA driver step complete."
else
  echo "No GPU device detected; skipping NVIDIA driver installation."
fi

# --- 3. Install FSx for Lustre Client ---
echo "Installing FSx for Lustre client..."
# Add the AWS repository for the Lustre client
curl -sS https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-main-repo-public-key.asc | apt-key add -
echo "deb https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu jammy main" > /etc/apt/sources.list.d/fsx-lustre-client-repo.list
apt-get update -y

# Install the client and its dependencies
apt-get install -y "lustre-client-modules-$(uname -r)"

echo "FSx client installation complete."

# --- 4. Mount the FSx File System ---
echo "Mounting the FSx file system..."
mkdir -p /fsx

if ! grep -q "/fsx " /proc/mounts; then
  # shellcheck disable=SC2154 # fsx_dns_name & fsx_mount_name are provided via Terraform template interpolation
  for attempt in 1 2 3 4 5 6 7 8; do
    echo "FSx mount attempt ${attempt}..."
    if mount -t lustre -o noatime,flock "${fsx_dns_name}@tcp:/${fsx_mount_name}" /fsx; then
      echo "FSx mounted successfully."
      break
    else
      rc=$?
      echo "Mount failed (exit ${rc}). Retrying in 15s..."
      sleep 15
    fi
  done
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
