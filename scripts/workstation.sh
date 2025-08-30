#!/bin/bash

# Simple script to start and stop the GPU cloud workstation.
#
# Usage:
#  ./workstation.sh start
#  ./workstation.sh stop
#
# Before running, set the ASG_NAME variable below to the name of your
# Auto Scaling Group, which is provided in the Terraform output.

# --- Configuration ---
# Replace this with the output from `terraform output autoscaling_group_name`
ASG_NAME="YOUR_AUTOSCALING_GROUP_NAME_HERE"
# -------------------

set -e

if [ "$ASG_NAME" == "YOUR_AUTOSCALING_GROUP_NAME_HERE" ]; then
  echo "ERROR: Please edit this script and set the ASG_NAME variable."
  exit 1
fi

if [ "$1" == "start" ]; then
  echo "Starting workstation... (Desired capacity -> 1)"
  aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG_NAME" --desired-capacity 1
  echo "Request sent. It may take a few minutes for the instance to become available."
elif [ "$1" == "stop" ]; then
  echo "Stopping workstation... (Desired capacity -> 0)"
  aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG_NAME" --desired-capacity 0
  echo "Request sent. The instance will be terminated."
else
  echo "Usage: $0 [start|stop]"
  exit 1
fi
