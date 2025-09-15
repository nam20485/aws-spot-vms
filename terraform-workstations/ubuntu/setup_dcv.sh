#!/usr/bin/env bash
#
# setup_dcv.sh - Install and configure NICE DCV on Ubuntu 22.04/24.04
#
# Idempotent installer that:
# - Installs GNOME + GDM3 (required by DCV for console sessions)
# - Disables Wayland for GDM3 (DCV requires Xorg)
# - Downloads and installs the latest NICE DCV server .deb packages for Ubuntu
# - Installs Web Viewer and Virtual Sessions support (nice-xdcv)
# - Installs DCV GL package if NVIDIA drivers are present
# - Enables and starts the dcvserver systemd service
#
# References:
# - Amazon DCV Admin Guide (Linux install): https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux.html
# - Prereqs (Wayland disable, desktop env): https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html
# - EC2 doesn’t require a DCV license

set -euo pipefail
shopt -s nullglob

# Test harness knobs (useful inside Docker):
# - DCV_SKIP_DESKTOP=1   -> skip installing ubuntu-desktop and gdm3; still configures /etc/gdm3/custom.conf
# - DCV_MOCK_SYSTEMCTL=1 -> replace systemctl invocations with no-op logging

sc() {
  if [[ "${DCV_MOCK_SYSTEMCTL:-0}" == "1" ]]; then
    echo "[DCV] (mock) systemctl $*" || true
    return 0
  else
    systemctl "$@"
  fi
}

LOG="/var/log/setup-dcv.log"
exec > >(tee -a "$LOG") 2>&1

echo "[DCV] Starting NICE DCV setup..."

if command -v dcvserver >/dev/null 2>&1; then
  echo "[DCV] Detected existing dcvserver: $(dcvserver --version || true). Skipping install."
  # Still ensure service enabled and Wayland disabled
else
  echo "[DCV] Updating apt cache..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y

  DESKTOP_FLAVOR="${DCV_DESKTOP:-gnome-minimal}"
  if [[ "${DCV_SKIP_DESKTOP:-0}" == "1" || "$DESKTOP_FLAVOR" == "none" ]]; then
    echo "[DCV] Skipping desktop environment install (DCV_SKIP_DESKTOP=1 or DCV_DESKTOP=none)"
  else
    echo "[DCV] Installing desktop: $DESKTOP_FLAVOR (this can take several minutes)"
    export DEBIAN_FRONTEND=noninteractive
    case "$DESKTOP_FLAVOR" in
      cinnamon)
        # Avoid snaps by not using ubuntu-desktop; install Xorg + LightDM + Cinnamon
        echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections || true
        apt-get install -y xorg lightdm cinnamon slick-greeter || true
        ;;
      mate)
        # MATE core to avoid extra apps/snaps; you can add more later
        echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections || true
        apt-get install -y xorg lightdm mate-desktop-environment-core mate-terminal || true
        ;;
      gnome)
        # Full GNOME (may pull Firefox snap via ubuntu-desktop)
        apt-get install -y ubuntu-desktop gdm3 || true
        ;;
      gnome-minimal|*)
        # Default minimal GNOME to keep lean; no Firefox snap
        apt-get install -y ubuntu-desktop-minimal gdm3 || true
        ;;
    esac
  fi

  # Disable Wayland for GDM3
  # Only relevant if GDM3 is present
  if dpkg -s gdm3 >/dev/null 2>&1; then
    echo "[DCV] Disabling Wayland in /etc/gdm3/custom.conf..."
    mkdir -p /etc/gdm3
    CUSTOM_CONF="/etc/gdm3/custom.conf"
    if [[ ! -f "$CUSTOM_CONF" ]]; then
      cat > "$CUSTOM_CONF" <<'CFG'
[daemon]
WaylandEnable=false
CFG
    else
      # Ensure [daemon] section exists and WaylandEnable=false
      if ! grep -q '^\[daemon\]' "$CUSTOM_CONF"; then
        sed -i '1i [daemon]' "$CUSTOM_CONF"
      fi
      if grep -q '^WaylandEnable=' "$CUSTOM_CONF"; then
        sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' "$CUSTOM_CONF"
      else
        awk '1; /^\[daemon\]$/ && !x {print "WaylandEnable=false"; x=1}' "$CUSTOM_CONF" >"$CUSTOM_CONF.tmp" && mv "$CUSTOM_CONF.tmp" "$CUSTOM_CONF"
      fi
    fi
  fi

  if [[ "${DCV_SKIP_DESKTOP:-0}" == "1" || "$DESKTOP_FLAVOR" == "none" ]]; then
    echo "[DCV] Skipping set-default graphical.target due to no desktop install"
  else
    echo "[DCV] Setting default target to graphical.target (start X on boot)"
    sc set-default graphical.target || true
  fi

  # Determine Ubuntu version and arch to pick the right DCV archive
  . /etc/os-release
  VER_ID="${VERSION_ID:-}"
  if [[ -z "${VER_ID}" ]]; then
    echo "[DCV] Could not determine Ubuntu VERSION_ID from /etc/os-release" >&2
    exit 1
  fi

  ARCH_TAG="x86_64"
  case "$(uname -m)" in
    x86_64) ARCH_TAG="x86_64" ;;
    aarch64|arm64) ARCH_TAG="aarch64" ;;
    *) echo "[DCV] Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac

  case "$VER_ID" in
    22.04) UBUNTU_TAG="ubuntu2204" ;;
    24.04) UBUNTU_TAG="ubuntu2404" ;;
    *) echo "[DCV] Unsupported/untested Ubuntu version $VER_ID. Supported: 22.04, 24.04" >&2; exit 1 ;;
  esac

  WORKDIR="/var/tmp/dcv-install"
  mkdir -p "$WORKDIR"
  cd "$WORKDIR"

  URL="https://d1uj6qtbmh3dt5.cloudfront.net/nice-dcv-${UBUNTU_TAG}-${ARCH_TAG}.tgz"
  echo "[DCV] Downloading DCV archive: $URL"
  if ! curl -fSL "$URL" -o dcv.tgz; then
    echo "[DCV] Failed to fetch $URL. You can consult latest links at https://download.amazondcv.com/latest.html" >&2
    exit 1
  fi
  echo "[DCV] Extracting archive..."
  rm -rf dcv && mkdir dcv && tar -xzf dcv.tgz -C dcv --strip-components=1
  cd dcv

  echo "[DCV] Installing DCV server and components (.deb packages)"
  # Server package(s)
  SERVER_PKGS=( ./nice-dcv-server*.deb )
  if (( ${#SERVER_PKGS[@]} == 0 )); then
    echo "[DCV] Could not find nice-dcv-server debs in archive directory" >&2
    exit 1
  fi
  dpkg -i "${SERVER_PKGS[@]}" || true
  apt-get update -y && apt-get -f install -y

  # Web viewer for browser-based client (optional)
  WEB_PKGS=( ./nice-dcv-web-viewer*.deb )
  if (( ${#WEB_PKGS[@]} > 0 )); then
    dpkg -i "${WEB_PKGS[@]}" || true
    apt-get -f install -y || true
  fi

  # Virtual sessions support (optional)
  XDCV_PKGS=( ./nice-xdcv*.deb )
  if (( ${#XDCV_PKGS[@]} > 0 )); then
    dpkg -i "${XDCV_PKGS[@]}" || true
    apt-get -f install -y || true
  fi

  # Install GL package only on NVIDIA systems
  if command -v nvidia-smi >/dev/null 2>&1; then
  GL_PKGS=( ./nice-dcv-gl*.deb )
    if (( ${#GL_PKGS[@]} > 0 )); then
      echo "[DCV] NVIDIA GPU detected. Installing DCV GL package for hardware-accelerated OpenGL in virtual sessions."
      dpkg -i "${GL_PKGS[@]}" || true
      apt-get -f install -y || true
      # Optional gltest utility
  GLTEST_PKGS=( ./nice-dcv-gltest*.deb )
      if (( ${#GLTEST_PKGS[@]} > 0 )); then
        dpkg -i "${GLTEST_PKGS[@]}" || true
        apt-get -f install -y || true
      fi
    fi
  else
    echo "[DCV] NVIDIA GPU not detected. Skipping DCV GL package."
  fi

  echo "[DCV] Enabling and starting dcvserver service"
  sc enable dcvserver || true
  sc restart dcvserver || sc start dcvserver || true
fi

# Minimal, safe dcv.conf hardening/adjustments
DCV_CONF="/etc/dcv/dcv.conf"
if [[ -f "$DCV_CONF" ]]; then
  echo "[DCV] Applying minimal connectivity and security defaults in $DCV_CONF"
  # Ensure sections exist and avoid duplications
  if ! grep -q '^\[connectivity\]' "$DCV_CONF"; then echo '[connectivity]' >> "$DCV_CONF"; fi
  if ! grep -q '^\[security\]' "$DCV_CONF"; then echo '[security]' >> "$DCV_CONF"; fi
  # Keep default 8443; make sure web client is allowed (handled by web-viewer package)
  if grep -q '^#*web-port=' "$DCV_CONF"; then
    sed -i 's/^#*web-port=.*/web-port=8443/' "$DCV_CONF"
  else
    awk '1; /^\[connectivity\]$/ && !x {print "web-port=8443"; x=1}' "$DCV_CONF" >"$DCV_CONF.tmp" && mv "$DCV_CONF.tmp" "$DCV_CONF"
  fi
  # Leave TLS settings at secure defaults; DCV auto-generates a self-signed cert on first start
fi

echo "[DCV] Restarting services to apply changes (display manager and dcvserver)"
if [[ "${DCV_SKIP_DESKTOP:-0}" == "1" || "$DESKTOP_FLAVOR" == "none" ]]; then
  echo "[DCV] Skipping display manager restart due to no desktop install"
else
  if dpkg -s gdm3 >/dev/null 2>&1; then
    sc restart gdm3 || true
  elif dpkg -s lightdm >/dev/null 2>&1; then
    sc restart lightdm || true
  fi
fi
sc restart dcvserver || true

echo "[DCV] NICE DCV setup completed. A reboot is recommended if NVIDIA drivers or desktop packages were newly installed."
