#!/usr/bin/env bash
# Fix headless NVIDIA Xorg for DCV console sessions on Ubuntu (LightDM/GDM)
# Safe to run multiple times.
set -euo pipefail

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA driver not detected (nvidia-smi missing). Aborting."
  exit 1
fi

sudo mkdir -p /etc/X11/xorg.conf.d
sudo nvidia-xconfig --allow-empty-initial-configuration --use-display-device=None --virtual=1920x1080 || true
sudo tee /etc/X11/xorg.conf.d/10-nvidia-headless.conf >/dev/null <<'EOF'
Section "Device"
    Identifier "Nvidia Card"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
EndSection
EOF

# Restart display manager and DCV
if systemctl list-unit-files | grep -q '^gdm3\.service'; then
  sudo systemctl restart gdm3 || true
fi
if systemctl list-unit-files | grep -q '^lightdm\.service'; then
  sudo systemctl restart lightdm || true
fi
sudo systemctl restart dcvserver || true

echo "Headless NVIDIA Xorg configured. If this is the first driver install or kernel changed, consider rebooting." 
