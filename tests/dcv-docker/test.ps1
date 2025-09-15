#!/usr/bin/env pwsh
param(
  [string]$UbuntuVersion = "24.04"
)

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $here "../..")
$staged = Join-Path $here "setup_dcv.sh"

try {
  Copy-Item (Join-Path $root.Path "terraform-workstations/ubuntu/setup_dcv.sh") $staged -Force

  $img = "dcv-testbed:ubuntu$UbuntuVersion"
  Write-Host "[TEST] Building Docker image: $img (Ubuntu $UbuntuVersion)"
  docker build --build-arg "UBUNTU_VERSION=$UbuntuVersion" -t $img $here

  Write-Host "[TEST] Running setup_dcv.sh inside container (mock systemctl, skip desktop)"
  docker run --rm `
    -e DCV_MOCK_SYSTEMCTL=1 `
    -e DCV_SKIP_DESKTOP=1 `
    $img bash -lc "bash /workspace/setup_dcv.sh && echo '[TEST] Completed. Checking log...' && tail -n +1 /var/log/setup-dcv.log"

  Write-Host "[TEST] SUCCESS (Ubuntu $UbuntuVersion)"
}
finally {
  if (Test-Path $staged) { Remove-Item $staged -Force }
}
