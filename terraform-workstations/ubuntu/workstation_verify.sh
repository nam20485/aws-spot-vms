#!/bin/bash
set -e -x

# Verify FSx mount
df -h | grep /fsx

# Verify NVIDIA drivers
nvidia-smi
