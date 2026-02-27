#!/bin/bash
set -e

echo "=== Installing Argo CD ==="
echo ""

echo "Ensuring namespace 'argocd' exists..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Applying official Argo CD manifests..."
echo "Using --server-side and --force-conflicts to handle CRD size limitations (official approach)"
echo ""

# Official Argo CD installation method that handles CRD annotation size limit
# See: https://argo-cd.readthedocs.io/en/stable/
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "✓ Argo CD manifests applied successfully"
echo ""

echo "Step 2: Waiting for Argo CD to be ready (this may take 30-60 seconds)..."
# Wait for the Argo CD server deployment to be ready
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s || {
    echo "⚠️  Timeout waiting for argocd-server"
    echo "Checking current status..."
    kubectl get pods -n argocd
}

echo "✓ Argo CD is ready!"
echo ""

echo "Step 3: Getting Argo CD initial password..."
# The default password is the pod name of argocd-server
echo "To access Argo CD UI:"
echo "  1. Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Open: https://localhost:8080"
echo "  3. Username: admin"
echo "  4. Password: (run the command below)"
echo ""
echo "Get initial password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""
echo ""

echo "Step 4: Checking Argo CD components..."
kubectl get pods -n argocd
echo ""

echo "=== Argo CD installation complete! ==="
echo ""
