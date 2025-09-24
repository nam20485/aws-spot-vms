#!/usr/bin/env bash

# dcv-fix-dual-head.sh
# Enforce Xorg + NVIDIA as primary with a dual-head layout for NICE DCV.
# Safely backs up configs, disables headless snippets (UseDisplayDevice "None"),
# installs a canonical /etc/X11/xorg.conf with MetaModes, restarts GDM, and verifies via xrandr.
#
# Usage:
#   sudo ./dcv-fix-dual-head.sh --left 2560x1440 --right 1920x1440 [--no-restart] [--skip-kms]
#
# Notes:
# - Run on the Ubuntu instance (SSH). Requires sudo.
# - GDM will be restarted unless --no-restart is provided.
# - KMS (nvidia-drm modeset=1) is set unless --skip-kms is provided; reboot may be required to take effect.

set -u

log() { echo "[dcv-fix] $*"; }
fail() { echo "[dcv-fix][ERROR] $*" >&2; exit 1; }

LEFT=""
RIGHT=""
NO_RESTART=0
SKIP_KMS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --left) LEFT=${2:-}; shift 2;;
    --right) RIGHT=${2:-}; shift 2;;
    --no-restart) NO_RESTART=1; shift;;
    --skip-kms) SKIP_KMS=1; shift;;
    -h|--help)
      grep -E "^#" "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) fail "Unknown arg: $1";;
  esac
done

[[ -n "$LEFT" && -n "$RIGHT" ]] || fail "--left and --right are required (e.g., --left 2560x1440 --right 1920x1440)"

parse_wh() {
  local s="$1"
  if [[ "$s" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
  else
    fail "Invalid resolution format: $s (expected WxH)"
  fi
}

read L_W L_H < <(parse_wh "$LEFT")
read R_W R_H < <(parse_wh "$RIGHT")
V_W=$((L_W + R_W))
V_H=$(( L_H > R_H ? L_H : R_H ))

log "Left=${LEFT} (W=${L_W} H=${L_H}); Right=${RIGHT} (W=${R_W} H=${R_H}); Virtual=${V_W}x${V_H}"

# Backup
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/etc/X11/dcv-backups/$TS
sudo mkdir -p "$BACKUP_DIR" || fail "Failed to create backup dir $BACKUP_DIR"
for f in \
  /etc/X11/xorg.conf \
  /etc/dcv/dcv.conf \
  /etc/gdm3/custom.conf \
  /etc/modprobe.d/nvidia-drm.conf
do
  if [[ -f "$f" ]]; then sudo cp -a "$f" "$BACKUP_DIR"/; fi
done
if [[ -d /etc/X11/xorg.conf.d ]]; then sudo cp -a /etc/X11/xorg.conf.d "$BACKUP_DIR"/xorg.conf.d; fi
echo "$BACKUP_DIR" | sudo tee /etc/X11/dcv-latest-backup >/dev/null

# Create rollback helper
ROLLBACK=$BACKUP_DIR/rollback.sh
cat <<'EOS' | sudo tee "$ROLLBACK" >/dev/null
#!/usr/bin/env bash
set -e
BACKUP_DIR=$(dirname "$0")
echo "[rollback] Restoring from $BACKUP_DIR"
[[ -d "$BACKUP_DIR/xorg.conf.d" ]] && sudo rm -rf /etc/X11/xorg.conf.d && sudo cp -a "$BACKUP_DIR/xorg.conf.d" /etc/X11/
[[ -f "$BACKUP_DIR/xorg.conf" ]] && sudo cp -a "$BACKUP_DIR/xorg.conf" /etc/X11/xorg.conf
[[ -f "$BACKUP_DIR/dcv.conf" ]] && sudo cp -a "$BACKUP_DIR/dcv.conf" /etc/dcv/dcv.conf
[[ -f "$BACKUP_DIR/custom.conf" ]] && sudo cp -a "$BACKUP_DIR/custom.conf" /etc/gdm3/custom.conf
[[ -f "$BACKUP_DIR/nvidia-drm.conf" ]] && sudo cp -a "$BACKUP_DIR/nvidia-drm.conf" /etc/modprobe.d/nvidia-drm.conf
echo "[rollback] Done. Consider: sudo systemctl restart gdm3"
EOS
sudo chmod +x "$ROLLBACK"

# Ensure dirs
sudo mkdir -p /etc/X11/xorg.conf.d || true

# Disable headless snippets that force NoScanout / UseDisplayDevice None
for f in /etc/X11/xorg.conf.d/*.conf; do
  [[ -e "$f" ]] || continue
  if grep -Eiq 'UseDisplayDevice\s+"?None"?|NoScanout' "$f"; then
    log "Disabling headless snippet: $f"
    sudo mv "$f" "$f.disabled.$TS"
  fi
done

# Also strip any lingering UseDisplayDevice None from main xorg.conf
if [[ -f /etc/X11/xorg.conf ]]; then
  sudo sed -i -E 's/^(\s*Option\s+"UseDisplayDevice"\s+)"?None"?/\1"DFP-0"/I' /etc/X11/xorg.conf || true
fi

# Ensure NVIDIA is primary via OutputClass
PRIMARY_CONF=/etc/X11/xorg.conf.d/20-nvidia-primary.conf
if [[ ! -f "$PRIMARY_CONF" ]]; then
  cat <<'EOC' | sudo tee "$PRIMARY_CONF" >/dev/null
Section "OutputClass"
    Identifier "nvidia-primary"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "PrimaryGPU" "yes"
EndSection
EOC
fi

# Try to compute a BusID (optional)
BUSID=""
if command -v lspci >/dev/null 2>&1; then
  GPU_ADDR=$(lspci -Dnnd 10de: | awk 'NR==1{print $1}')
  if [[ -n "$GPU_ADDR" ]]; then
    IFS=':.' read -r DOMAIN BUS SLOT FUNC <<<"$GPU_ADDR"
    # convert hex to decimal for BUS and SLOT
    BUS=$((16#$BUS)); SLOT=$((16#$SLOT)); FUNC=${FUNC:-0}
    BUSID="PCI:${BUS}:${SLOT}:${FUNC}"
  fi
fi

# Write canonical /etc/X11/xorg.conf
log "Writing /etc/X11/xorg.conf with MetaModes and Virtual ${V_W}x${V_H}"
TMP_XORG=$(mktemp)
cat > "$TMP_XORG" <<EOC
Section "ServerLayout"
    Identifier     "layout"
    Screen         0 "screen0"
EndSection

Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection

Section "Device"
    Identifier "nvidia"
    Driver     "nvidia"
EOC
if [[ -n "$BUSID" ]]; then
  echo "    BusID      \"$BUSID\"" >> "$TMP_XORG"
fi
cat >> "$TMP_XORG" <<EOC
    Option    "AllowEmptyInitialConfiguration" "false"
    Option    "ConnectedMonitor" "DFP-0, DFP-1"
    Option    "ModeValidation" "AllowNonEdidModes"
EndSection

Section "Screen"
    Identifier "screen0"
    Device     "nvidia"
    Option     "MetaModes" "DFP-0: ${LEFT} +0+0, DFP-1: ${RIGHT} +${L_W}+0"
    Option     "TwinView" "1"
    Option     "TwinViewXineramaInfoOrder" "DFP-0, DFP-1"
    SubSection "Display"
        Virtual ${V_W} ${V_H}
    EndSubSection
EndSection

Section "OutputClass"
    Identifier "nvidia-primary"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "PrimaryGPU" "yes"
EndSection
EOC

sudo cp "$TMP_XORG" /etc/X11/xorg.conf
rm -f "$TMP_XORG"

# Disable Wayland
if [[ -f /etc/gdm3/custom.conf ]]; then
  if grep -q '^#\?WaylandEnable=' /etc/gdm3/custom.conf; then
    sudo sed -i -E 's/^#?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
  else
    sudo sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf || echo '[daemon]
WaylandEnable=false' | sudo tee -a /etc/gdm3/custom.conf >/dev/null
  fi
else
  echo -e "[daemon]\nWaylandEnable=false" | sudo tee /etc/gdm3/custom.conf >/dev/null
fi

# Ensure DRM KMS unless skipped
if [[ "$SKIP_KMS" -eq 0 ]]; then
  echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-drm.conf >/dev/null
  if command -v update-initramfs >/dev/null 2>&1; then
    log "Updating initramfs (KMS change)"
    sudo update-initramfs -u || true
  fi
fi

# Restart gdm (optional)
if [[ "$NO_RESTART" -eq 0 ]]; then
  log "Restarting gdm3"
  sudo systemctl restart gdm3 || true
  # Give it a moment
  sleep 4
fi

# Verify via xrandr using GDM's Xauthority
XAUTH=/run/user/122/gdm/Xauthority
if [[ -f "$XAUTH" ]]; then
  log "xrandr --listmonitors"
  DISPLAY=:0 XAUTHORITY=$XAUTH xrandr --listmonitors || log "xrandr listmonitors failed"
  log "xrandr -q"
  DISPLAY=:0 XAUTHORITY=$XAUTH xrandr -q || log "xrandr -q failed"
else
  log "GDM Xauthority not found at $XAUTH (is gdm running and Xorg started?)"
fi

log "Relevant Xorg.0.log lines (nvidia/metamodes/virtual/primarygpu)"
sudo egrep -in 'nvidia|metamodes|virtual|primarygpu|twinview|connectedmonitor' /var/log/Xorg.0.log 2>/dev/null | tail -n 120 || true

log "Done. If KMS changed, a reboot may be required for full effect."
