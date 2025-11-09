output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "control_plane_private_ips" {
  description = "Private IP addresses of control plane nodes"
  value       = aws_instance.control_plane[*].private_ip
}

output "control_plane_public_ips" {
  description = "Public IP addresses of control plane nodes (if in public subnet)"
  value       = aws_instance.control_plane[*].public_ip
}

output "control_plane_instance_ids" {
  description = "Instance IDs of control plane nodes"
  value       = aws_instance.control_plane[*].id
}

output "worker_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = aws_instance.workers[*].private_ip
}

output "worker_instance_ids" {
  description = "Instance IDs of worker nodes"
  value       = aws_instance.workers[*].id
}

output "k8s_api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://${aws_instance.control_plane[0].private_ip}:6443"
}

output "ssh_key_path" {
  description = "Path to the SSH private key (if created)"
  value       = var.create_key_pair ? "${path.module}/${var.cluster_name}-key.pem" : "N/A - Using existing key: ${var.key_name}"
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "ssh_command_bastion" {
  description = "SSH command to connect to bastion host"
  value       = var.create_key_pair ? "ssh -i ${path.module}/${var.cluster_name}-key.pem ubuntu@${aws_instance.bastion.public_ip}" : "ssh -i <your-key>.pem ubuntu@${aws_instance.bastion.public_ip}"
}

output "ssh_command_control_plane" {
  description = "SSH command to connect to control plane via bastion"
  value       = "First SSH to bastion, then: ssh ubuntu@${aws_instance.control_plane[0].private_ip}"
}

output "k8s_api_tunnel_command" {
  description = "Command to create SSH tunnel for Kubernetes API access"
  value       = var.create_key_pair ? "ssh -i ${path.module}/${var.cluster_name}-key.pem -L 6443:${aws_instance.control_plane[0].private_ip}:6443 -N ubuntu@${aws_instance.bastion.public_ip}" : "ssh -i <your-key>.pem -L 6443:${aws_instance.control_plane[0].private_ip}:6443 -N ubuntu@${aws_instance.bastion.public_ip}"
}

output "k8s_api_endpoint_haproxy" {
  description = "Kubernetes API endpoint via HAProxy on bastion"
  value       = "https://${aws_instance.bastion.public_ip}:6443"
}

output "kubeconfig_haproxy_instructions" {
  description = "Instructions to configure kubectl with HAProxy endpoint"
  value       = <<-EOT
    Configure kubectl to use HAProxy endpoint:
    kubectl config set-cluster ${var.cluster_name} \
      --server=https://${aws_instance.bastion.public_ip}:6443 \
      --insecure-skip-tls-verify
    
    Or update your kubeconfig server URL to: https://${aws_instance.bastion.public_ip}:6443
    
    Note: HAProxy on bastion automatically forwards traffic to the control plane.
    No SSH tunnel needed!
  EOT
}

output "kubeconfig_instructions" {
  description = "Instructions to retrieve kubeconfig via bastion"
  value       = <<-EOT
    To retrieve kubeconfig via bastion:
    1. SSH into bastion: ${var.create_key_pair ? "ssh -i ${path.module}/${var.cluster_name}-key.pem ubuntu@${aws_instance.bastion.public_ip}" : "ssh -i <your-key>.pem ubuntu@${aws_instance.bastion.public_ip}"}
    2. From bastion, SSH to control plane: ssh ubuntu@${aws_instance.control_plane[0].private_ip}
    3. Copy kubeconfig: cat /home/ubuntu/.kube/config
    4. Copy to local machine via bastion: scp -i <key>.pem ubuntu@${aws_instance.bastion.public_ip}:/home/ubuntu/.kube/config ~/.kube/config
       (First copy from control plane to bastion, then from bastion to local)
    5. Create SSH tunnel for kubectl: ${var.create_key_pair ? "ssh -i ${path.module}/${var.cluster_name}-key.pem -L 6443:${aws_instance.control_plane[0].private_ip}:6443 -N ubuntu@${aws_instance.bastion.public_ip}" : "ssh -i <your-key>.pem -L 6443:${aws_instance.control_plane[0].private_ip}:6443 -N ubuntu@${aws_instance.bastion.public_ip}"}
    6. Configure kubectl: kubectl config set-cluster my-cluster --server=https://127.0.0.1:6443 --insecure-skip-tls-verify
    7. Test: kubectl get nodes
  EOT
}

output "kubeadm_join_instructions" {
  description = "Instructions to manually join worker nodes (if needed)"
  value       = <<-EOT
    Worker nodes should automatically join the cluster using the kubeadm join command stored in SSM.
    If you need to manually join a worker node:
    1. SSH into the control plane node
    2. Retrieve join command: aws ssm get-parameter --name '/${var.cluster_name}/kubeadm-join-command' --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region}
    3. Or generate new token: kubeadm token create --print-join-command
    4. Run the join command on the worker node
  EOT
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    bastion       = aws_security_group.bastion.id
    control_plane = aws_security_group.k8s_control_plane.id
    workers       = aws_security_group.k8s_workers.id
    efs           = aws_security_group.efs.id
  }
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = "${aws_efs_file_system.main.id}.efs.${var.aws_region}.amazonaws.com"
}

