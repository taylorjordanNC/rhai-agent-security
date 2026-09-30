SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
HARNESS_DIR := $(AUTOMATION_DIR)/openshell-env
ARGOCD_DIR := $(AUTOMATION_DIR)/argocd
FLEET_DIR := $(AUTOMATION_DIR)/fleet
CAPSTONE_APP ?= module-7-prereqs
GITOPS_NS ?= openshift-gitops

OPENSHELL_VERSION ?= 0.0.103
OPENSHELL_SANDBOX_IMAGE ?= ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e
RAW_GATEWAY_NAME ?= local-gateway

.PHONY: help prerequisites install-openshell openshell-install openshell-verify \
        openshell-security-test openshell-teardown \
        capstone-bootstrap capstone-status capstone-teardown \
        fleet-install fleet-status

help:
	@printf '%s\n' \
	  'Core workshop automation:' \
	  '  make prerequisites       Check required local tools and cluster access' \
	  '  make install-openshell   Install the raw OpenShell evaluation gateway' \
	  '  make openshell-security-test   Run the sandbox control-layer security test' \
	  'Workshop GitOps (capstone child):' \
	  '  make capstone-bootstrap  One-time apply of the capstone child Application' \
	  '  make capstone-status     Show the capstone child and seed Job status' \
	  '  make capstone-teardown   Delete the capstone child Application' \
	  'Fleet SAW deployment (RHDP orders):' \
	  '  make fleet-install       Loop the SAW install over clusters (fleet/clusters.csv)' \
	  '  make fleet-status        Poll SAW + workshop resources per cluster'

prerequisites:
	bash $(AUTOMATION_DIR)/bootstrap/prerequisites.sh

install-openshell: openshell-install

openshell-install:
	OPENSHELL_VERSION=$(OPENSHELL_VERSION) OPENSHELL_SANDBOX_IMAGE=$(OPENSHELL_SANDBOX_IMAGE) bash $(HARNESS_DIR)/install.sh

openshell-verify:
	OPENSHELL_VERSION=$(OPENSHELL_VERSION) RAW_GATEWAY_NAME=$(RAW_GATEWAY_NAME) \
	  bash $(HARNESS_DIR)/verify.sh

openshell-security-test:
	bash $(HARNESS_DIR)/test-sandbox-security.sh $(SANDBOX_NAME)

openshell-teardown:
	bash $(HARNESS_DIR)/teardown.sh

capstone-bootstrap:
	oc apply -f $(ARGOCD_DIR)/templates/10-capstone.yaml

capstone-status:
	oc get application $(CAPSTONE_APP) -n $(GITOPS_NS) 2>/dev/null || true
	oc get pods -n openshell -l app=incident-data-seed -o wide 2>/dev/null || true

capstone-teardown:
	oc delete application $(CAPSTONE_APP) -n $(GITOPS_NS) --wait=false || true

fleet-install:
	bash $(FLEET_DIR)/fleet-install.sh $(FLEET_ARGS)

fleet-status:
	bash $(FLEET_DIR)/fleet-status.sh $(FLEET_ARGS)
