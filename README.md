= Securing AI Agents on Red Hat AI

*From OpenShell to Secure Agent Workspace.*

This Showroom workshop uses one OpenShift 4.22 cluster and progresses from the
raw OpenShell pod boundary to the production-shaped Secure Agent Workspace VM:

. Deploy and inspect a basic OpenShell gateway and sandbox on OpenShift.
. Deploy OpenClaw on the raw pod boundary and identify its runtime boundary.
. Test the OpenShell boundary: default-deny egress, L7 method control, binary
   binding, and mandatory Landlock, each with runtime evidence.
. Change policy live — allow a new endpoint, verify it works, restore, and
   confirm the denial returns.
. Act as platform admin and inspect what every sandbox attempted against the
   gateway.
. Optionally install Secure Agent Workspace (OpenShift Virtualization, OIDC,
   Vault, GitOps), then validate and operate the deployed environment.
. Run OpenClaw model-backed inside the SAW-managed NemoClaw sandbox, then test
   permitted and rejected agent actions and governance.
. Optionally close with the SRE incident fleet or the Security CTF.
. Add model-boundary guardrails: deploy a NeMo Guardrails server with the
   TrustyAI operator, prove rails block sensitive input before the model, wire
   a client application, and change a rail live.

* `automation/` contains the raw OpenShell harness and pinned policies used by
  the raw-track modules (1, 2, and the optional Security CTF), plus the
  Argo-managed capstone prerequisites.
* `automation/sre-capstone/` is the GitOps source for the Module 7 capstone
  environment (demo shop, MLflow instance, telemetry proxy, incident console,
  and the incident-data seed job): `Application module-7-prereqs` in the
  `vp-gitops` namespace points at `automation/sre-capstone/components` here.
  Bootstrap with `make -C automation capstone-bootstrap` after the SAW
  deployment is up.
* `automation/charts/nemo-guardrails` is the Helm chart Module 8 installs: it
  deploys the guardrails server via the TrustyAI operator with a
  user-supplied model API key.
* `OpenShell` supplies the OpenShift Helm deployment, raw sandbox lifecycle, and
  default-deny/L7 policy exercises.
* `NemoClaw` supplies the managed OpenClaw runtime and policy model. The
  cluster-resident runtime is provisioned through Secure Agent Workspace rather
  than the standalone local `nemoclaw onboard` workflow.
* The `saw-emulation-fixes` branch of the `secure-agent-workspace` fork supplies
  the production-oriented deployment assets and the canonical SAW procedure.
* This repository provides the participant exercises, validation criteria, and
  technical context that connect those experiences.

* `agent-harness-in-a-box` supplies the raw OpenShift evaluation deployment and
  policy examples.
* `nemoclaw-openshift-launchable` remains useful context for interaction,
  configuration, observability, and fleet exercises, but its pinned versions
  are not the workshop baseline.

Build the site with:

```bash
npm ci
npm run build
```

The workshop includes the harness raw OpenShell deployment and policy
quickstart. It consumes the SAW deployment procedure directly from the fork's
Antora component so charts, scripts, and deployment commands are not copied into
this repository. The SAW fork stays trim to the changes needed for the SAW
deployment itself; workshop-specific assets (the capstone environment, its
GitOps Application, and the participant exercises) live here.
