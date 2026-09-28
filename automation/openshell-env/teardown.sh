#!/bin/bash
# Remove the basic OpenShell workshop resources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/functions.sh"

NAMESPACE="${NAMESPACE:-openshell}"
DELETE_CRDS="${1:-}"

echo "============================================"
echo " Teardown Basic OpenShell Workshop Environment"
echo "============================================"
echo ""

step "Delete OpenShell Helm release"
helm uninstall openshell --namespace "$NAMESPACE" 2>/dev/null || warn "Helm release not found"

step "Delete http-echo service and deployment"
oc -n "$NAMESPACE" delete svc http-echo 2>/dev/null || true
oc -n "$NAMESPACE" delete deployment http-echo 2>/dev/null || true

step "Delete Route"
oc -n "$NAMESPACE" delete route openshell-gw 2>/dev/null || true

step "Delete JWT secret"
oc -n "$NAMESPACE" delete secret openshell-jwt-keys 2>/dev/null || true

step "Delete PVC"
oc -n "$NAMESPACE" delete pvc openshell-data-openshell-0 2>/dev/null || true

step "Delete SCC binding"
oc adm policy remove-scc-from-user privileged -z openshell-sandbox -n "$NAMESPACE" 2>/dev/null || true

step "Delete namespace"
oc delete ns "$NAMESPACE" 2>/dev/null || true

if [ "$DELETE_CRDS" = "--crd" ]; then
    step "Delete Agent Sandbox operator"
    crds=""
    csv=""
    csv=$(oc -n openshift-operators get subscription agent-sandbox-operator \
        -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)
    if [ -n "$csv" ]; then
        crds=$(oc -n openshift-operators get csv "$csv" \
            -o jsonpath='{.spec.customresourcedefinitions.owned[*].name}' 2>/dev/null || true)
    fi
    oc -n openshift-operators delete subscription agent-sandbox-operator 2>/dev/null || true
    if [ -n "$csv" ]; then
        oc -n openshift-operators delete csv "$csv" 2>/dev/null || true
    fi
    if [ -n "$crds" ]; then
        # OLM intentionally retains owned CRDs after CSV removal.
        oc delete crd $crds 2>/dev/null || true
    fi
fi

echo ""
info "Teardown complete."
