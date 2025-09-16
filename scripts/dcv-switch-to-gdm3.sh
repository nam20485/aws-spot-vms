#!/usr/bin/env bash
# Switch an existing Ubuntu 22.04/24.04 system to GDM3 for Amazon DCV
# Disables LightDM if installed, disables Wayland, restarts display manager and DCV.
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script is intended for Debian/Ubuntu systems with apt-get." >&2
  exit 1
fi

# Install gdm3 if missing
if ! dpkg -s gdm3 >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y gdm3
fi

# Disable LightDM if present
if dpkg -s lightdm >/dev/null 2>&1; then
  sudo systemctl disable --now lightdm || true
fi

# Ensure GDM3 enabled
sudo systemctl enable gdm3 || true

# Disable Wayland in GDM3
sudo mkdir -p /etc/gdm3
sudo bash -c 'cat >/etc/gdm3/custom.conf <<EOF
[daemon]
WaylandEnable=false
EOF'

# Restart display manager and DCV
sudo systemctl restart gdm3 || true
sudo systemctl restart dcvserver || true

echo "GDM3 is active with Wayland disabled. If NVIDIA drivers were recently installed/updated, a reboot may be required." 
