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

# --- 4b. FSx shared directory and group permissions ---
if grep -q "/fsx " /proc/mounts; then
  echo "Configuring group permissions for /fsx/shared..."

  FSX_GROUP="${FSX_GROUP:-fsxusers}"
  SHARED_DIR="/fsx/shared"

  if ! getent group "$FSX_GROUP" >/dev/null; then
    groupadd -r "$FSX_GROUP" || true
  fi

  # Add typical default user if present
  if id -u ubuntu >/dev/null 2>&1; then
    usermod -a -G "$FSX_GROUP" ubuntu || true
  fi

  # Ensure setfacl is available for default ACLs
  if ! command -v setfacl >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y acl || true
  fi

  install -d -m 2775 -g "$FSX_GROUP" "$SHARED_DIR"
  chown root:"$FSX_GROUP" "$SHARED_DIR" || true

  # Grant rwx to group and set default ACL so new files/dirs inherit group write
  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m g:"$FSX_GROUP":rwx "$SHARED_DIR" || true
    setfacl -d -m g:"$FSX_GROUP":rwx "$SHARED_DIR" || true
  else
    echo "WARNING: setfacl not available; default ACLs not set. Group will have rwx on the top-level only." >&2
  fi

  echo "FSx shared directory ready: $SHARED_DIR (group: $FSX_GROUP, perms: 2775, default ACLs for group)."
else
  echo "Skipping /fsx/shared permissioning because FSx is not mounted."
fi

echo "--- Workstation Setup Complete ---"

# --- 5. NICE DCV Install & Configure ---
echo "Installing and configuring NICE DCV..."

# Ensure DCV helper script is present and executable (embed content for cloud-init availability)
DCV_HELPER="/opt/aws/workstation/setup_dcv.sh"
install -d /opt/aws/workstation
if [ ! -f "$DCV_HELPER" ]; then
  cat > "$DCV_HELPER" <<'SCRIPT'
#!/usr/bin/env bash
#
# Embedded from repository: terraform-workstations/ubuntu/setup_dcv.sh
set -euo pipefail
LOG="/var/log/setup-dcv.log"
exec > >(tee -a "$LOG") 2>&1
echo "[DCV] Starting NICE DCV setup..."
if command -v dcvserver >/dev/null 2>&1; then
  echo "[DCV] Detected existing dcvserver: $(dcvserver --version || true). Skipping install."
else
  echo "[DCV] Updating apt cache..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  echo "[DCV] Installing desktop environment (ubuntu-desktop) and GDM3... (this can take several minutes)"
  if ! dpkg -s ubuntu-desktop >/dev/null 2>&1; then
    apt-get install -y ubuntu-desktop
  fi
  if ! dpkg -s gdm3 >/dev/null 2>&1; then
    apt-get install -y gdm3
  fi
  echo "[DCV] Disabling Wayland in /etc/gdm3/custom.conf..."
  mkdir -p /etc/gdm3
  CUSTOM_CONF="/etc/gdm3/custom.conf"
  if [[ ! -f "$CUSTOM_CONF" ]]; then
    cat > "$CUSTOM_CONF" <<'CFG'
[daemon]
WaylandEnable=false
CFG
  else
    if ! grep -q '^\[daemon\]' "$CUSTOM_CONF"; then
      sed -i '1i [daemon]' "$CUSTOM_CONF"
    fi
    if grep -q '^WaylandEnable=' "$CUSTOM_CONF"; then
      sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$CUSTOM_CONF"
    else
      awk '1; /^\[daemon\]$/ && !x {print "WaylandEnable=false"; x=1}' "$CUSTOM_CONF" >"$CUSTOM_CONF.tmp" && mv "$CUSTOM_CONF.tmp" "$CUSTOM_CONF"
    fi
  fi
  echo "[DCV] Setting default target to graphical.target (start X on boot)"
  systemctl set-default graphical.target || true

  # Ensure GDM3 is the active display manager (LightDM is not supported by DCV on Ubuntu >= 20.04)
  if ! dpkg -s gdm3 >/dev/null 2>&1; then
    apt-get install -y gdm3 || true
  fi
  if dpkg -s lightdm >/dev/null 2>&1; then
    systemctl disable --now lightdm || true
    systemctl enable gdm3 || true
  fi
  . /etc/os-release
  VER_ID="${VERSION_ID:-}"
  if [[ -z "${VER_ID}" ]]; then echo "[DCV] Could not determine Ubuntu VERSION_ID" >&2; exit 1; fi
  ARCH_TAG="x86_64"
  case "$(uname -m)" in
    x86_64) ARCH_TAG="x86_64" ;;
    aarch64|arm64) ARCH_TAG="aarch64" ;;
    *) echo "[DCV] Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  case "$VER_ID" in
    22.04|24.04) UBUNTU_TAG="ubuntu${VER_ID}" ;;
    *) echo "[DCV] Unsupported/untested Ubuntu version $VER_ID. Supported: 22.04, 24.04" >&2; exit 1 ;;
  esac
  WORKDIR="/var/tmp/dcv-install"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"
  URL="https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-${UBUNTU_TAG}-${ARCH_TAG}.tgz"
  echo "[DCV] Downloading DCV archive: $URL"
  if ! curl -fSL "$URL" -o dcv.tgz; then
    echo "[DCV] Failed to fetch $URL. See https://download.amazondcv.com/latest.html for links." >&2
    exit 1
  fi
  echo "[DCV] Extracting archive..."
  rm -rf dcv && mkdir dcv && tar -xzf dcv.tgz -C dcv --strip-components=1
  cd dcv
  echo "[DCV] Installing DCV server and components (.deb packages)"
  apt-get install -y ./nice-dcv-server-*.deb || { echo "[DCV] DCV server install failed" >&2; exit 1; }
  if ls ./nice-dcv-web-viewer-*.deb >/dev/null 2>&1; then apt-get install -y ./nice-dcv-web-viewer-*.deb || true; fi
  if ls ./nice-xdcv-*.deb >/dev/null 2>&1; then apt-get install -y ./nice-xdcv-*.deb || true; fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    if ls ./nice-dcv-gl-*.deb >/dev/null 2>&1; then
      echo "[DCV] NVIDIA GPU detected. Installing DCV GL."
      apt-get install -y ./nice-dcv-gl-*.deb || true
      if ls ./nice-dcv-gltest-*.deb >/dev/null 2>&1; then apt-get install -y ./nice-dcv-gltest-*.deb || true; fi
    fi
  else
    echo "[DCV] NVIDIA GPU not detected. Skipping DCV GL package."
  fi
  echo "[DCV] Enabling and starting dcvserver service"
  systemctl enable dcvserver || true
  systemctl restart dcvserver || systemctl start dcvserver || true
fi
DCV_CONF="/etc/dcv/dcv.conf"
if [[ -f "$DCV_CONF" ]]; then
  echo "[DCV] Applying minimal defaults in $DCV_CONF"
  if ! grep -q '^\[connectivity\]' "$DCV_CONF"; then echo '[connectivity]' >> "$DCV_CONF"; fi
  if ! grep -q '^\[security\]' "$DCV_CONF"; then echo '[security]' >> "$DCV_CONF"; fi
  if grep -q '^#*web-port=' "$DCV_CONF"; then
    sed -i 's/^#*web-port=.*/web-port=8443/' "$DCV_CONF"
  else
    awk '1; /^\[connectivity\]$/ && !x {print "web-port=8443"; x=1}' "$DCV_CONF" >"$DCV_CONF.tmp" && mv "$DCV_CONF.tmp" "$DCV_CONF"
  fi
fi
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[DCV] Configuring headless NVIDIA Xorg (AllowEmptyInitialConfiguration, UseDisplayDevice=None)"
  mkdir -p /etc/X11/xorg.conf.d
  nvidia-xconfig --allow-empty-initial-configuration --use-display-device=None --virtual=1920x1080 || true
  cat >/etc/X11/xorg.conf.d/10-nvidia-headless.conf <<'EOF'
Section "Device"
    Identifier "Nvidia Card"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
EndSection
EOF
fi
echo "[DCV] Restarting services to apply changes (gdm3 and dcvserver)"
systemctl restart gdm3 || true
systemctl restart dcvserver || true
echo "[DCV] NICE DCV setup completed. A reboot is recommended if NVIDIA drivers or desktop packages were newly installed."
SCRIPT
  chmod +x "$DCV_HELPER"
fi

if ! command -v dcvserver >/dev/null 2>&1; then
  bash "$DCV_HELPER" || echo "DCV setup encountered issues; check /var/log/setup-dcv.log" >&2
else
  echo "DCV already installed; ensuring service is running..."
  systemctl enable dcvserver || true
  systemctl restart dcvserver || true
fi

echo "NICE DCV setup step complete."
