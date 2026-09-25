SHELL := /usr/bin/env bash

AUTOMATION_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
HARNESS_DIR := $(AUTOMATION_DIR)/harness/01-basic-openshell

OPENSHELL_VERSION ?= 0.0.103
OPENSHELL_SANDBOX_IMAGE ?= ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e
RAW_GATEWAY_NAME ?= local-gateway

.PHONY: help prerequisites install-openshell openshell-install openshell-verify \
        openshell-security-test openshell-teardown

help:
	@printf '%s\n' \
	  'Core workshop automation:' \
	  '  make prerequisites       Check required local tools and cluster access' \
	  '  make install-openshell   Install the raw OpenShell evaluation gateway' \
	  '  make openshell-security-test   Run the sandbox control-layer security test'

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
