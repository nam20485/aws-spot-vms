# Manual Deployment Commands for DCV Dual Monitor Setup
# Copy and paste these commands into your EC2 instance terminal

echo "🚀 Creating DCV dual monitor setup script..."

# Create the main setup script
cat > /tmp/dcv-setup-extended-desktop.sh << 'EOF'
#!/usr/bin/env bash
# DCV Dual Monitor Extended Desktop Setup
set -euo pipefail

echo "DCV Dual Monitor Setup Starting..."

# Check for NVIDIA
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: NVIDIA driver not detected. This script requires NVIDIA GPU."
  exit 1
fi

# Create backup directory
BACKUP_DIR="/etc/X11/dcv-backups/$(date +%Y%m%d_%H%M%S)"
echo "Creating backup in: $BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"

# Backup existing Xorg configuration
echo "Backing up existing configuration..."
if [[ -d "/etc/X11/xorg.conf.d" ]]; then
    sudo cp -r /etc/X11/xorg.conf.d "$BACKUP_DIR/"
    echo "  ✓ Backed up /etc/X11/xorg.conf.d/"
fi

if [[ -f "/etc/X11/xorg.conf" ]]; then
    sudo cp /etc/X11/xorg.conf "$BACKUP_DIR/"
    echo "  ✓ Backed up /etc/X11/xorg.conf"
fi

# Backup DCV config
DCV_CONF="/etc/dcv/dcv.conf"
if [[ -f "$DCV_CONF" ]]; then
    sudo cp "$DCV_CONF" "$BACKUP_DIR/"
    echo "  ✓ Backed up DCV configuration"
fi

# Create rollback script
sudo tee "$BACKUP_DIR/rollback.sh" >/dev/null << 'ROLLBACK_EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Rolling back DCV configuration..."

if [[ -d "/etc/X11/dcv-backups/$(basename $(dirname $0))/xorg.conf.d" ]]; then
    sudo rm -rf /etc/X11/xorg.conf.d
    sudo cp -r "/etc/X11/dcv-backups/$(basename $(dirname $0))/xorg.conf.d" /etc/X11/
    echo "  ✓ Restored Xorg configuration"
fi

if [[ -f "/etc/X11/dcv-backups/$(basename $(dirname $0))/dcv.conf" ]]; then
    sudo cp "/etc/X11/dcv-backups/$(basename $(dirname $0))/dcv.conf" /etc/dcv/dcv.conf
    echo "  ✓ Restored DCV configuration"
fi

sudo systemctl restart dcvserver
echo "✅ Rollback complete!"
ROLLBACK_EOF

sudo chmod +x "$BACKUP_DIR/rollback.sh"
echo "  ✓ Created rollback script: $BACKUP_DIR/rollback.sh"

# Save backup location
echo "$BACKUP_DIR" | sudo tee /etc/X11/dcv-latest-backup >/dev/null

echo ""
echo "📋 Backup Summary:"
echo "   Location: $BACKUP_DIR" 
echo "   Rollback: $BACKUP_DIR/rollback.sh"
echo ""

# Confirm before proceeding
read -p "Proceed with dual monitor setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled. Backups preserved."
    exit 0
fi

echo "⚙️ Applying dual monitor configuration..."

# Create dual monitor Xorg configuration
sudo tee /etc/X11/xorg.conf.d/10-nvidia-dual-monitors.conf >/dev/null << 'XORG_EOF'
Section "Device"
    Identifier "NVIDIA Card"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
    # Configure two virtual displays side by side
    Option     "ConnectedMonitor" "DFP-0, DFP-1"
    Option     "MetaModes" "DFP-0: 1920x1080 +0+0, DFP-1: 1920x1080 +1920+0"
    Option     "TwinView" "true"
    Option     "TwinViewXineramaInfoOrder" "DFP-0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "NVIDIA Card"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        # Total virtual desktop: width of both monitors combined
        Virtual 3840 1080
    EndSubSection
EndSection
XORG_EOF

# Configure DCV for dual monitors
if [[ -f "$DCV_CONF" ]]; then
    echo "⚙️ Configuring DCV settings..."
    
    # Ensure display section exists
    if ! grep -q '^\[display\]' "$DCV_CONF"; then 
        echo '' | sudo tee -a "$DCV_CONF" >/dev/null
        echo '[display]' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
    
    # Set layout manager
    if grep -q '^layout-manager=' "$DCV_CONF"; then
        sudo sed -i 's/^layout-manager=.*/layout-manager=automatic/' "$DCV_CONF"
    else
        echo 'layout-manager=automatic' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
    
    # Set target FPS
    if grep -q '^target-fps=' "$DCV_CONF"; then
        sudo sed -i 's/^target-fps=.*/target-fps=25/' "$DCV_CONF"
    else
        echo 'target-fps=25' | sudo tee -a "$DCV_CONF" >/dev/null
    fi
fi

echo "🔄 Restarting services..."

# Restart display manager and DCV
if systemctl is-active --quiet gdm3; then
    sudo systemctl restart gdm3
elif systemctl is-active --quiet lightdm; then
    sudo systemctl restart lightdm
fi

sudo systemctl restart dcvserver

echo ""
echo "✅ Dual Monitor Setup Complete!"
echo ""
echo "📊 Configuration:"
echo "   • Two virtual displays: 1920x1080 each"
echo "   • Layout: Extended desktop (not spanned)"
echo "   • Left Monitor:  X=0-1919,    Y=0-1079"
echo "   • Right Monitor: X=1920-3839, Y=0-1079"
echo ""
echo "🎯 DCV Client Instructions:"
echo "   1. Connect to DCV normally"
echo "   2. In DCV viewer settings:"
echo "      - Enable 'Use all local displays'"
echo "      - Or set to 'Full screen on all displays'"
echo "   3. Each local monitor shows separate desktop area"
echo "   4. Drag windows between monitors normally"
echo ""
echo "🔍 Verification: Run 'xrandr' after DCV connection"
echo "🔄 Rollback: sudo bash $BACKUP_DIR/rollback.sh"
EOF

# Make script executable
chmod +x /tmp/dcv-setup-extended-desktop.sh

echo ""
echo "✅ Script created successfully!"
echo ""
echo "📋 Next Steps:"
echo "1. Run the setup: sudo /tmp/dcv-setup-extended-desktop.sh"
echo "2. Follow the prompts (it will backup everything first)"
echo "3. Connect with DCV client and enable dual monitor mode"
echo ""
echo "🆘 If something goes wrong:"
echo "   • Rollback: sudo bash \$(cat /etc/X11/dcv-latest-backup)/rollback.sh"
echo "   • Or restore manually from backup directory"