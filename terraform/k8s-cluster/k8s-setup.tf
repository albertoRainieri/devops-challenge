# User data script for control plane node using kubeadm
locals {
  control_plane_user_data = <<-EOF
#!/bin/bash
set -e
# Wait for internet connectivity (timeout after 5 minutes = 300 seconds)
timeout=300
interval=5
elapsed=0
while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "ERROR: No internet connectivity after $timeout seconds. Exiting."
    exit 1
  fi
  echo "Waiting for internet connectivity..."
  sleep $interval
  elapsed=$((elapsed + interval))
done
echo "Internet connectivity detected."

# Update system
apt-get update -y
apt-get upgrade -y

# Install prerequisites
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release awscli jq

# Disable swap (required for kubeadm)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<K8SCONF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
K8SCONF

modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters
cat <<SYSCONF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCONF

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

# Initialize kubeadm
# 169.254.169.254 special link-local ip reserved for AWS Instance Metadata Service
export PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

kubeadm init \
  --apiserver-advertise-address=$PRIVATE_IP \
  --apiserver-cert-extra-sans=$PRIVATE_IP \
  --pod-network-cidr=192.168.0.0/16 \
  --control-plane-endpoint=$PRIVATE_IP \
  --ignore-preflight-errors=Swap

# Configure kubectl for ubuntu user
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# Store kubeadm join command in SSM
JOIN_COMMAND=$(kubeadm token create --print-join-command 2>/dev/null || echo "")
JOIN_TOKEN=$(kubeadm token list -o jsonpath='{.items[0].token}' 2>/dev/null || echo "")
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //' || echo "")

export AWS_DEFAULT_REGION="${var.aws_region}"

if [ ! -z "$JOIN_COMMAND" ]; then
  aws ssm put-parameter \
    --name "/${var.cluster_name}/kubeadm-join-command" \
    --value "$JOIN_COMMAND" \
    --type SecureString \
    --overwrite \
    --region "${var.aws_region}" || true
fi

# Store individual components for workers
aws ssm put-parameter \
  --name "/${var.cluster_name}/control-plane-ip" \
  --value "$PRIVATE_IP" \
  --type String \
  --overwrite \
  --region "${var.aws_region}" || true

if [ ! -z "$JOIN_TOKEN" ]; then
  aws ssm put-parameter \
    --name "/${var.cluster_name}/kubeadm-token" \
    --value "$JOIN_TOKEN" \
    --type SecureString \
    --overwrite \
    --region "${var.aws_region}" || true
fi

if [ ! -z "$CA_HASH" ]; then
  aws ssm put-parameter \
    --name "/${var.cluster_name}/ca-cert-hash" \
    --value "sha256:$CA_HASH" \
    --type String \
    --overwrite \
    --region "${var.aws_region}" || true
fi

# Install Calico CNI
kubectl --kubeconfig=/home/ubuntu/.kube/config apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
# Wait for node to be ready
sleep 30
kubectl --kubeconfig=/home/ubuntu/.kube/config get nodes

echo "Kubernetes control plane node initialized successfully!"
EOF

  worker_user_data = templatefile("${path.module}/worker-userdata.sh", {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    k8s_version  = var.k8s_version
  })

  bastion_user_data = <<-EOF
#!/bin/bash
set -e

# Wait for internet connectivity
timeout=300
interval=5
elapsed=0
while ! ping -c 1 8.8.8.8 >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "ERROR: No internet connectivity after $timeout seconds. Exiting."
    exit 1
  fi
  echo "Waiting for internet connectivity..."
  sleep $interval
  elapsed=$((elapsed + interval))
done
echo "Internet connectivity detected."

# Update system
apt-get update -y
apt-get upgrade -y

# Install HAProxy
apt-get install -y haproxy awscli


# Wait for IAM instance profile credentials to be available
echo "Waiting for IAM role credentials to be available..."
MAX_IAM_RETRIES=30
IAM_RETRY=0
while [ $IAM_RETRY -lt $MAX_IAM_RETRIES ]; do
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ > /dev/null 2>&1; then
    echo "IAM credentials available"
    break
  fi
  IAM_RETRY=$((IAM_RETRY + 1))
  echo "Waiting for IAM credentials... ($IAM_RETRY/$MAX_IAM_RETRIES)"
  sleep 2
done

# Configure AWS CLI to use instance metadata
mkdir -p /home/ubuntu/.aws
cat > /home/ubuntu/.aws/config <<AWS_CONFIG
[default]
region = ${var.aws_region}
credential_source = Ec2InstanceMetadata
AWS_CONFIG

# Wait for control plane IP to be available in SSM
echo "Waiting for control plane IP from SSM..."
export AWS_DEFAULT_REGION="${var.aws_region}"
MAX_RETRIES=60
RETRY_COUNT=0
CONTROL_PLANE_IP=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  CONTROL_PLANE_IP=$(aws ssm get-parameter --name "/${var.cluster_name}/control-plane-ip" --region "${var.aws_region}" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$CONTROL_PLANE_IP" ] && [ "$CONTROL_PLANE_IP" != "placeholder" ]; then
    echo "Control plane IP retrieved: $CONTROL_PLANE_IP"
    break
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Waiting for control plane IP..."
  sleep 10
done

if [ -z "$CONTROL_PLANE_IP" ] || [ "$CONTROL_PLANE_IP" == "placeholder" ]; then
  echo "ERROR: Could not retrieve control plane IP after $MAX_RETRIES attempts"
  echo "HAProxy will need to be configured manually"
  exit 1
fi

# Create initial basic HAProxy configuration (only Kubernetes API)
# Full configuration with ingress will be managed separately via configure-haproxy.sh script
cat > /etc/haproxy/haproxy.cfg <<HAPROXY_CFG
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

listen k8s-api-6443
    bind *:6443
    mode tcp
    balance roundrobin
    server k8s_control_plane $CONTROL_PLANE_IP:6443 check
HAPROXY_CFG

# Enable and start HAProxy
systemctl enable haproxy
systemctl restart haproxy

# Verify HAProxy is running
systemctl status haproxy --no-pager

echo "HAProxy installed and started with basic Kubernetes API configuration!"
echo "Kubernetes API is now accessible at: https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):6443"
echo ""
echo "To configure HTTP/HTTPS ingress routing, run:"
echo "  /opt/configure-haproxy.sh ${var.cluster_name} ${var.aws_region}"
EOF
}

