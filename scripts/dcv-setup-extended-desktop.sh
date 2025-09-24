#!/usr/bin/env bash
# Simple and reliable dual monitor setup for DCV
# Creates extended desktop (two separate displays) not spanned
# Includes comprehensive backup and rollback functionality
set -euo pipefail

# Defaults (can be overridden by flags)
LEFT_RES="1920x1080"
RIGHT_RES="1920x1080"

# Parse simple --left WxH --right WxH flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --left)
            LEFT_RES="$2"; shift 2;;
        --right)
            RIGHT_RES="$2"; shift 2;;
        *)
            echo "Unknown option: $1"; exit 2;;
    esac
done

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "❌ NVIDIA driver not detected. This script requires NVIDIA GPU."
  exit 1
fi

# Create timestamped backup directory
BACKUP_DIR="/etc/X11/dcv-backups/$(date +%Y%m%d_%H%M%S)"
DCV_CONF="/etc/dcv/dcv.conf"
GDM_CUSTOM_CONF="/etc/gdm3/custom.conf"

# Detect NVIDIA GPU BusID (format: PCI:bus:device:function)
BUS_ID=""
if command -v nvidia-xconfig >/dev/null 2>&1; then
    BUS_ID=$(nvidia-xconfig --query-gpu-info 2>/dev/null | awk -F': ' '/PCI BusID/ {print $2; exit}')
fi
if [[ -z "$BUS_ID" ]] && command -v lspci >/dev/null 2>&1; then
    # Parse first NVIDIA device and convert bus:dev.func from hex to decimal
    PCI_ADDR=$(lspci -Dn | awk '/10de:/ {print $1; exit}') # e.g., 0000:00:1e.0
    if [[ -n "$PCI_ADDR" ]]; then
        BUS_HEX=$(echo "$PCI_ADDR" | cut -d: -f2)
        DEV_FUNC=$(echo "$PCI_ADDR" | cut -d: -f3) # e.g., 1e.0
        DEV_HEX=${DEV_FUNC%%.*}
        FUNC=${DEV_FUNC##*.}
        BUS=$((16#$BUS_HEX))
        DEV=$((16#$DEV_HEX))
        BUS_ID="PCI:${BUS}:${DEV}:${FUNC}"
    fi
fi
if [[ -z "$BUS_ID" ]]; then
    BUS_ID="PCI:0:30:0" # fallback common for AWS T4 per Xorg logs
fi

echo "🖥️  Setting up dual monitor extended desktop for DCV..."
echo "📦 Creating backup in: $BACKUP_DIR"

# Create backup directory
sudo mkdir -p "$BACKUP_DIR"

# Backup existing Xorg configuration files
echo "💾 Backing up existing Xorg configuration..."
if [[ -d "/etc/X11/xorg.conf.d" ]]; then
    sudo cp -r /etc/X11/xorg.conf.d "$BACKUP_DIR/"
    echo "   ✓ Backed up /etc/X11/xorg.conf.d/"
fi

if [[ -f "/etc/X11/xorg.conf" ]]; then
    sudo cp /etc/X11/xorg.conf "$BACKUP_DIR/"
    echo "   ✓ Backed up /etc/X11/xorg.conf"
fi

# Backup DCV configuration
if [[ -f "$DCV_CONF" ]]; then
    sudo cp "$DCV_CONF" "$BACKUP_DIR/"
    echo "   ✓ Backed up $DCV_CONF"
else
    echo "   ⚠️  DCV config not found, will create new one"
fi

# Backup GDM custom.conf (Wayland/Xorg setting)
if [[ -f "$GDM_CUSTOM_CONF" ]]; then
    sudo cp "$GDM_CUSTOM_CONF" "$BACKUP_DIR/"
    echo "   ✓ Backed up $GDM_CUSTOM_CONF"
fi

# Backup current X11 settings (if X is running)
if command -v xrandr >/dev/null 2>&1 && DISPLAY=:0 xrandr >/dev/null 2>&1; then
    DISPLAY=:0 xrandr > "$BACKUP_DIR/xrandr_before.txt" 2>&1 || true
    echo "   ✓ Backed up current display configuration"
fi

# Create rollback script
sudo tee "$BACKUP_DIR/rollback.sh" >/dev/null <<EOF
#!/usr/bin/env bash
# Rollback script for DCV dual monitor setup
# Run this script to restore previous configuration
set -euo pipefail

echo "🔄 Rolling back DCV dual monitor configuration..."

# Restore Xorg configuration
if [[ -d "$BACKUP_DIR/xorg.conf.d" ]]; then
    echo "   Restoring /etc/X11/xorg.conf.d/"
    sudo rm -rf /etc/X11/xorg.conf.d
    sudo cp -r "$BACKUP_DIR/xorg.conf.d" /etc/X11/
fi

if [[ -f "$BACKUP_DIR/xorg.conf" ]]; then
    echo "   Restoring /etc/X11/xorg.conf"
    sudo cp "$BACKUP_DIR/xorg.conf" /etc/X11/
fi

# Restore DCV configuration
if [[ -f "$BACKUP_DIR/dcv.conf" ]]; then
    echo "   Restoring DCV configuration"
    sudo cp "$BACKUP_DIR/dcv.conf" "$DCV_CONF"
fi

# Restart services
echo "   Restarting display manager and DCV..."
if systemctl is-active --quiet gdm3; then
    sudo systemctl restart gdm3
elif systemctl is-active --quiet lightdm; then
    sudo systemctl restart lightdm
fi
sudo systemctl restart dcvserver

echo "✅ Rollback complete!"
echo "💡 If you need to reboot: sudo reboot"
EOF

sudo chmod +x "$BACKUP_DIR/rollback.sh"
echo "   ✓ Created rollback script: $BACKUP_DIR/rollback.sh"

# Save backup info for easy access
echo "$BACKUP_DIR" | sudo tee /etc/X11/dcv-latest-backup >/dev/null
echo "   ✓ Backup location saved to /etc/X11/dcv-latest-backup"

echo ""
echo "📋 Backup Summary:"
echo "   Backup location: $BACKUP_DIR"
echo "   Rollback script: $BACKUP_DIR/rollback.sh"
echo "   Quick rollback:  sudo bash \$(cat /etc/X11/dcv-latest-backup)/rollback.sh"
echo ""

# Ask for confirmation before proceeding
read -p "🤔 Proceed with dual monitor setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled. Backups preserved in: $BACKUP_DIR"
    exit 0
fi

echo "⚙️  Applying dual monitor configuration..."

# Ensure Xorg config directory exists
sudo mkdir -p /etc/X11/xorg.conf.d

# Create the dual monitor configuration
LEFT_W=$(echo "$LEFT_RES" | cut -dx -f1)
LEFT_H=$(echo "$LEFT_RES" | cut -dx -f2)
RIGHT_W=$(echo "$RIGHT_RES" | cut -dx -f1)
RIGHT_H=$(echo "$RIGHT_RES" | cut -dx -f2)
VIRTUAL_W=$((LEFT_W + RIGHT_W))
# Use the taller height to avoid panning issues
if [[ "$LEFT_H" -ge "$RIGHT_H" ]]; then VIRTUAL_H="$LEFT_H"; else VIRTUAL_H="$RIGHT_H"; fi

sudo tee /etc/X11/xorg.conf.d/10-nvidia-dual-monitors.conf >/dev/null <<EOF
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
    BusID      "${BUS_ID}"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
    # Configure two virtual displays side by side
    Option     "ConnectedMonitor" "DFP-0, DFP-1"
    Option     "TwinView" "true"
    Option     "TwinViewXineramaInfoOrder" "DFP-0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "NVIDIA Card"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        # Total virtual desktop computed from inputs
        Virtual ${VIRTUAL_W} ${VIRTUAL_H}
    EndSubSection
EndSection
EOF

# Ensure NVIDIA is the primary GPU for Xorg
sudo tee /etc/X11/xorg.conf.d/20-nvidia-primary.conf >/dev/null <<'EOF'
Section "OutputClass"
    Identifier "nvidia-primary"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "PrimaryGPU" "yes"
    Option "AllowEmptyInitialConfiguration" "true"
EndSection
EOF

# Also generate a full xorg.conf to ensure NVIDIA is the primary screen
sudo tee /etc/X11/xorg.conf >/dev/null <<EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection

Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0" 0 0
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "${BUS_ID}"
    Option         "AllowEmptyInitialConfiguration" "true"
    Option         "UseDisplayDevice" "None"
    Option         "ConnectedMonitor" "DFP-0, DFP-1"
    Option         "TwinView" "true"
    Option         "TwinViewXineramaInfoOrder" "DFP-0"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    DefaultDepth    24
    Option         "MetaModes" "DFP-0: ${LEFT_RES} +0+0, DFP-1: ${RIGHT_RES} +${LEFT_W}+0"
    SubSection     "Display"
        Depth       24
        Virtual     ${VIRTUAL_W} ${VIRTUAL_H}
    EndSubSection
EndSection
EOF

# Configure DCV for optimal dual monitor experience
DCV_CONF="/etc/dcv/dcv.conf"
if [[ -f "$DCV_CONF" ]]; then
    echo "⚙️  Configuring DCV settings for dual monitors..."
    
    # Ensure display section exists
    if ! grep -q '^\[display\]' "$DCV_CONF"; then 
        printf '\n[display]\n' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
    
    # Set automatic layout management
    if grep -q '^layout-manager=' "$DCV_CONF"; then
        sudo sed -i 's/^layout-manager=.*/layout-manager=automatic/' "$DCV_CONF"
    else
        echo 'layout-manager=automatic' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
    
    # Optimize frame rate for dual monitors
    if grep -q '^target-fps=' "$DCV_CONF"; then
        sudo sed -i 's/^target-fps=.*/target-fps=25/' "$DCV_CONF"
    else
        echo 'target-fps=25' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
fi

echo "🔄 Restarting services..."

# Restart X11 and DCV
if systemctl is-active --quiet gdm3; then
    sudo systemctl restart gdm3
elif systemctl is-active --quiet lightdm; then
    sudo systemctl restart lightdm
fi

sudo systemctl restart dcvserver

# Ensure GDM uses Xorg (disable Wayland) to honor Xorg configs
if [[ -f "$GDM_CUSTOM_CONF" ]]; then
    if grep -q "^#\?WaylandEnable=" "$GDM_CUSTOM_CONF"; then
        sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' "$GDM_CUSTOM_CONF"
    else
        # make sure [daemon] section exists
        if ! grep -q '^\[daemon\]' "$GDM_CUSTOM_CONF"; then
            echo '[daemon]' | sudo tee -a "$GDM_CUSTOM_CONF" >/dev/null
        fi
        echo 'WaylandEnable=false' | sudo tee -a "$GDM_CUSTOM_CONF" >/dev/null
    fi
    # Restart GDM if running
    if systemctl is-active --quiet gdm3; then
        sudo systemctl restart gdm3 || true
    fi
fi

echo ""
echo "✅ Dual Monitor Setup Complete!"
echo ""
echo "📊 Configuration:"
echo "   • Two virtual displays: ${LEFT_RES} (left) + ${RIGHT_RES} (right)"
echo "   • Layout: Extended desktop (not spanned)"
echo "   • Left Monitor origin:  +0+0"
echo "   • Right Monitor origin: +${LEFT_W}+0"
echo ""
echo "🎯 DCV Client Instructions:"
echo "   1. Connect to DCV normally"
echo "   2. In DCV viewer settings:"
echo "      - Enable 'Use all local displays'"
echo "      - Or manually set to 'Full screen on all displays'"
echo "   3. Each local monitor will show a separate part of the desktop"
echo "   4. You can drag windows between monitors normally"
echo ""
echo "🔍 Verification:"
echo "   After connecting via DCV, run: xrandr"
echo "   You should see two displays configured"
echo ""
echo "💡 Tip: If you need to revert, run:"
echo "   sudo bash \$(cat /etc/X11/dcv-latest-backup)/rollback.sh"
echo ""
echo "🆘 Emergency Recovery:"
echo "   If X11 fails to start, you can still SSH/SSM in and run the rollback script"
echo "   All original files are safely backed up in: $BACKUP_DIR"