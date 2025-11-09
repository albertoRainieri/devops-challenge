#!/bin/bash
# Install AWS EFS CSI Driver for Kubernetes
# This script installs the EFS CSI driver using Helm

set -e

echo "Installing AWS EFS CSI Driver..."

# Add AWS EKS Helm repository
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Install EFS CSI driver
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --kube-insecure-skip-tls-verify \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=efs-csi-controller-sa

echo "Waiting for EFS CSI driver to be ready..."
kubectl --insecure-skip-tls-verify wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app=efs-csi-controller \
  --timeout=300s

echo "EFS CSI Driver installed successfully!"

# Verify installation
echo ""
echo "Checking EFS CSI driver pods:"
kubectl --insecure-skip-tls-verify get pods -n kube-system | grep efs-csi


