#!/bin/bash
set -e

# Wait for control plane to be ready and SSM parameters to be available
echo "Waiting for control plane to initialize..."
sleep 90

# Install AWS CLI and prerequisites
apt-get update -y
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release awscli jq

# Disable swap (required for kubeadm)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# Install containerd
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install Kubernetes components
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Retry logic to get kubeadm join command from SSM
export AWS_DEFAULT_REGION="${aws_region}"
MAX_RETRIES=30
RETRY_COUNT=0
JOIN_COMMAND=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  JOIN_COMMAND=$(aws ssm get-parameter --name "/${cluster_name}/kubeadm-join-command" --region "${aws_region}" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  CONTROL_PLANE_IP=$(aws ssm get-parameter --name "/${cluster_name}/control-plane-ip" --region "${aws_region}" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$JOIN_COMMAND" ] && [ ! -z "$CONTROL_PLANE_IP" ]; then
    echo "Successfully retrieved kubeadm join command"
    break
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Waiting for control plane to store join command..."
  sleep 10
done

if [ -z "$JOIN_COMMAND" ] || [ -z "$CONTROL_PLANE_IP" ]; then
  echo "ERROR: Could not retrieve join command or control plane IP after $MAX_RETRIES attempts"
  echo "Please manually join this node to the cluster"
  exit 1
fi

# Verify control plane is accessible
echo "Verifying connection to control plane at https://$CONTROL_PLANE_IP:6443..."
for i in {1..10}; do
  if curl -k -s https://$CONTROL_PLANE_IP:6443 > /dev/null 2>&1; then
    echo "Control plane is accessible"
    break
  fi
  echo "Attempt $i/10: Waiting for control plane to be accessible..."
  sleep 10
done

# Join the cluster
echo "Joining Kubernetes cluster..."
eval $JOIN_COMMAND

echo "Kubernetes worker node initialized successfully!"
