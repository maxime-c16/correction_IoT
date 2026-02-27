.PHONY: setup cluster argocd deploy verify upgrade clean status help

CLUSTER_NAME := macauchy
ARGOCD_NS := argocd
DEV_NS := dev
APP_NAME := macauchy-app

help:
	@echo "Part 3 - K3d + Argo CD Makefile"
	@echo ""
	@echo "=== Setup & Deployment ==="
	@echo "  make setup       - Full setup: cluster + Argo CD + application"
	@echo "  make cluster     - Create K3d cluster (idempotent)"
	@echo "  make argocd      - Install Argo CD (idempotent)"
	@echo "  make deploy      - Deploy application via Argo CD (idempotent, registers app if needed)"
	@echo "  make verify      - Verify v1 is running"
	@echo "  make upgrade     - Upgrade to v2 via GitOps and verify"
	@echo "  make downgrade   - Downgrade to v1 via GitOps and verify"
	@echo ""
	@echo "=== Management ==="
	@echo "  make status      - Show cluster status"
	@echo "  make logs        - Stream logs from latest pod"
	@echo "  make scale       - Scale deployment (usage: make scale N=3)"
	@echo "  make rollback    - Rollback to previous version"
	@echo "  make history     - Show deployment rollout history"
	@echo "  make cleanup-rs  - Remove old ReplicaSets (keep only latest)"
	@echo "  make port-forward - Port-forward app to localhost:8888"
	@echo ""
	@echo "=== Cleanup ==="
	@echo "  make clean       - Remove everything"
	@echo "  make help        - Show this message"

# Cluster setup - idempotent
cluster:
	@if k3d cluster list | grep -q $(CLUSTER_NAME); then \
		echo "[✓] K3d cluster '$(CLUSTER_NAME)' already exists"; \
	else \
		echo "[→] Creating K3d cluster..."; \
		bash scripts/setup_k3d.sh; \
	fi

# Argo CD setup - idempotent
argocd: cluster
	@if kubectl get deployment -n $(ARGOCD_NS) argocd-server 2>/dev/null | grep -q argocd-server; then \
		echo "[✓] Argo CD already installed"; \
	else \
		echo "[→] Installing Argo CD..."; \
		bash scripts/setup_argocd.sh; \
	fi
	@echo "[→] Waiting for Argo CD to be ready..."; \
	kubectl rollout status deployment/argocd-server -n $(ARGOCD_NS) --timeout=2m || true

# Application deployment - idempotent (via Argo CD)
deploy: argocd
	@echo "[→] Deploying application via Argo CD..."
	@if kubectl get application $(APP_NAME) -n $(ARGOCD_NS) > /dev/null 2>&1; then \
		echo "[✓] Application already exists, skipping creation"; \
	else \
		echo "[→] Creating Argo CD Application..."; \
		kubectl apply -f confs/argocd-app.yaml; \
	fi
	@echo "[→] Waiting for Argo CD to sync..."
	@sleep 5
	@kubectl wait --for=condition=Synced application/$(APP_NAME) -n $(ARGOCD_NS) --timeout=2m || true
	@echo "[→] Waiting for deployment to be ready..."
	@kubectl rollout status deployment/macauchy-app -n $(DEV_NS) --timeout=2m || true
	@echo "[→] Verifying deployment exists..."
	@kubectl get deployment macauchy-app -n $(DEV_NS) > /dev/null 2>&1 && echo "[✓] Deployment ready" || exit 1

# Verify v1 is running
verify: deploy
	@echo "[→] Verifying v1 is running..."
	@for i in 1 2 3; do \
		kubectl port-forward svc/$(APP_NAME) -n $(DEV_NS) 8888:8888 > /dev/null 2>&1 & \
		PF_PID=$$!; \
		sleep 2; \
		RESPONSE=$$(curl -s http://localhost:8888/ 2>/dev/null || echo "error"); \
		kill $$PF_PID 2>/dev/null || true; \
		if echo "$$RESPONSE" | grep -q 'v1'; then \
			echo "[✓] v1 is running: $$RESPONSE"; \
			exit 0; \
		fi; \
		echo "[→] Attempt $$i failed, retrying..."; \
		sleep 2; \
	done; \
	echo "[✗] v1 not responding properly: $$RESPONSE"; \
	exit 1

# Upgrade to v2 (via GitOps)
upgrade: deploy
	@echo "[→] Checking current version..."
	@CURRENT_VERSION=$$(grep "image: wil42/playground" confs/deployment.yaml | grep -o 'v[0-9]' || echo "unknown"); \
	if [ "$$CURRENT_VERSION" = "v2" ]; then \
		echo "[✓] Already running v2"; \
		exit 0; \
	fi
	@echo "[→] Upgrading to v2..."
	@sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' confs/deployment.yaml
	@echo "[→] Committing and pushing to Git..."
	@git add confs/deployment.yaml
	@git commit -m "upgrade: deploy v2 image" || echo "(Already committed)"
	@git push origin master
	@echo "[→] Waiting for Argo CD to sync..."
	@sleep 10
	@kubectl rollout status deployment/macauchy-app -n $(DEV_NS) --timeout=2m || true
	@echo "[→] Verifying v2 is running..."
	@for i in 1 2 3; do \
		kubectl port-forward svc/$(APP_NAME) -n $(DEV_NS) 8888:8888 > /dev/null 2>&1 & \
		PF_PID=$$!; \
		sleep 2; \
		RESPONSE=$$(curl -s http://localhost:8888/ 2>/dev/null || echo "error"); \
		kill $$PF_PID 2>/dev/null || true; \
		if echo "$$RESPONSE" | grep -q 'v2'; then \
			echo "[✓] v2 is running: $$RESPONSE"; \
			exit 0; \
		fi; \
		echo "[→] Attempt $$i failed, retrying..."; \
		sleep 2; \
	done; \
	echo "[✗] v2 not responding properly: $$RESPONSE"; \
	exit 1

# Downgrade back to v1 (for testing rollback, via GitOps)
downgrade: deploy
	@echo "[→] Checking current version..."
	@CURRENT_VERSION=$$(grep "image: wil42/playground" confs/deployment.yaml | grep -o 'v[0-9]' || echo "unknown"); \
	if [ "$$CURRENT_VERSION" = "v1" ]; then \
		echo "[✓] Already running v1"; \
		exit 0; \
	fi
	@echo "[→] Downgrading back to v1..."
	@sed -i 's/wil42\/playground:v2/wil42\/playground:v1/g' confs/deployment.yaml
	@echo "[→] Committing and pushing to Git..."
	@git add confs/deployment.yaml
	@git commit -m "downgrade: deploy v1 image" || echo "(Already committed)"
	@git push origin master
	@echo "[→] Waiting for Argo CD to sync..."
	@sleep 10
	@kubectl rollout status deployment/macauchy-app -n $(DEV_NS) --timeout=2m || true
	@echo "[→] Verifying v1 is running..."
	@for i in 1 2 3; do \
		kubectl port-forward svc/$(APP_NAME) -n $(DEV_NS) 8888:8888 > /dev/null 2>&1 & \
		PF_PID=$$!; \
		sleep 2; \
		RESPONSE=$$(curl -s http://localhost:8888/ 2>/dev/null || echo "error"); \
		kill $$PF_PID 2>/dev/null || true; \
		if echo "$$RESPONSE" | grep -q 'v1'; then \
			echo "[✓] v1 is running: $$RESPONSE"; \
			exit 0; \
		fi; \
		echo "[→] Attempt $$i failed, retrying..."; \
		sleep 2; \
	done; \
	echo "[✗] v1 not responding properly: $$RESPONSE"; \
	exit 1

# Show status
status:
	@echo "=== K3d Cluster Status ==="
	@k3d cluster list | grep $(CLUSTER_NAME) || echo "Cluster not found"
	@echo ""
	@echo "=== Argo CD Status ==="
	@kubectl get deployment -n $(ARGOCD_NS) 2>/dev/null | tail -1 || echo "Argo CD not installed"
	@echo ""
	@echo "=== Application Status ==="
	@kubectl get deployment,pods,svc -n $(DEV_NS) 2>/dev/null || echo "No application deployed"
	@echo ""
	@echo "=== To access Argo CD UI ==="
	@echo "  kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:443"
	@echo "  https://localhost:8080"
	@echo "  Username: admin"
	@echo "  Password: $$(kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)"

# Full setup
setup: cluster argocd deploy verify
	@echo ""
	@echo "=== Setup Complete ==="
	@echo "Part 3 is ready! Use 'make upgrade' to test the v1→v2 GitOps workflow"

# View logs from latest pod
logs:
	@echo "[→] Streaming logs from latest pod..."
	@kubectl logs -n $(DEV_NS) -f deployment/$(APP_NAME) --tail=50

# Scale deployment via GitOps (update Git, Argo CD syncs automatically)
# Usage: make scale N=3
scale:
	@if [ -z "$(N)" ]; then \
		echo "Usage: make scale N=<number>"; \
		echo "Example: make scale N=3"; \
		exit 1; \
	fi
	@echo "[→] Scaling $(APP_NAME) to $(N) replicas via GitOps..."
	@cd .. && sed -i 's/replicas: [0-9]\+/replicas: $(N)/' p3/confs/deployment.yaml
	@echo "[→] Updated deployment.yaml with replicas: $(N)"
	@cd .. && git add p3/confs/deployment.yaml
	@cd .. && git commit -m "Scale deployment to $(N) replicas"
	@cd .. && git push origin master
	@echo "[✓] Pushed to Git. Argo CD will sync in ~3 minutes (or use 'make status' to check)"
	@echo "[→] Waiting for Argo CD sync..."
	@sleep 10
	@echo "[→] Current pod count:"
	@kubectl get pods -n $(DEV_NS) | grep $(APP_NAME) | wc -l
	@echo "[✓] Use 'make status' to see full status"

# Show deployment rollout history
history:
	@echo "[→] Deployment rollout history:"
	@kubectl rollout history deployment/$(APP_NAME) -n $(DEV_NS)

# Rollback to previous version
rollback:
	@echo "[→] Rolling back to previous version..."
	@kubectl rollout undo deployment/$(APP_NAME) -n $(DEV_NS)
	@sleep 5
	@echo "[✓] Rollback complete. Waiting for rollout..."
	@kubectl rollout status deployment/$(APP_NAME) -n $(DEV_NS) --timeout=2m
	@echo "[→] Checking new version..."
	@kubectl port-forward svc/$(APP_NAME) -n $(DEV_NS) 8888:8888 > /dev/null 2>&1 &
	@PF_PID=$$!; sleep 2; \
	RESPONSE=$$(curl -s http://localhost:8888/ 2>/dev/null || echo "error"); \
	kill $$PF_PID 2>/dev/null || true; \
	echo "[✓] Current version: $$RESPONSE"

# Remove old ReplicaSets (keep only 1 revision history)
cleanup-rs:
	@echo "[→] Cleaning up old ReplicaSets..."
	@kubectl patch deployment $(APP_NAME) -n $(DEV_NS) \
		-p '{"spec":{"revisionHistoryLimit":1}}'
	@echo "[✓] Revision history limit set to 1"
	@sleep 2
	@echo "[✓] Old ReplicaSets will be garbage collected. Current status:"
	@kubectl get rs -n $(DEV_NS) -o wide

# Port-forward to app
port-forward:
	@echo "[→] Port-forwarding app to localhost:8888..."
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward svc/$(APP_NAME) -n $(DEV_NS) 8888:8888

# Cleanup
clean:
	@echo "[→] Cleaning up..."
	@if k3d cluster list | grep -q $(CLUSTER_NAME); then \
		echo "[→] Deleting K3d cluster '$(CLUSTER_NAME)'..."; \
		k3d cluster delete $(CLUSTER_NAME); \
	fi
	@git -C . checkout confs/deployment.yaml 2>/dev/null || echo "(Git checkout skipped)"
	@echo "[✓] Cleanup complete"
