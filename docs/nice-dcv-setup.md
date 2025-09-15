## Windows SSH alias tips (scp/ssh)

If an scp/ssh alias didn’t work, check your `~/.ssh/config` for syntax errors. The config file only accepts directives (Host, HostName, User, IdentityFile, etc.). A stray `scp ...` command line inside the file will break parsing.

Example corrected entry:

```
Host ubuntugpuws
  HostName 52.1.238.145
  User ubuntu
  IdentityFile ~/.ssh/aws-spot-vms2.pem
  IdentitiesOnly yes
```

Notes:
- Remove any standalone `scp ...` lines from `~/.ssh/config`.
- Prefer `IdentityFile ~/.ssh/aws-spot-vms2.pem` over a hard-coded `C:\Users\<you>\...` path; `~` works reliably with Windows OpenSSH.
- Keep one Host block per alias; capitalization of `HostName` vs `Hostname` is not significant.

Quick tests in PowerShell:

```
# See the final applied config (helpful for debugging)
ssh -G ubuntugpuws | Select-String -Pattern 'hostname|user|identityfile'

# Connect with the alias
ssh ubuntugpuws

# Copy a file with the alias (no -i flag needed when IdentityFile is set)
scp .\terraform-workstations\ubuntu\setup_dcv.sh ubuntugpuws:/home/ubuntu/setup_dcv.sh
```

If you have multiple OpenSSH installations (e.g., Git for Windows vs Windows built-in), ensure you’re using the Windows built-in tools in `C:\\Windows\\System32\\OpenSSH\\`.

### Windows: create a passphrase-protected key, add to Pageant, and copy pubkey

Use the helper to generate an Ed25519 key with a passphrase, export a .ppk for Pageant, and optionally copy the public key to your Ubuntu instance:

```
pwsh -File .\scripts\ssh-key-setup.ps1 -KeyName aws-spot-vms-ed25519 -ExportPpk -CopyToHost ubuntugpuws -ConnectIdentityFile ~/.ssh/aws-spot-vms2.pem
```

What it does:
- Creates `~/.ssh/aws-spot-vms-ed25519` and `~/.ssh/aws-spot-vms-ed25519.pub` (prompts for passphrase)
- Prints SHA256 fingerprint (a human-friendly key ID)
- If PuTTYgen is available, also creates `~/.ssh/aws-spot-vms-ed25519.ppk`
- Shows a suggested `Host` block and a Pageant startup command you can paste into a shortcut or Startup task
- If `-CopyToHost` is provided, appends the public key to `~/.ssh/authorized_keys` on the remote (using the identity you give via `-ConnectIdentityFile` or your working alias)

Notes:
- You can customize paths to PuTTY tools with `-PuttygenPath` and `-PageantPath`.
- Pageant uses file paths as startup arguments; use the .ppk path it prints.
- Alternatively, enable the built-in Windows `ssh-agent` and run `ssh-add` with your new key.

## NICE DCV on Ubuntu (22.04/24.04) — Install, Configure, and Integrate

This guide explains how this repo installs and configures NICE DCV on Ubuntu GPU workstations built by Terraform. It also documents the sub-script that the post‑boot process calls, verification steps, and how this approach compares with the AWS blog and the official DCV documentation.

### What we install

- Desktop environment: `ubuntu-desktop-minimal` (GNOME)
- Display manager: `gdm3` with Wayland disabled (DCV requires Xorg)
- NICE DCV Server for Ubuntu (latest archive per Ubuntu version and architecture)
- DCV Web Viewer (browser access over 8443) — optional but installed when present
- Virtual sessions support via `nice-xdcv`
- DCV GL for hardware-accelerated OpenGL if NVIDIA is present

### Where it’s wired in

- Post-boot script: `terraform-workstations/ubuntu/workstation_setup.sh`
- Sub-script: `terraform-workstations/ubuntu/setup_dcv.sh`
- At runtime, the post-boot script embeds a copy of the DCV installer under `/opt/aws/workstation/setup_dcv.sh` to ensure availability during cloud-init.

### How it works (high level)

1. Ensures GNOME + GDM3 are installed (minimal desktop to reduce size and avoid Firefox snap)
2. Disables Wayland in `/etc/gdm3/custom.conf` and sets default target to `graphical.target`
3. Downloads the latest DCV archive for Ubuntu 22.04/24.04 and `x86_64` or `aarch64`
4. Installs `nice-dcv-server`, then (when available) `nice-dcv-web-viewer` and `nice-xdcv`
5. Installs `nice-dcv-gl` when `nvidia-smi` is present
6. Enables and starts `dcvserver`
7. Applies minimal defaults to `/etc/dcv/dcv.conf` (keeps secure TLS defaults; sets `web-port=8443` explicitly)

### Usage

- The DCV step runs automatically at the end of `workstation_setup.sh`.
- The embedded script logs to `/var/log/setup-dcv.log`. The wrapper logs to `/var/log/setup-dcv-wrapper.log`.
- Re-run manually if needed:
  - `sudo /opt/aws/workstation/setup_dcv.sh`

### Verify

- Check service:
  - `systemctl status dcvserver`
  - `sudo dcvgladmin list` (if GL installed) — optional
- Confirm port 8443 listening:
  - `sudo ss -tlpn | grep 8443`
- Browser access (from allowed IPs per your security group):
  - `https://<instance-public-or-private-dns>:8443`

### Validate in Docker (testbed)

When developing locally, you can validate the installer script in a container approximating Ubuntu 24.04:

- Build and run the test:
  - `tests/dcv-docker/test.sh` (uses Docker)
- The test uses:
  - `DCV_SKIP_DESKTOP=1` to avoid pulling the full desktop in CI/containers
  - `DCV_MOCK_SYSTEMCTL=1` to avoid systemctl errors in containers
- Review `/var/log/setup-dcv.log` emitted inside the container for step-by-step confirmation.

Note: The container cannot truly start DCV or GDM; this harness validates logic, downloads, and package resolution flows.

Tip: The installer now uses `ubuntu-desktop-minimal` to avoid pulling the Firefox snap; this reduces disk usage and install time on small root volumes.

### Low disk recovery (root volume nearly full)

If you see messages like "no space left on device" or `/` at ~100%:

- Clear apt caches and old kernels:
  - `sudo apt-get clean`
  - `sudo apt-get autoremove -y --purge`
- Check large directories:
  - `sudo du -h -d1 /var | sort -h`
  - `sudo du -h -d1 / | sort -h`
- If a snap install wedged due to low space:
  - `sudo systemctl restart snapd`
  - `snap changes` then `sudo snap abort <id>` (if needed), free space, then `sudo snap retry <id>`
- Re-run the DCV installer after freeing space:
  - `sudo /opt/aws/workstation/setup_dcv.sh`

### Security notes

- EC2 instances do not require a DCV license.
- This keeps DCV TLS settings at defaults; DCV generates a self‑signed certificate on first start. Replace with a real certificate and update `dcv.conf` for production.
- Ensure your security groups only allow DCV from trusted sources. Optionally enable SSM Session Manager and disable public ingress.

### Comparison: AWS Blog vs Official Docs

Sources
- AWS Blog (MHTML in this repo): Managing Ubuntu Desktops with GPUs Using NICE DCV
- DCV Admin Guide:
  - Setting up: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up.html
  - Linux install: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux.html
  - Linux prerequisites: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-prereq.html

Alignment
- Both recommend GNOME + GDM on Ubuntu and disabling Wayland.
- Both install DCV Server from the official `download.amazondcv.com` archives.
- Both suggest Web Viewer for browser access and `nice-xdcv` for virtual sessions.
- GPU systems: installing DCV GL is recommended to enable HW OpenGL in virtual sessions.

Key Differences / Divergences
- Version targeting: This repo uses the “latest” archive links keyed by Ubuntu version (22.04/24.04) and architecture to avoid pin drift but stay current. The blog may pin explicit versions for reproducibility. If you need strict pinning, replace the URL with a concrete version from the DCV download page and checksum it.
- Embedded availability: We embed the DCV installer script under `/opt/aws/workstation/` during cloud-init so it’s always present, even if the repo isn’t available locally at first boot.
- Minimal `dcv.conf` edits: We keep defaults secure and only set `web-port=8443`, leaving TLS to DCV’s auto‑generated cert. The blog may provide more opinionated `dcv.conf` examples; feel free to extend `setup_dcv.sh` to template cert paths, user policies, USB redirection, etc.
- GL conditional: We install `nice-dcv-gl` only if `nvidia-smi` exists to keep non‑GPU instances lean; some guidance installs it unconditionally.

### Files

- `terraform-workstations/ubuntu/setup_dcv.sh` — main installer (idempotent)
- `terraform-workstations/ubuntu/workstation_setup.sh` — calls the embedded installer at the end
- `docs/nice-dcv-setup.md` — this document

### Troubleshooting

- Blank screen on connect: verify GDM3 is running, Wayland disabled, and NVIDIA driver loaded (`nvidia-smi`). A reboot after driver install often helps.
- Web client unreachable: verify SG allows TCP 8443 to this instance; confirm `systemctl status dcvserver` and `ss -tlpn`.
- Virtual session OpenGL not accelerating: ensure `nice-dcv-gl` installed and NVIDIA GRID driver is correctly installed. You can test with `dcvgltest` if present.

### Next steps (optional improvements)

- Pin exact DCV package versions and verify checksums for deterministic builds.
- Provide an Ansible/Puppet module or Terraform provisioner toggle to enable/disable DCV.
- Automate certificate provisioning (ACM Private CA, Let’s Encrypt) and configure `dcv.conf` accordingly.

### Snapshot/Checkpoint the EC2 instance (AMI)

After you verify the workstation, create an AMI to checkpoint the exact state:

- Terraform now outputs `workstation_instance_id`
- Use the script:
  - `scripts/create-ec2-snapshot.ps1 -InstanceId <id> -Name my-dcv-checkpoint -Region <region>`
- The script creates and tags an AMI without reboot, waits until the AMI is available, and prints the AMI ID.
