# Scripts quick reference

- nvidia-driver.ps1
  - Manage GPU driver holds remotely via SSH.
  - Examples:
    ```powershell
    .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action show
    .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action hold
    .\scripts\nvidia-driver.ps1 -Host ubuntugpuws -Action unhold
    ```

- fsx-mount.ps1
  - Check and mount FSx for Lustre on the instance; can persist to /etc/fstab.
  - Examples:
    ```powershell
    .\scripts\fsx-mount.ps1 -Host ubuntugpuws -Action status
    .\scripts\fsx-mount.ps1 -Host ubuntugpuws -Action mount -FsxDnsName <dns> -FsxMountName <mount> -Persist
    ```
