#!/usr/bin/env bash
set -euo pipefail

log() { echo "[diag] $*"; }
section() { echo; echo "==== $* ===="; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log "Some checks require root. Re-run with: sudo $0" >&2
    return 1
  fi
}

section "System summary"
date || true
uname -a || true
echo "Kernel: $(uname -r)"
if command -v curl >/dev/null 2>&1; then
  ITYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type || true)
  IID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id || true)
  echo "Instance: ${IID:-unknown} Type: ${ITYPE:-unknown}"
else
  echo "curl not available to query instance metadata"
fi

section "Cloud-init & user-data logs"
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --long || true
else
  log "cloud-init command not found"
fi

echo "--- tail /var/log/cloud-init-output.log (last 200) ---"
sudo tail -n 200 /var/log/cloud-init-output.log 2>/dev/null || tail -n 200 /var/log/cloud-init-output.log 2>/dev/null || true

echo "--- tail /var/log/cloud-init.log (last 200) ---"
sudo tail -n 200 /var/log/cloud-init.log 2>/dev/null || tail -n 200 /var/log/cloud-init.log 2>/dev/null || true

echo "--- tail /var/log/user-data.log (last 200) ---"
sudo tail -n 200 /var/log/user-data.log 2>/dev/null || tail -n 200 /var/log/user-data.log 2>/dev/null || true

section "GPU/NVIDIA"
if command -v lspci >/dev/null 2>&1; then
  lspci | egrep -i 'nvidia|3d' || echo "No NVIDIA/3D controller found via lspci"
else
  echo "lspci not found"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || echo "nvidia-smi present but returned non-zero"
else
  echo "nvidia-smi not found (driver may not be installed yet)"
fi

section "FSx Lustre client"
dpkg -l | grep -i lustre || echo "No lustre packages found via dpkg"
lsmod | grep -i lustre || echo "lustre kernel module not loaded"

echo "--- fstab entry for /fsx ---"
grep -n "[[:space:]]/fsx[[:space:]]" /etc/fstab || echo "No /fsx entry in /etc/fstab"

echo "--- current mount status ---"
df -h | grep /fsx || echo "/fsx not mounted"

# Optionally retry mount if FSx variables are available (via env or fstab)
FSX_DNS_NAME=${FSX_DNS_NAME:-}
FSX_MOUNT_NAME=${FSX_MOUNT_NAME:-}

if [[ -z "$FSX_DNS_NAME" || -z "$FSX_MOUNT_NAME" ]]; then
  # Try to parse from fstab
  if grep -q "[[:space:]]/fsx[[:space:]]lustre" /etc/fstab; then
    SRC=$(awk '$2=="/fsx" && $3=="lustre" {print $1}' /etc/fstab | head -n1)
    # Expect format: <dns>@tcp:/<mountname>
    if [[ "$SRC" =~ ^([^@]+)@tcp:/(.+)$ ]]; then
      FSX_DNS_NAME="${BASH_REMATCH[1]}"
      FSX_MOUNT_NAME="${BASH_REMATCH[2]}"
    fi
  fi
fi

if mountpoint -q /fsx; then
  log "/fsx already mounted"
else
  if [[ -n "${FSX_DNS_NAME}" && -n "${FSX_MOUNT_NAME}" ]]; then
    log "Attempting to mount FSx using ${FSX_DNS_NAME}@tcp:/${FSX_MOUNT_NAME}"
    if require_root; then
      sudo mkdir -p /fsx
      set +e
      sudo mount -t lustre -o noatime,flock "${FSX_DNS_NAME}@tcp:/${FSX_MOUNT_NAME}" /fsx
      RC=$?
      set -e
      if [[ $RC -eq 0 ]]; then
        log "FSx mounted successfully"
        df -h | grep /fsx || true
      else
        log "FSx mount failed (exit $RC). Recent kernel messages:"
        sudo dmesg | tail -n 100 || true
      fi
    fi
  else
    log "FSX_DNS_NAME/FSX_MOUNT_NAME not provided and not found in fstab; skipping mount attempt"
  fi
fi

section "Bundle key logs"
ARCHIVE="$HOME/setup-logs-$(date +%F-%H%M%S).tgz"
set +e
sudo tar -czf "$ARCHIVE" \
  /var/log/user-data.log \
  /var/log/cloud-init.log \
  /var/log/cloud-init-output.log \
  /var/log/apt/history.log \
  /var/log/apt/term.log \
  /var/log/syslog \
  /var/log/kern.log 2>/dev/null
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  log "Wrote $ARCHIVE"
else
  log "Tar archive step encountered an issue (RC=$RC). Some files may be missing; this is non-fatal."
fi

section "Done"
log "Diagnostics complete"
