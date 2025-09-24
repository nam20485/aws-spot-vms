#!/usr/bin/env bash
# DCV Configuration Rollback Utility
# Rollback any DCV dual monitor configuration to previous state

set -euo pipefail

LATEST_BACKUP_FILE="/etc/X11/dcv-latest-backup"

echo "🔄 DCV Configuration Rollback Utility"
echo "===================================="

# Check if we have a latest backup recorded
if [[ ! -f "$LATEST_BACKUP_FILE" ]]; then
    echo "❌ No backup location found in $LATEST_BACKUP_FILE"
    echo ""
    echo "🔍 Looking for manual backups..."
    
    if [[ -d "/etc/X11/dcv-backups" ]]; then
        echo "📁 Available backups:"
        ls -la /etc/X11/dcv-backups/ | grep "^d" | awk '{print "   " $9}' | grep -v "^\.$\|^\.\.$$"
        echo ""
        echo "To rollback manually, run:"
        echo "   sudo bash /etc/X11/dcv-backups/YYYYMMDD_HHMMSS/rollback.sh"
    else
        echo "❌ No backup directory found at /etc/X11/dcv-backups/"
        echo "Cannot perform automatic rollback."
    fi
    exit 1
fi

BACKUP_DIR=$(cat "$LATEST_BACKUP_FILE")

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "❌ Backup directory not found: $BACKUP_DIR"
    echo "The backup may have been moved or deleted."
    exit 1
fi

echo "📦 Found backup: $BACKUP_DIR"
echo "📅 Backup date: $(basename "$BACKUP_DIR")"
echo ""

# Show what will be restored
echo "🔍 Backup contents:"
if [[ -d "$BACKUP_DIR/xorg.conf.d" ]]; then
    echo "   ✓ Xorg configuration directory"
    ls "$BACKUP_DIR/xorg.conf.d/" | sed 's/^/     - /'
fi

if [[ -f "$BACKUP_DIR/xorg.conf" ]]; then
    echo "   ✓ Main xorg.conf file"
fi

if [[ -f "$BACKUP_DIR/dcv.conf" ]]; then
    echo "   ✓ DCV configuration file"
fi

if [[ -f "$BACKUP_DIR/xrandr_before.txt" ]]; then
    echo "   ✓ Previous display configuration"
fi

echo ""

# Ask for confirmation
read -p "🤔 Proceed with rollback? This will restore the previous configuration (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rollback cancelled."
    exit 0
fi

echo "🔄 Performing rollback..."

# Run the backup's rollback script if it exists
if [[ -f "$BACKUP_DIR/rollback.sh" ]]; then
    echo "   Using backup's rollback script..."
    sudo bash "$BACKUP_DIR/rollback.sh"
else
    echo "   Performing manual rollback..."
    
    # Manual rollback procedure
    DCV_CONF="/etc/dcv/dcv.conf"
    
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
fi

echo ""
echo "✅ Rollback completed successfully!"
echo ""
echo "📋 What was restored:"
echo "   • Xorg configuration files"
echo "   • DCV server configuration"
echo "   • Display manager restarted"
echo "   • DCV server restarted"
echo ""
echo "🔍 To verify, you can:"
echo "   • Check DCV connection works normally"
echo "   • Run 'xrandr' after connecting to see display config"
echo "   • Reboot if you experience any issues: sudo reboot"
echo ""
echo "📁 Backup preserved at: $BACKUP_DIR"