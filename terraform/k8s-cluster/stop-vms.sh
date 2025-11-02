#!/bin/bash
set -e
# Stop all instances
for id in $(terraform output -json | jq -r '.control_plane_instance_ids.value[]?, .worker_instance_ids.value[]?, .bastion_instance_id.value?' | grep -v null); do
  echo "Stopping instance: $id"
  aws ec2 stop-instances --instance-ids "$id" --region eu-north-1
done