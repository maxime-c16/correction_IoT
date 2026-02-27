#!/bin/bash

set -e

echo "==> Installing K3s in server mode..."

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl

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

if [ -z "${K3S_TOKEN:-}" ]; then
  echo "ERROR: K3S_TOKEN is required but missing."
  exit 1
fi

echo "==> Setting up K3s server..."
# Install K3s in server mode
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode=644 \
  --node-ip=${SERVER_IP} \
  --bind-address=${SERVER_IP} \
  --advertise-address=${SERVER_IP} \
  --flannel-iface=${NETWORK_IFACE} \
  --token=${K3S_TOKEN}

echo "==> K3s server installed."
echo "==> Checking K3s service status..."
sudo systemctl status k3s --no-pager || true

# Wait for K3s to be ready
echo "==> Waiting for K3s to be ready..."
READY=false
for i in {1..60}; do
  if kubectl get nodes &> /dev/null; then
    echo "==> K3s is ready!"
    READY=true
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 2
done

if [ "${READY}" != "true" ]; then
  echo "ERROR: K3s server did not become ready in time."
  systemctl status k3s --no-pager || true
  journalctl -u k3s --no-pager -n 120 || true
  exit 1
fi

echo "==> K3s server installation complete!"
kubectl get nodes
