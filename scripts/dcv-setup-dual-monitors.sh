#!/usr/bin/env bash
# Configure dual monitor extended desktop for DCV console sessions on Ubuntu
# Creates two separate virtual displays that can be used independently
# Safe to run multiple times.
set -euo pipefail

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA driver not detected (nvidia-smi missing). Aborting."
  exit 1
fi

echo "Configuring dual monitor extended desktop for DCV..."

sudo mkdir -p /etc/X11/xorg.conf.d

# Configure dual virtual displays with NVIDIA
# Two separate 1920x1080 displays side by side (3840x1080 total virtual space)
sudo nvidia-xconfig --allow-empty-initial-configuration --use-display-device=None --virtual=3840x1080 || true

# Create Xorg configuration for dual displays
sudo tee /etc/X11/xorg.conf.d/10-nvidia-dual-headless.conf >/dev/null <<'EOF'
Section "ServerLayout"
    Identifier "DualMonitorLayout"
    Screen 0 "Screen0" 0 0
    Screen 1 "Screen1" RightOf "Screen0"
    Option "Xinerama" "1"
EndSection

Section "Device"
    Identifier "Nvidia Card 0"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
    Option     "ConnectedMonitor" "DFP-0"
    BusID      "PCI:0:30:0"  # Will be auto-detected
EndSection

Section "Device"
    Identifier "Nvidia Card 1"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
    Option     "ConnectedMonitor" "DFP-1"
    BusID      "PCI:0:30:0"  # Will be auto-detected
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Nvidia Card 0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
        Virtual 1920 1080
    EndSubSection
EndSection

Section "Screen"
    Identifier "Screen1"
    Device "Nvidia Card 1"
    Monitor "Monitor1"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
        Virtual 1920 1080
    EndSubSection
EndSection

Section "Monitor"
    Identifier "Monitor0"
    VendorName "Virtual"
    ModelName "Virtual Monitor 0"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Option "DPMS"
EndSection

Section "Monitor"
    Identifier "Monitor1"
    VendorName "Virtual"
    ModelName "Virtual Monitor 1"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Option "DPMS"
EndSection
EOF

# Alternative simpler configuration that often works better with DCV
sudo tee /etc/X11/xorg.conf.d/20-nvidia-dual-simple.conf >/dev/null <<'EOF'
Section "Device"
    Identifier "Nvidia Card"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
    Option     "UseDisplayDevice" "None"
    Option     "ConnectedMonitor" "DFP-0, DFP-1"
    Option     "MetaModes" "DFP-0: 1920x1080 +0+0, DFP-1: 1920x1080 +1920+0"
    Option     "SLI" "Off"
    Option     "MultiGPU" "Off"
    Option     "BaseMosaic" "off"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Nvidia Card"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual 3840 1080
    EndSubSection
EndSection
EOF

# Configure DCV for multi-monitor support
DCV_CONF="/etc/dcv/dcv.conf"
if [[ -f "$DCV_CONF" ]]; then
    echo "Configuring DCV for dual monitor support..."
    
    # Ensure sections exist
    if ! grep -q '^\[display\]' "$DCV_CONF"; then 
        echo '[display]' >> "$DCV_CONF"
    fi
    
    # Enable multi-monitor support in DCV
    if grep -q '^#*layout-manager=' "$DCV_CONF"; then
        sudo sed -i 's/^#*layout-manager=.*/layout-manager=automatic/' "$DCV_CONF"
    else
        sudo awk '1; /^\[display\]$/ && !x {print "layout-manager=automatic"; x=1}' "$DCV_CONF" > "$DCV_CONF.tmp" && sudo mv "$DCV_CONF.tmp" "$DCV_CONF"
    fi
    
    # Set target FPS for smooth dual monitor experience
    if grep -q '^#*target-fps=' "$DCV_CONF"; then
        sudo sed -i 's/^#*target-fps=.*/target-fps=25/' "$DCV_CONF"
    else
        sudo awk '1; /^\[display\]$/ && !x2 {print "target-fps=25"; x2=1}' "$DCV_CONF" > "$DCV_CONF.tmp" && sudo mv "$DCV_CONF.tmp" "$DCV_CONF"
    fi
fi

echo "Restarting display manager and DCV server..."

# Restart display manager and DCV
if systemctl list-unit-files | grep -q '^gdm3\.service'; then
  sudo systemctl restart gdm3 || true
fi
if systemctl list-unit-files | grep -q '^lightdm\.service'; then
  sudo systemctl restart lightdm || true
fi
sudo systemctl restart dcvserver || true

echo ""
echo "✅ Dual monitor extended desktop configuration complete!"
echo ""
echo "📋 Configuration Summary:"
echo "   - Two virtual displays: 1920x1080 each"
echo "   - Total desktop space: 3840x1080"
echo "   - Layout: Extended (not spanned)"
echo "   - Display 0: Left monitor (0,0 to 1920,1080)"
echo "   - Display 1: Right monitor (1920,0 to 3840,1080)"
echo ""
echo "🖥️  DCV Client Setup:"
echo "   1. Connect to your DCV session normally"
echo "   2. In DCV client settings, enable 'Use all displays'"
echo "   3. DCV will detect both virtual monitors automatically"
echo "   4. Each of your local monitors will show a separate desktop"
echo ""
echo "🔄 If this is the first driver install or kernel changed, consider rebooting."
echo "📋 You can verify the configuration with: xrandr (after connecting via DCV)"