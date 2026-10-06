= Workshop Automation

This directory contains the raw OpenShell sandbox environment installer, the
canonical policy used by the workshop, the workshop GitOps chart (with the
capstone manifests it deploys), and the fleet SAW deployment scripts.

| Directory | What it holds
| `openshell-env/` | raw OpenShell sandbox environment scripts: install, verify, teardown, and the sandbox security test
| `policies/` | the pinned sandbox policies the workshop applies
| `argocd/` | the workshop GitOps chart (`Chart.yaml`, `values.yaml`, `templates/`) and the capstone manifests it deploys (`capstone/`)
| `fleet/` | multi-cluster SAW deployment scripts for RHDP orders
| `bootstrap/` | local CLI install and the pre-flight check
| `charts/` | the Helm charts modules install (currently `nemo-guardrails`)

Secure Agent Workspace deployment assets are not copied into this directory.
Follow the workshop instructions from the `saw-emulation-fixes` branch of the
`taylorjordanNC/secure-agent-workspace` fork.

== Workshop GitOps (RHDP chart)

`argocd/` is the workshop's RHDP field-content chart: the order's gitops path
deploys it, and its template (`argocd/templates/10-capstone.yaml`) creates the
`module-7-prereqs` child Application (the Module 7 capstone prerequisites).
`argocd/capstone/` is the sync source that child deploys. The SAW deployment
is deliberately *not* a child here — it is the SAW fork's Validated Patterns
deployment (scripted by `fleet/` or run by participants in module 3).

On a cluster without the order pointer, apply the child once:

[source,bash]
----
make -C automation capstone-bootstrap
----

On an order-managed cluster the chart owns the Application; don't double-apply
it. The child holds in retry until SAW and the RHOAI MLflow operator are
healthy — no manual re-apply.

The default Argo instance is `openshift-gitops` (the GitOps operator default).
For a cluster where Argo CD runs elsewhere, swap the namespace in one pass:

[source,bash]
----
sed -i.bak 's/namespace: openshift-gitops/namespace: vp-gitops/g' \
  automation/argocd/templates/10-capstone.yaml && \
  rm -f automation/argocd/templates/10-capstone.yaml.bak
----

If the SAW fork or its Validated Patterns framework changes, update only the
named knobs (`saw_gitops_namespace` in both Antora `antora.yml` files,
parity-checked by `npm run validate:docs`) — nothing in the workshop GitOps
references `vp-gitops` structurally.

== Fleet SAW deployment (RHDP orders)

`fleet/` loops the SAW fork's documented install over a credentials CSV —
the **SAW as script** path for ~50 RHDP clusters. It calls only the fork's
entry points (`make copy-images`, `./pattern.sh make install`, the HCO
emulation loop), so fork updates flow through:

[source,bash]
----
./automation/fleet/fleet-install.sh --jobs 5   # 50 clusters ≈ 2-3h
./automation/fleet/fleet-status.sh             # read-only per-cluster poll
----

See `fleet/README.md` for the one-time shared assets (fork checkout,
`values-secret.yaml`, SSH keypair) and the credentials file (gitignored).

== Prerequisites

Run from a RHEL/Fedora bastion or a validated Linux/WSL2 environment:

* OpenShift 4.22 access with the permissions required by the selected install.
* `oc`, Helm 3, OpenShell `0.1.2-rhaiv.0` (RHAIV container via the PATH
  wrapper), Podman 4.3+, `jq`, `make`, `curl`, and `openssl`.
* `virtctl` matching the cluster for SAW VM inspection and SSH.

Install the pinned OpenShell client with:

[source,bash]
----
./automation/bootstrap/install-openshell-cli.sh
----

Check the local tools and cluster context:

[source,bash]
----
make -C automation prerequisites
----

== Raw OpenShell

Install the raw OpenShell evaluation gateway from `openshell-env/`, then run
the sandbox control-layer test after the Modules 1-2 exercises have created the
`policy-lab` sandbox and applied the quickstart policy:

[source,bash]
----
make -C automation install-openshell
make -C automation openshell-security-test
----

This path intentionally uses the environment's plaintext, unauthenticated lab
configuration. It is not the production security posture.

== NeMo Guardrails chart

`charts/nemo-guardrails` is the Helm chart that Module 8 installs. It deploys
a NeMo Guardrails server on OpenShift AI via the TrustyAI operator from a
`NemoGuardrails` custom resource, with the guardrails configuration rendered
into a ConfigMap and the model API key supplied by the participant at install
time (never committed to values):

[source,bash]
----
helm install nemo-guardrails automation/charts/nemo-guardrails \
  -n guardrails --create-namespace \
  --set llm.apiKey="$LLM_API_KEY"
----

The chart's README documents the Llama Guard remote moderation wiring, the
optional on-cluster content safety detector, and the API key handling.

== Update the pinned baseline

The OpenShell version and the default sandbox image digest are pinned in
several places. Update all of them in a single commit so the automation,
content, and verification cannot drift:

[cols="1,2",options="header"]
|===
| Location | What to update

| `automation/Makefile`
| `OPENSHELL_VERSION` (Helm chart pin; the gateway image digest is pinned in
  `install.sh`) and `OPENSHELL_SANDBOX_IMAGE` (default sandbox image digest)

| `content/antora.yml`
| `openshell_version` and `openshell_sandbox_image` (rendered into the
  participant pages)

| `secure-agent-workspace/docs/antora/antora.yml` (SAW fork)
| `openshell_version`, `openshell_saw_version`, and `ocp_version` must agree
  with this repository; `npm run validate:docs` enforces the parity

| `automation/openshell-env/verify.sh`
| The `OPENSHELL_CLI_VERSION` fallback default used when the script runs
  outside `make openshell-verify`

| `automation/README.md` and
  `automation/openshell-env/README.md`
| The pinned version named in the prerequisites text
|===

After updating, run `make -C automation openshell-verify` and
`npm run validate:docs` from the repository root, then commit the change as one
commit.

The SAW guest gateway pin (`openshell_saw_version`) is a Red Hat packaging
suffix of the same compatibility line; update it only when the SAW fork changes
its gateway build.
