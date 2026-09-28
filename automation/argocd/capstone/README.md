# Module 7 capstone prerequisites — Argo-managed cluster setup

The components module 7 (SRE Copilot Capstone) needs up **before workshop
participants proceed** live here as Argo CD–managed manifests. This directory
is the GitOps source for the `module-7-prereqs` child Application, managed by
the workshop root app-of-apps (`../root.yaml`), which points at
`automation/argocd/capstone` on `taylorjordanNC/rhai-agent-security@main`
in the cluster's `openshift-gitops` instance.

| Component | Sync wave | Namespace | Purpose |
|---|---|---|---|
| openshell namespace | 0 | — | the workspace namespace the seed Job (and the SAW fleet) run in; carries the `mlflow-workspace=true` label |
| demo shop | 0 | `demo` | the instrumented `demo/shop` app the fleet investigates |
| MLflow instance | 1 | `redhat-ods-applications` | `MLflow` CR — the traces specialist queries it through the proxy |
| telemetry proxy | 2 | `openshell-agents` | plain-HTTP nginx in front of Thanos (8080) and MLflow (8081); the fleet's per-agent ceilings name this proxy |
| incident console | 3 | `openshell-agents` + RBAC in `demo` | browser console for the human-confirmed outage loop |
| incident data seed | 4 + PostSync hook | `openshell` | plants the `INC-4127` agent-session story traces the traces agent searches |

## Prerequisites of this Application

1. **SAW deployment up** (module 3, optional; the fleet script or the
   participant's module 3 run): `openshell-agents` namespace, the governance
   interceptor with the capstone fleet egress ceilings, Keycloak, and the
   fleet sandboxes (`metrics`, `traces`, `analyst`) provisioned by the
   `saw-bom` chart via `apply_bom.py` on the workspace VM. Those stay in the
   SAW fork's GitOps. The child holds in Argo retry until SAW is healthy.
2. **RHOAI MLflow operator installed** (cluster baseline) — the operator
   reconciles the `MLflow` CR in wave 1.
3. **`mlflow-workspace=true` label on the `openshell` namespace** — set
   declaratively by the wave-0 component in this directory.
4. Cluster reachability + Argo CD Application support in `openshift-gitops`.

## Bootstrap (one-time)

The root app-of-apps creates this child. Either the RHDP order's gitops path
points at `automation/argocd/apps`, or apply the root once:

```bash
make -C automation capstone-bootstrap
```

The Application self-syncs: waves 0–4 then the PostSync seed Job plants the
incident story (idempotent — re-plants on each sync so the story timestamps
stay fresh). Check with:

```bash
oc get application module-7-prereqs -n openshift-gitops
oc logs job/incident-data-seed -n openshell
```

## Facilitator steps that stay outside GitOps

- **Sandbox hand-off files**: the module's exec commands read
  `/tmp/incident-search.json`, `/tmp/mlflow.token` and
  `/tmp/agent-session-trace.json` inside the `traces` sandbox. Stage them by
   running `../../../content/modules/ROOT/assets/attachments/plant-incident-traces.sh`
  on the workspace VM (also linked from module 7's Extension prerequisites).
  The script is idempotent: it re-plants the story (matching the seed Job) and
  stages the files into the sandbox.
- **Fleet sandbox lifecycle** stays with the SAW deployment automation.
