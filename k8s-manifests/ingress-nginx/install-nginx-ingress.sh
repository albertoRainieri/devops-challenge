#!/bin/bash
# Install Nginx Ingress Controller with NodePort
# This script installs nginx ingress controller configured to use NodePort service type

set -e

echo "Installing Nginx Ingress Controller..."

# Add Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --kube-insecure-skip-tls-verify \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassResource.default=true \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --set controller.resources.limits.cpu=200m \
  --set controller.resources.limits.memory=256Mi

echo "Waiting for nginx ingress controller to be ready..."
kubectl --insecure-skip-tls-verify wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Nginx Ingress Controller installed successfully!"
echo ""
echo "Service details:"
kubectl get svc -n ingress-nginx ingress-nginx-controller
echo ""
echo "To configure HAProxy to route traffic, run on bastion:"
echo "  /opt/configure-haproxy.sh <cluster_name> <aws_region>"
echo ""
echo "Or manually copy and run configure-haproxy.sh script"

