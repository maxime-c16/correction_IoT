# Part 3: K3d and Argo CD - Implementation Guide

## Overview

This Part demonstrates **GitOps** - a modern DevOps practice where:
- Your Kubernetes manifests live in Git (source of truth)
- **Argo CD** watches the repository and automatically syncs changes to the cluster
- No manual `kubectl apply` commands needed
- Infrastructure is declarative and version-controlled

## Architecture

```
GitHub Repository (macauchy-c16/inception_of_things)
    │
    ├── p3/confs/          ← Kubernetes manifests (watched by Argo CD)
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── kustomization.yaml
    │   └── argocd-app.yaml
    │
    └── (on push/commit)
            ↓
    K3d Cluster (Docker-based)
    ├── argocd namespace    ← Argo CD system
    │   ├── argocd-server
    │   ├── argocd-application-controller (watches GitHub)
    │   ├── argocd-repo-server
    │   └── other components
    │
    └── dev namespace       ← Application deployment target
        ├── Deployment: macauchy-app
        ├── Service: macauchy-app (LoadBalancer)
        └── Pod: macauchy-app-xxxxx
```

## Components Installed

### 1. K3d Cluster
- **Type:** Docker-based lightweight Kubernetes
- **Nodes:** 1 control plane + 2 workers (in Docker containers)
- **Network:** K3d creates a Docker network bridge

### 2. Argo CD
- **Role:** GitOps controller
- **Components:**
  - `argocd-server`: Web UI and REST API
  - `argocd-application-controller`: Watches Git repos and syncs
  - `argocd-repo-server`: Clones and parses Git repositories
  - `argocd-notifications-controller`: Sends sync notifications
  - `argocd-redis`: Caching layer
  - `argocd-dex-server`: Authentication system

### 3. Application
- **Image:** `wil42/playground` (from Docker Hub)
- **Versions:** v1 and v2 available
- **Port:** 8888
- **Deployment:** Managed by Argo CD from GitHub

## Setup Instructions

### Prerequisites
- Docker installed and running
- kubectl installed
- K3d not yet installed (we install it in the setup)

### Step 1: Create the K3d Cluster

```bash
bash p3/scripts/setup_k3d.sh
```

What this does:
- Installs K3d (if not already installed)
- Creates a cluster named "macauchy"
- Creates 1 server + 2 agents
- Creates `argocd` and `dev` namespaces
- Waits for cluster to be ready

### Step 2: Install Argo CD

```bash
bash p3/scripts/setup_argocd.sh
```

What this does:
- Applies Argo CD manifests from the official repository
- Sets up all Argo CD components
- Waits for components to be ready
- Outputs the admin password

### Step 3: Access Argo CD Web UI (Optional)

```bash
# Terminal 1: Port forward to Argo CD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Terminal 2: Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo ""

# Browser: https://localhost:8080
# Login: admin / <password from above>
```

You'll see the Argo CD dashboard showing:
- Application: `macauchy-app`
- Sync Status: Synced
- Health Status: Healthy
- Source: GitHub repository
- Destination: dev namespace

## Kubernetes Manifests

### deployment.yaml
Defines how your application runs:
- **Image:** `wil42/playground:v1` (initially) or `v2` (after update)
- **Replicas:** 1
- **Port:** 8888
- **Health Checks:** Liveness and Readiness probes

### service.yaml
Exposes the application:
- **Type:** LoadBalancer (accessible from host in K3d)
- **Port:** 8888
- **Selector:** Matches pods with `app: macauchy-app` label

### kustomization.yaml
Template configuration for Argo CD:
- Lists the resources (deployment + service)
- Allows Kustomize to manage the manifests

### argocd-app.yaml
Argo CD Application CRD:
- **Repository:** `https://github.com/maxime-c16/inception_of_things.git`
- **Path:** `p3/confs/` ← Directory watched by Argo CD
- **Destination:** `dev` namespace
- **Sync Policy:** Automated with self-heal and prune

## Testing GitOps: Version Update Flow

### Version 1 (Initial)
```bash
# Check current version
curl http://<service-ip>:8888/
# Response: {"status":"ok", "message": "v1"}
```

### Upgrade to Version 2

**Step 1: Update the manifest**
```yaml
# In p3/confs/deployment.yaml
image: wil42/playground:v2  # Changed from v1
```

**Step 2: Commit and push to GitHub**
```bash
git add p3/confs/deployment.yaml
git commit -m "chore(p3): update application to v2"
git push origin main
```

**Step 3: Watch Argo CD auto-deploy**
- Argo CD detects the change (within 3 minutes, or trigger refresh)
- Pulls the new manifest
- Updates the deployment spec
- Terminates old pod
- Creates new pod with v2 image
- Service automatically routes to new pod

**Step 4: Verify new version**
```bash
curl http://<service-ip>:8888/
# Response: {"status":"ok", "message": "v2"}
```

## Key Files

| File | Purpose |
|------|---------|
| `p3/scripts/setup_k3d.sh` | Creates K3d cluster and namespaces |
| `p3/scripts/setup_argocd.sh` | Installs Argo CD from official manifests |
| `p3/confs/deployment.yaml` | Kubernetes Deployment manifest |
| `p3/confs/service.yaml` | Kubernetes Service manifest |
| `p3/confs/kustomization.yaml` | Kustomize configuration |
| `p3/confs/argocd-app.yaml` | Argo CD Application CRD |

## Useful Commands

```bash
# Check cluster nodes
kubectl get nodes

# View all namespaces
kubectl get ns

# Check Argo CD components
kubectl get pods -n argocd

# Check application deployment
kubectl get pods -n dev
kubectl get deployments -n dev
kubectl get svc -n dev

# View Argo CD Application status
kubectl get application -n argocd
kubectl describe application macauchy-app -n argocd

# View sync history
kubectl get application macauchy-app -n argocd -o jsonpath='{.status.operationState}'

# Manually trigger refresh (if needed)
kubectl patch application macauchy-app -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# View logs
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-repo-server

# Access application
# Get the service IP (K3d LoadBalancer IP)
kubectl get svc -n dev macauchy-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test endpoint
curl http://<service-ip>:8888/
```

## Cleanup

To remove the cluster:
```bash
k3d cluster delete macauchy
```

To remove only applications but keep cluster:
```bash
kubectl delete -f p3/confs/
```

## Troubleshooting

### Issue: Application not deploying
**Check:**
1. Argo CD controller logs: `kubectl logs -n argocd deployment/argocd-application-controller`
2. Repo server logs: `kubectl logs -n argocd deployment/argocd-repo-server`
3. Application status: `kubectl describe application macauchy-app -n argocd`
4. GitHub repository URL is correct and accessible

### Issue: Version not updating
**Solutions:**
1. Trigger manual refresh: Add `argocd.argoproj.io/refresh` annotation
2. Check if commit is pushed: `git log --oneline`
3. Verify manifest path: `git show HEAD:p3/confs/deployment.yaml`
4. Check Argo CD revision: `kubectl get application macauchy-app -n argocd -o jsonpath='{.status.sync.revision}'`

### Issue: Can't access application
**Check:**
1. Pod is running: `kubectl get pods -n dev`
2. Service exists: `kubectl get svc -n dev`
3. Service has external IP: `kubectl get svc -n dev -o wide`
4. Pod logs: `kubectl logs -n dev <pod-name>`

## Learning Outcomes

After completing Part 3, you understand:
- ✅ **K3d:** Docker-based lightweight Kubernetes
- ✅ **Argo CD:** GitOps controller
- ✅ **Namespaces:** Logical isolation in Kubernetes
- ✅ **Custom Resources:** Argo CD Application CRD
- ✅ **Git-Driven Deployments:** Automatic sync from GitHub
- ✅ **Continuous Deployment:** Without manual kubectl commands
- ✅ **Infrastructure as Code:** Declarative configuration management

## Next Steps (Bonus)

The **Bonus part** involves integrating **Gitlab** with this setup:
- Local Gitlab instance
- Integration with Argo CD
- Gitlab webhook triggers
- Advanced GitOps workflows

Bonus is only evaluated if Parts 1-3 are complete and working perfectly.

---

**Part 3 Status:** ✅ **COMPLETE**

All requirements met:
- [x] K3d cluster created with 2 namespaces
- [x] Argo CD installed and configured
- [x] Application deployed from GitHub
- [x] v1 and v2 versions available
- [x] Automatic sync demonstrated
- [x] Version update tested
