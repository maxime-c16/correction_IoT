#!/bin/bash
# =============================================================================
# K3S SERVER SETUP SCRIPT
# =============================================================================
# This script sets up a K3s server on the host and deploys the applications.
#
# Prerequisites:
# 1. SERVER_IP environment variable set to the server's IP address (192.168.56.110)
# 2. K3S_TOKEN environment variable set to a secure token for cluster authentication
# 3. This script is run on the server node (not a worker)
#
# This script:
# - Installs K3s in server mode
# - Waits for K3s to be ready
# - Deploys the applications defined in confs/apps.yaml and confs/ingress.yaml
# =============================================================================
set -e

echo "=== Installing K3s Server (Single Node) ==="
SERVER_IP="${SERVER_IP:-192.168.56.110}"

echo "==> Detecting network interface..."
NETWORK_IFACE=$(ip -o -4 addr show | awk -v target="${SERVER_IP}" '$4 ~ ("^" target "/") {print $2; exit}')
if [ -z "$NETWORK_IFACE" ]; then
  NETWORK_IFACE=$(ip -o -4 route show to default | awk 'NR==1 {print $5}')
fi
if [ -z "$NETWORK_IFACE" ]; then
  echo "ERROR: Could not determine network interface for SERVER_IP=${SERVER_IP}."
  ip a
  exit 1
fi
echo "==> Using network interface: ${NETWORK_IFACE}"
echo "==> Server IP: ${SERVER_IP}"

# Install k3s in SERVER mode (idempotent)
if command -v k3s >/dev/null 2>&1; then
    echo "k3s already installed; skipping installation"
else
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=${SERVER_IP} --advertise-address=${SERVER_IP} --flannel-iface=${NETWORK_IFACE}" sh -
fi

echo "=== K3s Server installed, waiting for readiness ==="

# Wait for K3s to be ready
kubectl_path="/usr/local/bin/kubectl"
max_retries=30
retry=0

while ! KUBECONFIG=/etc/rancher/k3s/k3s.yaml $kubectl_path get node &>/dev/null && [ $retry -lt $max_retries ]; do
    echo "Waiting for K3s API to be ready... ($retry/$max_retries)"
    sleep 5
    retry=$((retry + 1))
done

if [ $retry -ge $max_retries ]; then
    echo "ERROR: K3s failed to start within timeout"
    exit 1
fi

echo "=== K3s API ready, configuring kubectl for vagrant user ==="

# Make kubeconfig readable and copy to vagrant home
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
sudo mkdir -p /home/vagrant/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config
sudo chmod 600 /home/vagrant/.kube/config

# Add to bashrc for persistence
echo 'export KUBECONFIG=/home/vagrant/.kube/config' >> /home/vagrant/.bashrc
echo "alias k='kubectl'" >> /home/vagrant/.bashrc

echo "=== kubectl configured for vagrant user ==="

# Set KUBECONFIG for this script
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for traefik to be ready
$kubectl_path wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=300s 2>/dev/null || true

# Deploy P2 applications
echo "=== Deploying P2 applications from confs/ ==="
$kubectl_path apply -f /home/vagrant/confs/apps.yaml
$kubectl_path apply -f /home/vagrant/confs/ingress.yaml

echo "=== P2 K3s Server setup complete ==="
