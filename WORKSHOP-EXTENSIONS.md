# Workshop Extension Recommendations

Working document — not rendered in the Showroom site. Each section is a
candidate user step for teaching OpenShell/OpenClaw inner workings, with the
source lesson in the `nemoclaw-openshift-launchable` project, a suggested
placement in this workshop, draft commands, and known caveats. Items are
ordered by value: the first three teach inner workings the workshop currently
asserts but never shows.

---

## 1. The OpenClaw gateway inside the sandbox (highest value)

**Teaches:** a sandboxed agent has its *own* control plane — WebSocket gateway +
Control UI — running inside the sealed pod, distinct from the OpenShell gateway.
This is the concrete version of the "two gateways" distinction the overview
states but no exercise demonstrates.

**Source:** `nemoclaw-openshift-launchable/web/src/content/configure.mdx`,
`chat.mdx`, `pairing.mdx`; the provisioner
(`charts/saw-bom/scripts/apply_bom.py`) shows the real commands.

**Placement:** extend the Module 1 OpenClaw exercise (raw boundary), or a
dedicated exercise in Module 4 (SAW boundary, where a real model exists).

**Draft steps:**

```bash
# Inspect the inner OpenClaw configuration (already staged by the sandbox image
# or the setup Job):
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  cat /sandbox/.openclaw/openclaw.json | python3 -m json.tool

# The inner gateway auth token and Control UI origins are in that file:
#   gateway.auth.token                 - token for the inner WebSocket/Control UI
#   gateway.controlUi.allowedOrigins   - browser origins allowed to connect

# Start the inner gateway inside the sandbox (the provisioner does this at
# deploy time; manual form for a hand-built sandbox):
openshell sandbox exec -n <sandbox> --tty -- \
  /bin/bash -ic 'export HOME=/sandbox OPENCLAW_HOME=/sandbox \
    SQLITE_TMPDIR=/sandbox/.openclaw/state TMPDIR=/sandbox/.openclaw/state \
    OPENCLAW_NIX_MODE=0 TERM=xterm-256color; \
    nohup openclaw gateway run --allow-unconfigured --bind lan --port 18789 \
    > /tmp/openclaw-gateway.log 2>&1 &'

# Verify it is listening (inner port is 18789, inside the sandbox):
openshell sandbox exec -n <sandbox> -- curl -sf http://127.0.0.1:18789/health
```

**Device pairing (browser Control UI):**

```bash
# The UI reports "Device pairing required". List and approve from inside the
# sandbox through the OpenShell gateway:
openshell --gateway openshell-saw sandbox exec -n <sandbox> --workspace <ws> -- \
  openclaw devices list --json
openshell --gateway openshell-saw sandbox exec -n <sandbox> --workspace <ws> -- \
  openclaw devices approve <REQUEST_ID>
```

**Caveats (verified):**

* The deployed BOM registers only the external dashboard Route as an allowed
  Control UI origin — a `localhost:18790` browser connect can be rejected until
  the origin is registered. Check
  `openclaw config get gateway.controlUi.allowedOrigins` before forwarding.
* Device pairing stays enabled in the BOM; do not disable
  (`gateway.controlUi.dangerouslyDisableDeviceAuth`) to make an exercise pass.
* Scope-upgrade deadlock: on a new gateway the operator pairs with only the
  `operator.pairing` scope and cannot approve others until approvals are
  enabled (grants `operator.admin`). Approve the displayed request only.
* The forward command (`make nemoclaw-gui`) prints a token-bearing URL — treat
  it as a credential.

---

## 2. Inference provider wiring and verification (highest value)

**Teaches:** how inference reaches the agent — the provider lives gateway-side,
`inference.local` resolves inside the sandbox, and the upstream credential is
never delivered to the agent. Turns the Modules 4–5 credential-boundary claim
into a hands-on verification.

**Source:** `inference.mdx`, `openai-api.mdx`; `openshell provider --help`.

**Placement:** Module 4 (after "Run and verify an agent request") or Module 5
before the governance rejection.

**Draft steps:**

```bash
# What providers exist on the gateway, and what profiles are vended:
openshell --gateway openshell-saw provider list
openshell --gateway openshell-saw provider list-profiles

# What is attached to the sandbox:
openshell --gateway openshell-saw sandbox provider list -n cuda-sandbox --workspace cuda-dev

# Prove the virtual inference endpoint resolves from inside the sandbox:
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  curl -sf https://inference.local/v1/models

# Prove the upstream credential is NOT in the sandbox environment:
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  sh -c 'env | grep -iE "key|token|secret" || echo "no credential material in env"'

# For a hand-built sandbox on the raw gateway, attach a provider at creation
# (requires a configured provider; the raw track has none by default):
openshell provider create --name workshop-inference --type build --credential NGC_API_KEY
openshell sandbox create --name inf-demo --provider workshop-inference --no-tty -- true
```

**Caveats:**

* The exact provider type identifier must match the vended profile set; SAW
  governance fails closed for unvended types (Module 5 covers the rejection).
* On the raw gateway there is no provider by design — attaching one requires an
  API key and changes the "no model key required" property of the raw track.
  Frame it as an optional exercise.

---

## 3. Identity & Soul — the agent's brain is plain workspace files (highest value)

**Teaches:** OpenClaw memory and personality are ordinary `.md` files staged
into `/sandbox` (IDENTITY.md, SOUL.md) — visible, reviewable, and living inside
the filesystem-policy-writable path. Connects the agent story directly to the
policy story: the brain is data in a governed directory, not a hidden system
prompt.

**Source:** `soul.mdx`; `scripts/fleet.sh` stages them
(`IDENTITY.md`/`SOUL.md`/`BOOTSTRAP.md` from `manifests/openclaw/fleet-roles/<name>/`).

**Placement:** Module 5 (agent capabilities) — one short exercise.

**Draft steps:**

```bash
# Read the agent's identity files from outside the agent:
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  cat /sandbox/IDENTITY.md
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  cat /sandbox/SOUL.md

# Or ask the agent to read its own SOUL and explain where it lives:
#   "Read /sandbox/SOUL.md and explain why that location is writable."

# Stage a modified SOUL (this is all identity is — a file in the workspace):
openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- \
  sh -c 'printf "I am the workshop agent. I operate inside a sealed sandbox.\n" > /sandbox/IDENTITY.md'
```

**Caveats:**

* The NemoClaw BOM sandboxes stage these at provision time only for fleet-style
  flows; a BOM-provisioned `cuda-sandbox` may not contain them. Verify with
  `sandbox exec ... ls /sandbox` and fall back to staging a file as above.
* Keep the framing: identity is reviewable workspace data — capability changes
  are reviewed changes, not prompt instructions.

---

## 4. Skills & Governance

**Teaches:** OpenClaw's extension model — installing verified skills from a
registry, authoring one, and governing which skills run. The workshop covers
provider governance but nothing about skills.

**Source:** `skills.mdx`; `scripts/fleet.sh` installs registry skills
(`openclaw plugins install '<skill>'` after staging `/sandbox/.npmrc`).

**Placement:** Module 5 or the optional extensions module.

**Draft steps:**

```bash
# List installed plugins/skills:
openshell --gateway openshell-saw sandbox exec -n <sandbox> -- openclaw plugins list

# Install from a registry (the fleet stages registry credentials in .npmrc):
openshell --gateway openshell-saw sandbox exec -n <sandbox> -- \
  sh -c 'NODE_NO_WARNINGS=1 openclaw plugins install "<skill-name>"'
```

**Caveats:** registry availability and authentication are environment-specific;
the fleet's Verdaccio registry is launchable infrastructure. If unavailable,
restrict the step to listing and reading skill files under
`/sandbox/.agents/skills/`.

---

## 5. Heartbeat — run the agent autonomously

**Teaches:** a scheduled self-prompt turns the agent into a long-running
operator that acts on its own — still inside the same sandbox boundary and
policy. The strongest "agent as a governed workload" lesson, currently absent.

**Source:** `heartbeat.mdx` (openclaw cron: `cron add` / `cron run`).

**Placement:** Module 5 or the optional extensions module.

**Draft steps:**

```bash
# Schedule a self-prompt (bounded example):
openshell --gateway openshell-saw sandbox exec -n <sandbox> -- \
  openclaw cron add --schedule "*/5 * * * *" --prompt "Check /sandbox and report changes"
# Run it once immediately to observe:
openshell --gateway openshell-saw sandbox exec -n <sandbox> -- openclaw cron run
```

**Caveats:** cron prompts consume inference tokens; bound the schedule and
prompt for lab use, and remove the cron afterwards.

---

## 6. Web search as a governed tool

**Teaches:** a second concrete tool (search) enabled inside the sandbox and
governed by the same egress policy — tool use is explicit and policy-scoped.

**Source:** `web-search.mdx` (key-free DuckDuckGo path). The SAW BOM's default
web-search provider is Brave and requires a credential.

**Placement:** Module 5.

**Draft steps:** enable search for the agent, run one search, and prove the
egress policy records the destination (search endpoint appears in the OCSF
evidence when allowed, or a denial event when the policy excludes it).

**Caveats:** the key-free DuckDuckGo path depends on upstream availability; the
BOM's Brave provider needs `~/.brave-api-key` per the secret contract. Choose
one path per environment and document it.

---

## 7. OpenAI-compatible API surface

**Teaches:** the inner OpenClaw gateway can expose `/v1/chat/completions` so
any OpenAI client calls the governed agent programmatically — the consumption
interface of the inner workings.

**Source:** `openai-api.mdx`.

**Placement:** optional extensions module or capstone.

**Draft steps:** start the inner gateway with the API enabled, forward the
port, and call `/v1/chat/completions` with curl from the workstation; the
conversation appears in the same policy and audit evidence.

---

## 8. Sandbox port forwarding (`--forward`)

**Teaches:** an OpenShell feature exercised nowhere in the workshop — forward a
local port to a sandbox service before the initial command starts.

**Source:** `openshell sandbox create --help` (`--forward [bind_address:]port`,
keeps the sandbox alive).

**Placement:** Module 1 (alongside the OpenClaw exercise) or Module 5.

**Draft steps:**

```bash
openshell sandbox create --name fwd-demo --no-auto-providers \
  --forward 8080 --no-tty -- true
# Then reach the sandbox service on localhost:8080 while the sandbox runs.
```

---

## 9. "Under the Hood" — show the fleet's real orchestration

**Teaches:** transparency — the capstone fleet is a fixed plan with prescribed
probes and a telemetry skill, all reviewable code. "Nothing hidden" is a trust
story worth one read-only section.

**Source:** `orchestration.mdx`; the actual assets:
`fleet.txt`, `scripts/fleet.sh`, `manifests/openclaw/fleet-roles/*/policy.yaml`,
`manifests/openclaw/skills/cluster-telemetry/`.

**Placement:** Module 7 (after the incident exercise), read-only pointer.

**Draft content:** a short table mapping fleet role → policy file → allowed
backend, plus the observation that the "intelligence" is a prescribed probe
executed by a sealed sandbox — the policy, not the prompt, is the control.

---

## 10. Build Your Own — extend the fleet

**Teaches:** the fleet is a pattern. Author a new specialist: add a line to
`fleet.txt`, a role folder (IDENTITY/SOUL), and a policy scoped to one backend.

**Source:** `build-your-own.mdx`.

**Placement:** optional 301 authoring extension after Module 7.

**Caveats:** requires the launchable checkout and its observability stack;
facilitator-provisioned only.

---

## 11. Observability: OpenShift-native stack (Prometheus, LokiStack, Perses) and Grafana

**Teaches:** operator-side observability of the gateway and fleet from the
OpenShift-native stack — Prometheus (User Workload Monitoring), LokiStack,
Perses dashboards — with the launchable's Grafana stack as the alternative.
This is the natural replacement for CLI-only evidence in the capstone.

**Source:** `monitoring.mdx`; the launchable deploys the operator-based stack
via `scripts/15-observability.sh` (Cluster Observability, OpenTelemetry, Tempo,
Logging, Loki operators; UWM enabled; MinIO backend; LokiStack +
ClusterLogForwarder; OTEL collector). The capstone fleet's backends are exactly
these: Thanos Querier, the Loki gateway (application vs infrastructure paths),
and the Tempo gateway — all bearer-token authenticated.

**OpenShell integration points (verified):**

* The gateway exposes Prometheus metrics on 9090 (`grpc_requests_total` by
  method+code, readiness gauges, request-duration summaries) — scrapeable into
  OpenShift User Workload Monitoring via a `ServiceMonitor` on the
  `openshell` service.
* The gateway has **built-in OpenTelemetry tracing**: every gRPC request log
  line carries `otel.name` / `otel.kind` server-span attributes. Point its OTLP
  export at an in-cluster OTEL collector to land gateway traces in Tempo.
* Sandbox and gateway pod logs (RPC traces) are forwardable to LokiStack via a
  `ClusterLogForwarder` — giving the logs/events capstone agents an
  application-logs backend without the launchable's custom stack.

**Draft user steps (capstone, facilitator-provisioned):**

```bash
# Gateway metrics in OpenShift Prometheus (UWM):
oc -n openshell port-forward svc/openshell 9090:9090   # raw scrape first
# After a ServiceMonitor exists, query the Thanos Querier API:
TOKEN=$(oc create token monitoring-reader -n monitoring --duration=1h)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://thanos-querier.openshift-monitoring.svc.cluster.local:9091/api/v1/query?query=openshell_server_grpc_requests_total"

# Forwarded gateway/sandbox logs via the Loki gateway (application path):
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://logging-loki-gateway-http.openshift-logging.svc.cluster.local:8080/api/logs/v1/application/loki/api/v1/query_range?query=%7Bnamespace%3D%22openshell%22%7D"
```

**Caveats:**

* Every query endpoint requires a bearer token (SA with
  `cluster-monitoring-view` ClusterRole; the fleet's `monitoring-reader` SA
  pattern). Do not embed tokens in workshop content.
* Loki application vs infrastructure paths are distinct
  (`/api/logs/v1/application/...` vs `/api/logs/v1/infrastructure/...`) — the
  capstone's `logs` and `events` agents split exactly there.
* Keep Grafana (launchable) vs Perses/OpenShift dashboards as an either/or per
  environment; both read the same backends.

---

## 12. MLflow / OpenShift AI tracing for agent conversations

**Teaches:** agent conversations and model calls are traceable workloads. The
OpenShell gateway's OTLP export (or an OpenAI-compatible tracing hook in the
agent) can land spans in MLflow tracking (OpenShift AI workbench or
in-cluster MLflow server), producing a per-conversation artifact — another
governed, observable output of the same boundary.

**Source:** the old harness's optional MLflow tracing integration;
OpenShift AI MLflow workbench/registry pattern.

**Placement:** optional extensions module; pairs with item 1 (inner gateway)
and the ref-architecture mapping.

**Draft steps:** enable the OTEL/MLflow export on the inner OpenClaw gateway or
the inference provider, run one conversation, then open the MLflow experiment
and inspect the trace/artifact from outside the agent — the conversation is
evidence, not just chat.

**Caveats:** MLflow availability is environment-specific (workbench vs
in-cluster server); do not route conversation content containing secrets into
shared tracking stores — apply the same secret-handling rules as the printed
Control UI URLs.

---

## 13. Exec duality — "a sandbox IS a pod, but sealed"

**Teaches:** the two ways into a sandbox and what each proves:
`sandbox exec` (run a command, streamed, exits with the remote exit code) vs
`sandbox connect` (interactive PTY session). Both cross the OpenShell boundary;
neither bypasses the seal.

**Source:** `into-the-sandbox.mdx`.

**Placement:** strengthen Module 1's sandbox exercise with one paragraph and a
two-command demonstration.

---

## 14. OpenShift cluster resource prerequisites — precise

**Precise, evidence-based prerequisites from the cluster runs.** Mark anything
not yet verified against chart values accordingly.

### OpenShell + OpenClaw without SAW (the raw track — verified live)

The full raw track (gateway + base sandbox + OpenClaw sandbox + policy
exercises) ran on a **single control-plane node** of a workshop cluster: both
`openshell-0` and the sandbox pods scheduled on
`control-plane-cluster-pqsps-1`. Verified requirements:

* **Cluster:** one multinode OpenShift 4.22 cluster (verified working with the
  raw track on a single hosting node; 2+ nodes recommended so sandbox and
  gateway workloads can separate).
* **Permissions (cluster-admin, verified operations):** create an OLM
  Subscription in `openshift-operators`; accept cluster-scoped Agent Sandbox
  CRDs and RBAC; grant the `privileged` SCC to the `openshell-sandbox`
  ServiceAccount; create the `openshell` namespace; install the Helm release.
* **Storage:** a default StorageClass (verified `WaitForFirstConsumer` RBD
  worked). Verified consumption: the gateway takes a **1Gi** PVC
  (`openshell-data-openshell-0`). Sandbox workspace PVC size defaults to the
  chart's `sandboxWorkspace` storage value — verify before promising numbers.
* **Egress (verified pulls):** `oci://ghcr.io/nvidia/openshell/helm-chart`
  (chart), the version-pinned supervisor image (~31 MB), the base sandbox image
  (**3.2 GB**), and the OpenClaw sandbox image (similar size class — budget
  registry egress accordingly). Policy exercises additionally need egress to
  `api.github.com` and `httpbin.org` from sandbox pods.
* **Per-sandbox footprint:** chart defaults (CPU/memory) were sufficient for
  the policy exercises; pass `--cpu`/`--memory` if a lab needs tighter bounds.
* **OpenClaw without SAW adds:** the inner OpenClaw gateway (port 18789 inside
  the sandbox) and, only if model-backed, inference egress to the provider
  endpoint plus a configured provider credential. Runtime-only deployment
  needs neither.

### Whole workshop including SAW (facilitator/prework sizing)

* **Cluster:** multinode OpenShift 4.22 with **16 CPUs and 32 GiB minimum**
  for QEMU software emulation; hardware virtualization substantially better.
  A dedicated workshop cluster is required — the SAW pattern installs
  cluster-scoped operators and OpenShift Virtualization, and its uninstall
  path can affect other virtualization workloads.
* **Additional capacity:** OpenShift Virtualization operator and golden-image
  DataVolume import, Keycloak + PostgreSQL, Vault/ESO, governance
  interceptor, Developer Hub and OpenShift AI operator subscriptions (in
  `values-prod.yaml` — disable if not required), and the workspace VM itself.
* **Image imports:** the four quickstart images via `make copy-images` into
  the internal registry, plus the pinned binaries pulled by the setup Job.
* The canonical sizing and cluster-prerequisite procedure lives in the SAW
  Antora component (`cluster-prerequisites.adoc`, `control-node.adoc`) — keep
  this section as the quick reference and link, do not duplicate.

---

## Admin perspective: viewing sandbox activity and logs

Verified mechanisms for the platform-admin view (all confirmed live on an
OpenShift 4.22 cluster with OpenShell 0.0.103). Module 2 already includes the
short version; this is the full reference.

### Admin, cluster-wide (raw gateway pod)

```bash
# Every Sandbox CR in the cluster (admin-only, cluster-scoped API):
oc get sandboxes -A

# Aggregate gateway RPC activity across ALL sandboxes, by method:
oc -n openshell logs statefulset/openshell --tail=500 | \
  grep -oE 'openshell\.[A-Za-z0-9.]+/[A-Za-z]+' | sort | uniq -c | sort -rn
# Typical output (verified): CreateSandbox, ExecSandbox, RelayStream,
# SubmitPolicyAnalysis, GetSandboxConfig, GetInferenceBundle, UpdateConfig, ...
```

### Operator, per-sandbox event history

```bash
# The gateway event store keeps OCSF events per sandbox. Denials include the
# destination, calling binary, engine, and reason (verified):
openshell --gateway local-gateway logs policy-lab --since 30s
openshell --gateway local-gateway logs policy-lab --level info --since 30s
```

### Operator, live event stream

```bash
# Interactive TUI streaming OCSF events in real time: sandbox creation,
# command execution, network policy enforcement (ALLOWED/DENIED).
# Requires a TTY — verified it errors without one (run in an interactive terminal):
openshell term --gateway local-gateway
```

### Aggregate metrics

```bash
# The gateway exposes Prometheus metrics on 9090 (service port 9090/TCP).
# Verified content: grpc_requests_total by method+code, readiness gauges,
# request-duration summaries. No denial-specific metrics in this build.
oc -n openshell port-forward svc/openshell 9090:9090
curl -s http://127.0.0.1:9090/metrics | grep openshell_server
```

### Verified limitations (state these honestly in any admin exercise)

* The gateway pod stdout carries gRPC request tracing (method, request_id,
  sandbox_id) but **not** OCSF denial events — denials live in the gateway event
  store, surfaced through `openshell logs`/`openshell term`.
* `openshell logs` is **per-sandbox**; there is no cross-sandbox denial query in
  0.0.103. Cross-sandbox visibility comes from the pod log RPC aggregate and
  metrics only.
* Metrics contain no denial counters in this build.
* For SAW, the guest gateway runs **inside the workspace VM**, not as a pod:
  admin views are `virtctl` SSH into the VM
  (`systemctl --user status openshell-gateway.service`, `journalctl --user`),
  or the OpenShell CLI against the workspace gateway. Cluster-level `oc logs`
  shows the VM pod, not the gateway process.
