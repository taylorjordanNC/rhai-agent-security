# Workshop GitOps — Argo CD child Applications

`automation/argocd/` is a Helm chart (`Chart.yaml`, `values.yaml`) — the RHDP
field-content deployment vehicle. `templates/10-capstone.yaml` is the child
Application it deploys (currently `module-7-prereqs`, the Module 7 capstone
prerequisites), and `capstone/` is the GitOps sync source that the child
deploys. The SAW deployment is deliberately *not* a child here: it is the SAW
fork's Validated Patterns deployment — scripted by `../fleet/` or run by
participants in module 3.

## Deploy the child

On RHDP orders the order's gitops path deploys the chart — the child lands in
the cluster's `openshift-gitops` instance with no manual step. On a cluster
without the order pointer, apply the child once:

[source,bash]
----
oc apply -f automation/argocd/templates/10-capstone.yaml
# or, via make:
make -C automation capstone-bootstrap
----

On an order-managed cluster the chart owns the Application; don't double-apply
it. The child holds in retry until SAW and the RHOAI MLflow operator are
healthy — no manual re-apply.

## Argo instance

The default is `openshift-gitops` (the GitOps operator default instance).
For a cluster where Argo CD runs elsewhere, swap the namespace in one pass:

[source,bash]
----
sed -i.bak 's/namespace: openshift-gitops/namespace: vp-gitops/g' \
  templates/10-capstone.yaml && rm -f templates/10-capstone.yaml.bak
----

## Decay playbook

The workshop GitOps is workshop-owned and does not reference `vp-gitops`
structurally. If the SAW fork or its framework changes:

| Scenario | Action |
|---|---|
| Fork renames/moves `vp-gitops` | Update the `saw_gitops_namespace` attribute in both Antora `antora.yml` files (parity-checked by `npm run validate:docs`) and `SAW_GITOPS_NS` in `../fleet/` |
| Fork changes `pattern.sh`/install procedure | Update the per-cluster function in `../fleet/fleet-install.sh` (it calls the fork's entry points verbatim) |
| Fork charts change runtime namespaces | Update the namespace references in `capstone/` (the wave-0 `openshell` Namespace, telemetry proxy, seed Job) |
| Fork decays or the framework is abandoned | Plan B: rebuild SAW as Argo children pointing at the fork's charts (`charts/openshift-cnv`, `openshell-keycloak`, `pattern-secrets`, `governance-policy`, `governance-interceptor`, `saw-bom`, `openshell-saw` + `/overrides/openshell-saw.yaml`) plus Subscription glue (CNV `stable`, RHBK `stable-v26`, RHOAI `fast`). The charts are plain Helm; ~10 manifests. Not built until needed |

## Managed children

| Child | Source path | Depends on |
|---|---|---|
| `module-7-prereqs` | `automation/argocd/capstone` | SAW up (retry), RHOAI MLflow operator |

Add future children (e.g. the NeMo Guardrails chart) as Application manifests
in `templates/` — the chart deploys them the same way as `10-capstone.yaml`.
