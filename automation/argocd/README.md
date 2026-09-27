# Workshop GitOps — Argo CD app-of-apps

`root.yaml` is the workshop's root app-of-apps Application; `apps/` holds the
child Applications it manages (currently `10-capstone.yaml`, the Module 7
capstone prerequisites), and `capstone/` is the GitOps sync source that the
capstone Application deploys. The SAW deployment is deliberately *not* a child
here: it is the SAW fork's Validated Patterns deployment — scripted by
`../fleet/` or run by participants in module 3.

## Point Argo at one path

ONE pointer per cluster — either the RHDP order's gitops path targets
`automation/argocd/apps` (the order creates the root itself), or apply the
shipped root once:

[source,bash]
----
oc apply -f automation/argocd/root.yaml
# or, via make:
make -C automation capstone-bootstrap
----

Never use both on the same cluster — two roots managing the same children
fight over ownership. Children that depend on SAW (capstone) hold in retry
until SAW and the RHOAI MLflow operator are healthy — no manual re-apply.

## Argo instance

The default is `openshift-gitops` (the GitOps operator default instance).
For a cluster where Argo CD runs elsewhere, swap the namespace in one pass
across the root and every child:

[source,bash]
----
sed -i.bak 's/namespace: openshift-gitops/namespace: vp-gitops/g' \
  root.yaml apps/*.yaml && rm -f root.yaml.bak apps/*.bak
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
in `apps/` — the root's `directory.include: "*.yaml"` picks them up
automatically.
