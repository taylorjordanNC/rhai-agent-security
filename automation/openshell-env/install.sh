#!/bin/bash
# Basic OpenShell workshop environment on OpenShift.
# The unauthenticated gateway is reachable only through a local port-forward.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=functions.sh
source "$SCRIPT_DIR/functions.sh"

NAMESPACE="${NAMESPACE:-openshell}"
RAW_GATEWAY_NAME="${RAW_GATEWAY_NAME:-local-gateway}"
# OpenShell Helm chart version. The chart pins the gateway image by digest
# below, so the gateway build matches the workshop's 0.1.2-rhaiv.0 CLI.
OPENSHELL_VERSION="${OPENSHELL_VERSION:-0.1.2}"
OPENSHELL_SANDBOX_IMAGE="${OPENSHELL_SANDBOX_IMAGE:-ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e}"
# RHAIV gateway image (0.1.2-rhaiv.0), digest-pinned like the SAW track.
OPENSHELL_GATEWAY_REPO="${OPENSHELL_GATEWAY_REPO:-quay.io/opendatahub/odh-openshell-gateway}"
OPENSHELL_GATEWAY_DIGEST="${OPENSHELL_GATEWAY_DIGEST:-sha256:c3b230a32245d0a6c35ed11c17cf590da9ede79dfb0378e3829e16709f63fba3}"
# RHAIV supervisor and sandbox-runtime images (0.1.2-rhaiv.0), digest-pinned
# like the SAW track's BOM. The upstream chart defaults (mutable tags) fail
# closed under the RHAIV gateway's sandbox-policy gRPC validation.
# NOTE: these literals are duplicated from the SAW repo's BOM
# (charts/openshell-saw/values.yaml) — the raw track intentionally aligns to
# the same RHAIV image line.
OPENSHELL_SUPERVISOR_REPO="${OPENSHELL_SUPERVISOR_REPO:-quay.io/opendatahub/odh-openshell-supervisor}"
OPENSHELL_SUPERVISOR_DIGEST="${OPENSHELL_SUPERVISOR_DIGEST:-sha256:0179eb17dcc0098d3fce360035c0be0c26a39949ce09a397c7c259bf728170ff}"
OPENSHELL_SANDBOX_RUNTIME_REPO="${OPENSHELL_SANDBOX_RUNTIME_REPO:-quay.io/opendatahub/odh-openshell-sandbox}"
OPENSHELL_SANDBOX_RUNTIME_DIGEST="${OPENSHELL_SANDBOX_RUNTIME_DIGEST:-sha256:283838f9787bdd876ec8f110a5d5b5c752082a410f75173f0abf2533ae651989}"

if [ "${ENABLE_TLS:-false}" = "true" ]; then
    echo "ENABLE_TLS is not supported by this workshop environment. Use the documented local port-forward." >&2
    exit 1
fi

VERSION_FLAG=""
if [ -n "$OPENSHELL_VERSION" ]; then
    VERSION_FLAG="--version $OPENSHELL_VERSION"
fi

echo "============================================"
echo " Basic OpenShell Workshop Environment"
echo "============================================"
echo ""
echo " Namespace: $NAMESPACE"
echo ""

check_prereqs

# Step 1: Agent Sandbox operator
install_agent_sandbox_operator

# Step 2: Namespace
create_openshell_namespace "$NAMESPACE"

# Step 3: SCC
grant_privileged_scc "$NAMESPACE"

# Step 4: JWT signing secret
step "Step 4/7: Create JWT signing secret"
create_jwt_secret "$NAMESPACE"

# Step 5: Helm install
adopt_cluster_scoped_resources "$NAMESPACE"
step "Step 5/7: Install OpenShell Helm chart"
# shellcheck disable=SC2086
helm upgrade --install openshell oci://ghcr.io/nvidia/openshell/helm-chart \
    --namespace "$NAMESPACE" \
    $VERSION_FLAG \
    --set gateway.image.registry="${OPENSHELL_GATEWAY_REPO%%/*}" \
    --set gateway.image.repository="${OPENSHELL_GATEWAY_REPO#*/}" \
    --set gateway.image.digest="$OPENSHELL_GATEWAY_DIGEST" \
    --set supervisor.image.registry="${OPENSHELL_SUPERVISOR_REPO%%/*}" \
    --set supervisor.image.repository="${OPENSHELL_SUPERVISOR_REPO#*/}" \
    --set supervisor.image.digest="$OPENSHELL_SUPERVISOR_DIGEST" \
    --set sandboxRuntime.image.registry="${OPENSHELL_SANDBOX_RUNTIME_REPO%%/*}" \
    --set sandboxRuntime.image.repository="${OPENSHELL_SANDBOX_RUNTIME_REPO#*/}" \
    --set sandboxRuntime.image.digest="$OPENSHELL_SANDBOX_RUNTIME_DIGEST" \
    --set sandbox.image.repository="${OPENSHELL_SANDBOX_IMAGE%@*}" \
    --set sandbox.image.digest="${OPENSHELL_SANDBOX_IMAGE#*@}" \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set server.auth.allowUnauthenticatedUsers=true \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null

# Step 6: Wait
step "Step 6/7: Wait for gateway rollout"
wait_for_rollout statefulset openshell "$NAMESPACE" 300

# Step 7: In-cluster POST echo service used by the policy exercises
deploy_http_echo "$NAMESPACE"

# Remove the Route created by older revisions of this environment. This gateway is
# unauthenticated and must remain reachable only through port-forwarding.
oc -n "$NAMESPACE" delete route openshell-gw 2>/dev/null || true
echo ""
echo "============================================"
echo " Setup complete!"
echo "============================================"
echo ""
echo " Next steps:"
echo ""
echo "   1. Start a local port-forward in a separate terminal:"
echo "      oc -n $NAMESPACE port-forward svc/openshell 8080:8080"
echo ""
echo "   2. Register the local gateway endpoint:"
echo "      openshell gateway add http://host.containers.internal:8080 --local --name $RAW_GATEWAY_NAME"
echo ""
echo "   3. Select the gateway and check status:"
echo "      openshell gateway select $RAW_GATEWAY_NAME"
echo "      openshell status"
echo ""
echo "   4. Create your first sandbox:"
echo "      openshell sandbox create --name test -- echo 'Hello from OpenShell!'"
echo ""
echo "   5. Connect interactively:"
echo "      openshell sandbox create --name my-sandbox --no-tty -- true"
echo "      openshell sandbox connect my-sandbox"
echo ""
