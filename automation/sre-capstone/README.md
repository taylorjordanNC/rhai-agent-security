# Module 7 capstone prerequisites — Argo-managed cluster setup

The components module 7 (SRE Copilot Capstone) needs up **before workshop
participants proceed** live here as Argo CD–managed manifests. This repository
is the GitOps source: `argocd.argoproj.io/Application module-7-prereqs` in the
`vp-gitops` namespace points at `automation/sre-capstone/components` on
`taylorjordanNC/rhai-agent-security@main`.

| Component | Sync wave | Namespace | Purpose |
|---|---|---|---|
| demo shop | 0 | `demo` | the instrumented `demo/shop` app the fleet investigates |
| MLflow instance | 1 | `redhat-ods-applications` | `MLflow` CR — the traces specialist queries it through the proxy |
| telemetry proxy | 2 | `openshell-agents` | plain-HTTP nginx in front of Thanos (8080) and MLflow (8081); the fleet's per-agent ceilings name this proxy |
| incident console | 3 | `openshell-agents` + RBAC in `demo` | browser console for the human-confirmed outage loop |
| incident data seed | 4 + PostSync hook | `openshell` | plants the `INC-4127` agent-session story traces the traces agent searches |

## Prerequisites of this Application

1. **SAW deployment up** (module 5–6): `openshell-agents` namespace, the
   governance interceptor with the capstone fleet egress ceilings, Keycloak,
   and the fleet sandboxes (`metrics`, `traces`, `analyst`) provisioned by the
   `saw-bom` chart via `apply_bom.py` on the workspace VM. Those stay in the
   SAW fork's GitOps.
2. **RHOAI MLflow operator installed** (cluster baseline) — the operator
   reconciles the `MLflow` CR in wave 1.
3. **`mlflow-workspace=true` label on the `openshell` namespace** — MLflow's
   workspace store resolves the workspace by that label. (Verify/patch if the
   SAW deployment did not set it: `oc label ns openshell mlflow-workspace=true`.)
4. Cluster reachability + Argo CD Application support in `vp-gitops`.

## Bootstrap (one-time)

```bash
oc apply -f automation/sre-capstone/bootstrap/module-7-prereqs.yaml
```

The Application self-syncs: waves 0–4 then the PostSync seed Job plants the
incident story (idempotent — re-plants on each sync so the story timestamps
stay fresh). Check with:

```bash
oc get application module-7-prereqs -n vp-gitops
oc logs job/incident-data-seed -n openshell
```

## Facilitator steps that stay outside GitOps

- **Sandbox hand-off files**: the module's exec commands read
  `/tmp/incident-search.json`, `/tmp/mlflow.token` and
  `/tmp/agent-session-trace.json` inside the `traces` sandbox. Stage them by
  running `../../content/modules/ROOT/assets/attachments/plant-incident-traces.sh`
  on the workspace VM (also linked from module 7's Extension prerequisites).
  The script is idempotent: it re-plants the story (matching the seed Job) and
  stages the files into the sandbox.
- **Fleet sandbox lifecycle** stays with the SAW deployment automation.
