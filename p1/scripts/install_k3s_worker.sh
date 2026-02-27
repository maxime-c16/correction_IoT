#!/bin/bash

set -e

echo "==> Installing K3s in agent mode..."

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl

echo "==> Detecting network interface..."
NETWORK_IFACE=""
if [ -n "${WORKER_IP:-}" ]; then
  NETWORK_IFACE=$(ip -o -4 addr show | awk -v target="${WORKER_IP}" '$4 ~ ("^" target "/") {print $2; exit}')
fi
if [ -z "$NETWORK_IFACE" ]; then
  NETWORK_IFACE=$(ip -o -4 route show to default | awk 'NR==1 {print $5}')
fi
if [ -z "$NETWORK_IFACE" ]; then
  echo "ERROR: Could not determine network interface for WORKER_IP=${WORKER_IP:-unknown}."
  ip a
  exit 1
fi
echo "==> Using network interface: ${NETWORK_IFACE}"

# Resolve token (preferred: env provided by Vagrant host, fallback: shared file)
TOKEN_VALUE=$(printf '%s' "${K3S_TOKEN:-}" | tr -d '\r\n[:space:]')

if [ -z "$TOKEN_VALUE" ]; then
  echo "==> K3S_TOKEN env is empty, trying /vagrant_shared/token..."
  TIMEOUT=300
  while true; do
    if [ -f "/vagrant_shared/token" ]; then
      TOKEN_VALUE=$(tr -d '\r\n[:space:]' < /vagrant_shared/token)
      if [ -n "$TOKEN_VALUE" ]; then
        break
      fi
      echo "Token file exists but is empty/invalid. Waiting for a valid token..."
    fi

    sleep 5
    TIMEOUT=$((TIMEOUT - 5))
    if [ "$TIMEOUT" -le 0 ]; then
      echo "ERROR: Valid token not found (env + shared file)."
      exit 1
    fi
    echo "Waiting for token... (${TIMEOUT}s remaining)"
  done
fi

printf '%s\n' "$TOKEN_VALUE" > /tmp/k3s_token
sudo mkdir -p /etc/rancher
sudo mv /tmp/k3s_token /etc/rancher/k3s-token
sudo chmod 600 /etc/rancher/k3s-token

# Wait for server to be ready
echo "==> Waiting for K3s server to be available..."
SERVER_TIMEOUT=300
until curl -ks https://${SERVER_IP}:6443 &> /dev/null; do
  echo "Waiting for server..."
  sleep 5
  SERVER_TIMEOUT=$((SERVER_TIMEOUT - 5))
  if [ "$SERVER_TIMEOUT" -le 0 ]; then
    echo "ERROR: K3s API https://${SERVER_IP}:6443 is unreachable."
    exit 1
  fi
done

# Install K3s in agent mode using token file
export K3S_TOKEN_FILE=/etc/rancher/k3s-token
export K3S_TOKEN="${TOKEN_VALUE}"
export K3S_URL=https://${SERVER_IP}:6443
curl -sfL https://get.k3s.io | sh -s - agent \
  --node-ip=${WORKER_IP:-192.168.56.111} \
  --flannel-iface=${NETWORK_IFACE}

echo "==> K3s agent installation complete!"
