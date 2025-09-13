# NVIDIA GPU Driver Quick Reference (Ubuntu 24.04 LTS)

Instance-side (bash) — install, verify, and pin:

```bash
# Prep: kernel headers + DKMS
sudo apt-get update
sudo apt-get install -y linux-headers-$(uname -r) dkms

# Install server driver + utils (noble)
sudo apt-get install -y nvidia-driver-570-server nvidia-utils-570-server

# Reboot to load modules
sudo reboot
```

After reboot, verify:

```bash
nvidia-smi
lsmod | grep nvidia
```

Pin working versions to avoid surprise upgrades:

```bash
sudo apt-mark hold nvidia-driver-570-server nvidia-utils-570-server
apt policy nvidia-driver-570-server nvidia-utils-570-server
```

Unpin if needed:

```bash
sudo apt-mark unhold nvidia-driver-570-server nvidia-utils-570-server
```

Host-side helpers (PowerShell) — run from your Windows machine:

```powershell
# Show candidate versions on the instance
.\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action show

# Hold / unhold remotely
.\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action hold
.\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action unhold
```

Notes:
- Keep linux-headers installed so DKMS can rebuild across kernel updates.
- After kernel updates, re-check `nvidia-smi` and `lsmod | grep nvidia`.
- If `nvidia-smi` fails post-update, ensure headers match `uname -r`, then reinstall the driver if needed.
