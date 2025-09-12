# This file declares the desired state of our workstation on Ubuntu 24.04.

# 1. Install NVIDIA drivers using the official, pre-validated module.
class { 'nvidia':
  driver_version => 'latest',
  require        => Class['apt::update'],
}

# 2. Install and configure the FSx for Lustre client.
class { 'apt::update': }

# Add the AWS repository for the FSx Lustre client
apt::source { 'fsx-lustre-repo':
  location => 'https://fsx-lustre-client-repo.s3.amazonaws.com/ubuntu',
  # UPDATED: Changed from jammy to noble for Ubuntu 24.04
  release  => 'noble',
  repos    => 'main',
  key      => {
    id     => '264342F355932130302251F41F59A5C02D157643',
    source => 'https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-main-repo-public-key.asc',
  },
  include  => {
    'src' => false,
  },
  require  => Class['apt::update'],
}

# Install the Lustre client package for the current running kernel
package { "lustre-client-modules":
  name      => "lustre-client-modules-$${facts[\"kernelrelease\"]}",
  ensure    => installed,
  require   => Apt::Source["fsx-lustre-repo"],
}

# Create the mount point directory
file { '/fsx':
  ensure => 'directory',
}

# Mount the FSx filesystem and ensure it's added to fstab for persistence
mount { '/fsx':
  ensure  => 'mounted',
  device  => '${fsx_dns_name}@tcp:/${fsx_mount_name}',
  fstype  => 'lustre',
  options => 'noatime,flock,_netdev',
  require => [
    Package['lustre-client-modules'],
    File['/fsx'],
  ],
}
```

### How to Deploy the Upgrade

Because you are changing the fundamental base operating system (the AMI), you must replace the instance.

1.  Replace the contents of your existing files with the updated versions above.
2.  Run the same replacement command you used before:
    ```bash
    terraform apply -replace="aws_instance.workstation"


