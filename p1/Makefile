SHELL := /bin/bash

VAGRANT ?= vagrant
SERVER ?= mcauchyS
WORKER ?= mcauchySW

.DEFAULT_GOAL := help

.PHONY: help validate up up-sequential up-server up-worker provision provision-sequential reconcile recreate destroy halt status test test-vms test-k3s

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Deployment strategies:"
	@echo "  up                 Idempotent: bring up both VMs (parallel/default Vagrant behavior)"
	@echo "  up-sequential      Idempotent: bring up server first, then worker"
	@echo "  up-server          Bring up only server VM"
	@echo "  up-worker          Bring up only worker VM"
	@echo "  provision          Re-run provisioning on all existing VMs"
	@echo "  provision-sequential Re-provision server then worker"
	@echo "  reconcile          validate + up-sequential + provision-sequential"
	@echo "  recreate           destroy + up-sequential"
	@echo ""
	@echo "Operations:"
	@echo "  validate           Validate Vagrantfile"
	@echo "  status             Show VM status"
	@echo "  halt               Stop both VMs"
	@echo "  destroy            Destroy both VMs"
	@echo "  ssh                SSH into server VM"
	@echo ""
	@echo "Testing:"
	@echo "  test               Run full checks (VMs + k3s services + 2-node cluster)"
	@echo "  test-vms           Check both VMs are running"
	@echo "  test-k3s           Check k3s server/agent services and cluster node count"

validate:
	@$(VAGRANT) validate

up: validate
	@$(VAGRANT) up --provision

up-sequential: validate
	@$(VAGRANT) up $(SERVER) --provision
	@$(VAGRANT) up $(WORKER) --provision

up-server: validate
	@$(VAGRANT) up $(SERVER) --provision

up-worker: validate
	@$(VAGRANT) up $(WORKER) --provision

provision:
	@$(VAGRANT) provision

provision-sequential:
	@$(VAGRANT) provision $(SERVER)
	@$(VAGRANT) provision $(WORKER)

reconcile: validate up-sequential provision-sequential
	@echo "Environment reconciled."

recreate:
	@$(VAGRANT) destroy -f
	@$(MAKE) up-sequential

destroy:
	@$(VAGRANT) destroy -f

halt:
	@$(VAGRANT) halt

status:
	@$(VAGRANT) status

ssh:
	@$(VAGRANT) ssh $(SERVER)

test: test-vms test-k3s
	@echo "All tests passed."

test-vms:
	@$(VAGRANT) status $(SERVER) | grep -q "$(SERVER).*running"
	@$(VAGRANT) status $(WORKER) | grep -q "$(WORKER).*running"
	@echo "VM state OK: $(SERVER), $(WORKER) are running."

test-k3s:
	@$(VAGRANT) ssh $(SERVER) -c "sudo systemctl is-active --quiet k3s"
	@bash -lc 'for i in {1..36}; do \
	  if $(VAGRANT) ssh $(WORKER) -c "sudo systemctl is-active --quiet k3s-agent" >/dev/null 2>&1; then \
	    exit 0; \
	  fi; \
	  echo "Waiting for k3s-agent to become active ($$i/36)..."; \
	  sleep 5; \
	done; \
	echo "k3s-agent did not become active in time"; \
	exit 1'
	@bash -lc 'count=$$($(VAGRANT) ssh $(SERVER) -c "sudo k3s kubectl get nodes --no-headers 2>/dev/null | wc -l" | tr -d "\r" | tr -d " "); \
	if [[ -z "$$count" || "$$count" -lt 2 ]]; then \
	  echo "Expected at least 2 nodes in cluster, got: $${count:-0}"; \
	  exit 1; \
	fi'
	@echo "k3s checks OK: services active and cluster has at least 2 nodes."
