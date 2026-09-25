SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
HARNESS_DIR := $(AUTOMATION_DIR)/harness/01-basic-openshell
CAPSTONE_DIR := $(AUTOMATION_DIR)/sre-capstone
CAPSTONE_APP ?= module-7-prereqs
CAPSTONE_NS ?= vp-gitops

OPENSHELL_VERSION ?= 0.0.103
OPENSHELL_SANDBOX_IMAGE ?= ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e
RAW_GATEWAY_NAME ?= local-gateway

.PHONY: help prerequisites install-openshell openshell-install openshell-verify \
        openshell-security-test openshell-teardown \
        capstone-bootstrap capstone-status capstone-teardown

help:
	@printf '%s\n' \
	  'Core workshop automation:' \
	  '  make prerequisites       Check required local tools and cluster access' \
	  '  make install-openshell   Install the raw OpenShell evaluation gateway' \
	  '  make openshell-security-test   Run the sandbox control-layer security test' \
	  'Module 7 capstone (Argo-managed prerequisites):' \
	  '  make capstone-bootstrap  One-time apply of the module-7-prereqs Application' \
	  '  make capstone-status     Show the Application and seed Job status' \
	  '  make capstone-teardown   Delete the Application (prunes its components)'

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
	oc apply -f $(CAPSTONE_DIR)/bootstrap/module-7-prereqs.yaml

capstone-status:
	oc get application $(CAPSTONE_APP) -n $(CAPSTONE_NS)
	oc get pods -n openshell -l app=incident-data-seed -o wide 2>/dev/null || true

capstone-teardown:
	oc delete application $(CAPSTONE_APP) -n $(CAPSTONE_NS) --wait=false || true
