#!/usr/bin/env bash
set -euo pipefail

# Optional: pass Ubuntu version as first arg (e.g., 22.04 or 24.04). Default 24.04
UBUNTU_VERSION=${1:-24.04}
IMG="dcv-testbed:ubuntu${UBUNTU_VERSION}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
STAGED="$HERE/setup_dcv.sh"

cleanup() {
  rm -f "$STAGED" || true
}
trap cleanup EXIT

cp -f "$ROOT/terraform-workstations/ubuntu/setup_dcv.sh" "$STAGED"

echo "[TEST] Building Docker image: $IMG (Ubuntu $UBUNTU_VERSION)"
docker build --build-arg "UBUNTU_VERSION=$UBUNTU_VERSION" -t "$IMG" "$HERE"

echo "[TEST] Running setup_dcv.sh inside container (mock systemctl, skip desktop)"
docker run --rm \
  -e DCV_MOCK_SYSTEMCTL=1 \
  -e DCV_SKIP_DESKTOP=1 \
  "$IMG" bash -lc "bash /workspace/setup_dcv.sh && echo '[TEST] Completed. Checking log...' && tail -n +1 /var/log/setup-dcv.log" 

echo "[TEST] SUCCESS (Ubuntu $UBUNTU_VERSION)"
