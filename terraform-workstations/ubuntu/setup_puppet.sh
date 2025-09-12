#!/bin/bash
set -e -x

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Puppet Bootstrap for Ubuntu 24.04 ---"

# Install prerequisites
apt-get update -y
apt-get install -y wget

# UPDATED: Download and install the official Puppet release package for Ubuntu 24.04 (Noble)
wget https://apt.puppet.com/puppet7-release-noble.deb
dpkg -i puppet7-release-noble.deb
apt-get update -y

# Install the puppet-agent
echo "Installing Puppet Agent..."
apt-get install -y puppet-agent

# Add Puppet to the path for this script
export PATH=$PATH:/opt/puppetlabs/bin

# Install the pre-validated NVIDIA module from the Puppet Forge
echo "Installing puppet-nvidia module..."
puppet module install nvidia-nvidia --version 5.0.0

# Install the Puppet module for managing APT (a dependency for the Lustre part)
puppet module install puppetlabs-apt --version 9.2.0

# Create the main Puppet manifest file on the instance from the Terraform template
echo "Creating Puppet manifest..."
cat << 'EOF' > /etc/puppetlabs/code/environments/production/manifests/site.pp
${puppet_manifest}
EOF

# Apply the manifest to configure the machine!
echo "Applying Puppet manifest..."
puppet apply /etc/puppetlabs/code/environments/production/manifests/site.pp --debug

echo "--- Puppet Configuration Complete ---"

