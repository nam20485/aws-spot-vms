# Testbed for validating setup_dcv.sh on Ubuntu 24.04 (closest to current Ubuntu AMIs)
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        sudo \
        systemd-sysv \
        wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -ms /bin/bash tester \
    && echo 'tester ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod +x /usr/sbin/policy-rc.d

WORKDIR /workspace

# Bring in the installer script (staged by test.sh)
COPY setup_dcv.sh /workspace/setup_dcv.sh
RUN chmod +x /workspace/setup_dcv.sh

# Default command prints help
CMD ["bash", "-lc", "echo 'Run test.sh to validate setup_dcv.sh' && ls -la /workspace"]
