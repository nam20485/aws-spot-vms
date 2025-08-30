#!/bin/bash

# Simple script to start and stop the GPU cloud workstation.
#
# Usage:
#  ./workstation.sh start
#  ./workstation.sh stop
#
# Before running, set the ASG_NAME variable below to the name of your
# Auto Scaling Group, which is provided in the Terraform output.

Param(
  [Parameter(Mandatory=$true)]
  [string]$action
)

# --- Configuration ---
# Replace this with the output from `terraform output autoscaling_group_name`
$ASG_NAME="YOUR_AUTOSCALING_GROUP_NAME_HERE"
# -------------------

if ($ASG_NAME == "YOUR_AUTOSCALING_GROUP_NAME_HERE") {
  Write-Content "Please edit this script and set the ASG_NAME variable."
  exit 1
}

$START = "start"
$STOP = "stop"

if ($action == ToLower($START)) {
  Write-Output "Starting workstation... (Desired capacity -> 1)"
  aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG_NAME" --desired-capacity 1
  Write-Output "Request sent. It may take a few minutes for the instance to become available."
  Write-Output "Starting workstation... (Desired capacity -> 1)"
  aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG_NAME" --desired-capacity 1
  Write-Output "Request sent. It may take a few minutes for the instance to become available."
}
elif ($action == ToLower($STOP)){
  Write-Output "Stopping workstation... (Desired capacity -> 0)"
  aws autoscaling set-desired-capacity --auto-scaling-group-name "$ASG_NAME" --desired-capacity 0
  Write-Output "Request sent. The instance will be terminated."
}
else {
  Write-Output "Invalid action: $action"
  Write-Output "Usage: $0 [start|stop]"
  exit 1
}
