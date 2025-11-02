#!/bin/bash
REGION="eu-north-1"
cd terraform/k8s-cluster

echo "Starting all cluster instances..."
for id in $(terraform output -json | jq -r '.control_plane_instance_ids.value[]?, .worker_instance_ids.value[]?, .bastion_instance_id.value?' | grep -v null); do
  echo "Starting: $id"
  aws ec2 start-instances --instance-ids "$id" --region "$REGION" --output json | jq -r '.StartingInstances[0].CurrentState.Name'
done

echo "Waiting for instances to be running..."
aws ec2 wait instance-running --instance-ids $(terraform output -json | jq -r '.control_plane_instance_ids.value[]?, .worker_instance_ids.value[]?, .bastion_instance_id.value?' | grep -v null | tr '\n' ' ') --region "$REGION"

echo "All instances are running!"