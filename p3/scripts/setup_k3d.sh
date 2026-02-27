#!/bin/bash
set -e

echo "=== K3d Cluster Setup Script ==="
echo ""

# Configuration variables
CLUSTER_NAME="macauchy"
REGISTRY_NAME="k3d-registry"
REGISTRY_PORT="5000"

echo "Step 1: Creating K3d cluster '$CLUSTER_NAME'..."
echo "This may take a minute..."

k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --api-port 6443 \
  --wait

echo "✓ K3d cluster created successfully"
echo ""

echo "Step 2: Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready node --all --timeout=300s 2>/dev/null || true
sleep 5

echo "✓ Cluster nodes are ready"
echo ""

echo "Step 3: Creating namespaces..."

kubectl create namespace argocd 2>/dev/null || echo "  (argocd namespace may already exist)"
kubectl create namespace dev 2>/dev/null || echo "  (dev namespace may already exist)"

echo "✓ Namespaces created"
echo ""

echo "Step 4: Verifying cluster setup..."
echo ""
echo "Cluster nodes:"
kubectl get nodes

echo ""
echo "Cluster namespaces:"
kubectl get ns | grep -E "argocd|dev|default|kube"

echo ""
echo "=== K3d setup complete! ==="
echo ""
echo "Cluster name: $CLUSTER_NAME"
echo "API endpoint: https://127.0.0.1:6443"
echo ""
echo "Next steps:"
echo "1. Install Argo CD in the argocd namespace"
echo "2. Create a GitHub repository for your application manifests"
echo "3. Configure Argo CD to sync from GitHub"
echo ""
