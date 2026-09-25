#!/bin/bash
# Verify the basic OpenShell workshop environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/common/functions.sh"

NAMESPACE="${NAMESPACE:-openshell}"
OPENSHELL_VERSION="${OPENSHELL_VERSION:-0.0.103}"
RAW_GATEWAY_NAME="${RAW_GATEWAY_NAME:-local-gateway}"
export OPENSHELL_VERSION RAW_GATEWAY_NAME
PASSED=0
FAILED=0

check() {
    local name="$1"
    shift
    if "$@" &>/dev/null; then
        info "PASS: $name"
        PASSED=$((PASSED + 1))
    else
        error "FAIL: $name"
        FAILED=$((FAILED + 1))
    fi
}

echo "============================================"
echo " Verify Basic OpenShell Workshop Environment"
echo "============================================"
echo ""

check "Agent Sandbox CRD exists" oc get crd sandboxes.agents.x-k8s.io
check "Namespace exists" oc get ns "$NAMESPACE"
check "Gateway pod running" oc -n "$NAMESPACE" wait --for=condition=Ready pod -l app.kubernetes.io/name=openshell --timeout=10s
check "Gateway service exists" oc -n "$NAMESPACE" get svc openshell

if command -v openshell &>/dev/null; then
    check "openshell ${OPENSHELL_VERSION} CLI" bash -c 'test "$(openshell --version | awk '\''{print $NF}'\'')" = "$OPENSHELL_VERSION"'
    check "raw workshop gateway connectivity" openshell --gateway "$RAW_GATEWAY_NAME" status
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
