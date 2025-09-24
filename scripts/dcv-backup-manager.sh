#!/usr/bin/env bash
# DCV Backup Manager - List and manage DCV configuration backups

set -euo pipefail

BACKUP_BASE="/etc/X11/dcv-backups"
LATEST_BACKUP_FILE="/etc/X11/dcv-latest-backup"

echo "📦 DCV Backup Manager"
echo "===================="

# Function to format file size
format_size() {
    local size=$1
    if [[ $size -gt 1048576 ]]; then
        echo "$(( size / 1048576 ))M"
    elif [[ $size -gt 1024 ]]; then
        echo "$(( size / 1024 ))K"
    else
        echo "${size}B"
    fi
}

# Function to show backup details
show_backup_details() {
    local backup_dir=$1
    local backup_name=$(basename "$backup_dir")
    
    echo "📁 Backup: $backup_name"
    echo "   Location: $backup_dir"
    
    if [[ -f "$backup_dir/xrandr_before.txt" ]]; then
        echo "   Created: $(stat -c %y "$backup_dir/xrandr_before.txt" | cut -d. -f1)"
    else
        echo "   Created: $(stat -c %y "$backup_dir" | cut -d. -f1)"
    fi
    
    # Calculate total size
    local total_size=0
    if [[ -d "$backup_dir" ]]; then
        total_size=$(du -sb "$backup_dir" 2>/dev/null | cut -f1 || echo "0")
    fi
    echo "   Size: $(format_size $total_size)"
    
    echo "   Contents:"
    if [[ -d "$backup_dir/xorg.conf.d" ]]; then
        local file_count=$(ls -1 "$backup_dir/xorg.conf.d/" 2>/dev/null | wc -l)
        echo "     ✓ Xorg config directory ($file_count files)"
    fi
    
    if [[ -f "$backup_dir/xorg.conf" ]]; then
        echo "     ✓ Main xorg.conf file"
    fi
    
    if [[ -f "$backup_dir/dcv.conf" ]]; then
        echo "     ✓ DCV configuration"
    fi
    
    if [[ -f "$backup_dir/xrandr_before.txt" ]]; then
        echo "     ✓ Display configuration snapshot"
    fi
    
    if [[ -f "$backup_dir/rollback.sh" ]]; then
        echo "     ✓ Automated rollback script"
    fi
    
    echo ""
}

# Check if backup directory exists
if [[ ! -d "$BACKUP_BASE" ]]; then
    echo "❌ No backup directory found at $BACKUP_BASE"
    echo "No DCV configuration backups have been created yet."
    exit 0
fi

# List all backups
echo "📋 Available Backups:"
echo ""

backup_count=0
for backup_dir in "$BACKUP_BASE"/*; do
    if [[ -d "$backup_dir" ]]; then
        show_backup_details "$backup_dir"
        ((backup_count++))
    fi
done

if [[ $backup_count -eq 0 ]]; then
    echo "❌ No backups found in $BACKUP_BASE"
    exit 0
fi

# Show latest backup
if [[ -f "$LATEST_BACKUP_FILE" ]]; then
    latest_backup=$(cat "$LATEST_BACKUP_FILE")
    echo "⭐ Latest/Active Backup: $(basename "$latest_backup")"
    echo ""
fi

# Show quick commands
echo "🔧 Quick Commands:"
echo "   Rollback to latest:  sudo bash dcv-rollback.sh"
echo "   Rollback to specific: sudo bash /etc/X11/dcv-backups/YYYYMMDD_HHMMSS/rollback.sh"
echo ""

# Show disk usage summary
total_backup_size=$(du -sh "$BACKUP_BASE" 2>/dev/null | cut -f1 || echo "0")
echo "💾 Total backup disk usage: $total_backup_size"
echo ""

# Cleanup suggestions
if [[ $backup_count -gt 5 ]]; then
    echo "💡 Cleanup suggestion: You have $backup_count backups. Consider removing old ones:"
    echo "   sudo rm -rf $BACKUP_BASE/YYYYMMDD_HHMMSS"
fi