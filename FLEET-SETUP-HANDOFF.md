# Fleet Cluster Setup — Session Handoff Reference

**Purpose:** working reference for an opencode session doing fleet cluster setup for this
workshop. Captures the architecture, the credential chain (definitively mapped during a live
run), the fixes applied, known limitations, and where things stand.

**Date:** 2026-09-29 · **Source session:** live fleet install + full module test on cluster `rh8s9`

---

## 1. What this repo is

`rhai-agent-security` — the workshop content (Antora) plus automation:

| Path | What |
|---|---|
| `automation/argocd/` | a Helm chart (`Chart.yaml`, `values.yaml`, `templates/`) — the RHDP field-content deployment vehicle. The RHDP order's gitops path deploys it; its template renders the `module-7-prereqs` child Application directly into the cluster's `openshift-gitops` instance. No root app-of-apps anymore (`root.yaml` deleted) |
| `automation/fleet/` | `fleet-install.sh` / `fleet-status.sh` — loop the SAW fork's documented install over clusters in `clusters.csv` (rows: `name,server,username,password[,token]`; gitignored, never commit) |
| `automation/policies/` | the pinned sandbox policies for Modules 2 and the landlock proof |
| `content/` | the participant modules (1-8 + capstone + CTF extra) |

**The SAW fork** (cloned to `~/git/secure-agent-workspace`, branch `saw-emulation-fixes`,
`https://github.com/taylorjordanNC/secure-agent-workspace.git`): the Validated Patterns
deployment — `./pattern.sh make install` creates the operators, Vault/ESO, Keycloak,
governance resources, the gateway VM, and the BOM setup Job, and loads secrets. The fork's
procedure stays canonical; the fleet scripts only loop it.

**One-time shared assets** (created once, reused for every cluster):
- the fork checkout
- `~/values-secret.yaml` (outside the repo — never commit; holds ssh, inference, web-search)
- `~/.generated-ssh-keys/sandbox-ssh` (`make generate-keys` in the fork)

---

## 2. The credential chain (definitive — verified live)

```
~/values-secret.yaml   (inference: provider=build, model=nvidia/nemotron-3-super-120b-a12b,
                        api_key: path ~/.ngc-api-key)
        │
        ▼  ./pattern.sh make load-secrets   (VP rhvp.cluster_utils.load_secrets → Ansible in the utility container)
cluster Vault
        │
        ▼  ESO (ClusterSecretStore vault-backend, 15s refresh)
k8s Secret `inference` (openshell-agents ns)
        │
        ▼  setup Job `openshell-saw-setup` (mounts /ws-secrets/inference + /provider-secret)
apply_bom.py (on the workspace VM)
        ├─ openshell provider create --name nvidia --type nvidia --credential NVIDIA_API_KEY=<key>
        └─ nemoclaw onboard (configures openclaw with the inference.local route + the profile's model)
        │
        ▼  openshell sandbox create --provider nvidia
sandbox env NVIDIA_API_KEY=<key>   ← FROZEN AT SANDBOX CREATION
```

**The two rules this chain produces (both verified live):**
1. **Changing the inference key requires re-running `./pattern.sh make load-secrets`.** The
   CLI `provider update --credential` only touches the OpenShell provider *object* — the
   authoritative store is the Vault-backed secret. (This is why a live test run's key swap
   never propagated: the provision-time key stayed in Vault.)
2. **Provider credential rotation requires sandbox re-creation.** The sandbox's injected
   `NVIDIA_API_KEY` env is frozen at creation and does not follow provider updates.

---

## 3. The two model paths

| Path | Model | Key | Mechanism |
|---|---|---|---|
| SAW inference (Modules 4-7 agent turns) | `nvidia/nemotron-3-super-120b-a12b` via NGC | shared NGC key (`provider: build` in values-secret.yaml) | sandbox openclaw → `inference.local` → gateway-side provider → `integrate.api.nvidia.com` |
| Module 8 (guardrails) | pinned Model-as-a-Service glm-53-flash | participant's own MaaS key (they have MaaS access; entered at install time) | the `nemo-guardrails` chart calls the endpoint **directly** — no gateway-side provider, no `inference.local` |

Verified live: the NGC key completes chat at **both** `integrate.api.nvidia.com/v1` and
`build.nvidia.com/v1` (200, real completions). Module 8 passed end-to-end on the MaaS path.

---

## 4. Fresh-cluster setup sequence

1. **Local tools**: `oc`, Helm 3, podman, `jq`, `make`, `curl`, `openssl`, `virtctl`,
   openshell CLI `0.0.103` (`./automation/bootstrap/install-openshell-cli.sh`;
   `make -C automation prerequisites` to check).
2. **One-time assets**: clone the fork; `cp values-secret.yaml.template ~/values-secret.yaml`;
   edit — `provider: build`, the default nemotron model, the NGC key in a readable file
   (e.g. `~/.ngc-api-key`); `make generate-keys`.
3. **`clusters.csv`**: one row per cluster from the RHDP order. Tokens take precedence over
   user/password. RHDP OCP tokens live ~10h — refresh close to class.
4. **GitOps**: the RHDP order deploys the chart (the child lands automatically). Without the
   order pointer: `make -C automation capstone-bootstrap` once.
5. **Fleet install**:
   - one cluster: `./automation/fleet/fleet-install.sh --only <name>` — installs SAW
     (copy-images → pattern install → HCO emulate annotate) and blocks until
     `module-7-prereqs` is Synced/Healthy (~50-70 min + up to 30 min wait)
   - fleets: `--jobs 5` (5 workers ≈ 10h for 50 clusters); knobs: `--wait`,
     `--no-emulation` (KVM-capable hosts only), `--dry-run`
6. **VM setup continues in-cluster ~1-3h after the install returns**: poll
   `./automation/fleet/fleet-status.sh` until the VM is Running and the
   `openshell-saw-setup` Job is Complete.
7. **Pre-participant gate**: `./automation/fleet/fleet-status.sh --gate` — exits non-zero if
   any cluster is not ready. Apps that are OutOfSync **and** Healthy pass (expected
   two-manager churn); only not-Healthy apps or missing namespaces fail.

---

## 5. Verification checklist (post-install)

- `./automation/fleet/fleet-status.sh` — Argo sync/health, VM phase, setup Job, namespaces
- `oc get applications -n openshift-gitops` — 12 apps; **2 expected OutOfSync+Healthy
  churn**: `field-content`, `openshift-cnv` (the SAW pattern adopts parity-declared objects)
- Fleet sandboxes: `openshell --gateway openshell-saw sandbox list` — `metrics`, `traces`,
  `analyst` Ready, each with a different signed policy (now **automated** by the capstone
  BOM profile; older fork revisions need manual creation)
- Agent turn (Module 4 Ex 5):
  `openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- openclaw agent --agent main --message "Say OK"`
- Golden image: DV `openshell-gateway-docker-golden` phase Succeeded

---

## 6. Fixes applied

**Fork commits (pushed to `saw-emulation-fixes`):**
- `b55a66f` mirror Job tags every mirrored image `:latest` — the setup Job's golden-image
  import pulls `:latest`; a missing tag deadlocked the DV import in ImagePullBackOff
- `2a70a6a` apply_bom.py provider `endpoint` field → provider config at create time
- `048e3a1` create_sandbox_generic indentation repair (compile-vs-runtime bug)
- `70c04b1` capstone fleet sandbox automation: `capstone/workspace.yaml` + `sandbox.yaml`
  (generic sandboxes in the default workspace, no providers) + sandbox `policy` field →
  `--policy` at create + `--no-auto-providers` for provider-less sandboxes
- `aab64a9` revert BOM profiles to the default nemotron model (the shared NGC key design;
  the MaaS glm endpoint is a Module 8 concern)

**Workshop repo (uncommitted in the working tree — deliberately, pending review):**
- Facilitator guide: the shared-NGC-key note (quota + never reaches participants),
  single-cluster support (`--only`/`--current`/`--gate`), the gitops chart story
- Module 8 prerequisites + `02-details.adoc` + `index.adoc`: two-audience key guidance
  (vended for the run; own MaaS key for self-paced)
- `automation/charts/nemo-guardrails/values.yaml`: **the main model config lacked
  `api_key_env_var: OPENAI_API_KEY`** (model level, like the llama_guard entry) — without
  it the server's LLM client never saw the injected key and every model call 401'd
- `content/modules/ROOT/assets/attachments/plant-incident-traces.sh`: stages `/tmp/sa.token`
  for the metrics agent (the doc claimed it; the script never did) + a token-freshness note;
  Module 7 Exercise 3 reads `$(cat /tmp/sa.token)`
- `automation/fleet/fleet-install.sh`: HCO emulation deadline 20 → 45 min
- `automation/fleet/fleet-status.sh`: gate tolerance (OutOfSync+Healthy passes)
- `automation/fleet/README.md`: troubleshooting sections
- `root.yaml` deleted; the argocd chart story adopted everywhere; `PLAN-GITOPS.md` updated
- Module pages 03-08 carry **pre-existing edits from earlier sessions** — not part of this
  round; leave them out of any commit scoped to this work

---

## 7. Known limitations (upstream OpenShell gateway / nemoclaw plugin)

Found during the live run; all in the gateway/plugin layer, not this repository:

1. **The plugin registers the provider type's default endpoint** and ignores a re-pointed
   `endpoint` config — custom OpenAI-compatible endpoints (a MaaS gateway) do not work
   end-to-end through the SAW path. (`build.nvidia.com` is the type's default; note it is
   the NGC catalog/API host — inference works there too, but `integrate.api.nvidia.com` is
   the canonical inference endpoint and the one the governance profile allowlists.)
2. **The proxy passes through the client's bearer** — it does not substitute the provider's
   credential at forward time.
3. **The model-id prefixing**: the plugin prefixes the model id with the provider name
   (`nvidia/<model-id>`); the gateway's catalog lookup must account for it.
4. NVIDIA's inference 401 error format (verified live):
   `{"status":401,"title":"Unauthorized","detail":"Authentication failed"}` — useful for
   attributing failures to the upstream vs the gateway.

---

## 8. Gotchas

- **RHDP OCP tokens ~10h**: the `oc` session, `clusters.csv` tokens, and any staged tokens
  all expire. Re-login / re-stage close to class; `oc whoami -t` returning ~51 bytes is
  either the real token or an error message — check.
- **Keycloak OIDC token (the CLI's gateway auth): 599 minutes.** When it expires every
  `openshell` command fails with `ExpiredSignature`. Refresh:
  `make login OIDC_FLOW=device-code` (from the fork root), then copy the token to
  `~/.config/openshell/gateways/openshell-saw/oidc_token.json` as
  `{access_token, refresh_token, issuer, client_id}`.
- **The BOM's `create_provider` no-ops on an existing provider** — the workspace association
  is skipped. When re-running the BOM after provider changes, delete the provider first
  (sandboxes must be deleted first — they attach it).
- **`nemoclaw onboard` can fail** — apply_bom.py falls back to a manual provider config +
  generic sandbox create, but the openclaw onboard config (gateway token, model binding)
  is then missing; the agent turn needs it.
- Never print or commit keys; the credentials CSV is gitignored.

---

## 9. Current cluster state (`rh8s9`)

- Logged in with a fresh OCP token; all infrastructure green: VM Running, setup Job
  Complete, 12 apps (2 known churn), Keycloak admin login works, INC-4127 traces planted,
  the fleet sandboxes Ready with signed policies, all three agent backends reachable
  through their scoped walls
- **cuda-dev is partial**: the provider `nvidia` exists with the correct NGC credential;
  the sandboxes were deleted and the BOM re-creation is **failing** (the fallback
  `sandbox create --provider nvidia` creates a container that does not persist — needs
  diagnosis: provider-association timing, or the failed `nemoclaw onboard` breaking the flow)
- The default workspace sandboxes (notebook/cuda-sandbox/toolbox) remain intact
- The agent turn has **not** been proven end-to-end with the NGC credential — the sandbox
  env must be re-injected via re-creation first

---

## 10. Remaining work

1. Diagnose the cuda-dev sandbox re-creation failure (why the create doesn't stick)
2. Re-test the agent turn with the NGC credential in the sandbox env — the final
   end-to-end test of the shipped design
3. Commit the workshop repo's doc changes (deliberately held — pending review)
4. Next round: fresh-cluster validation of the whole shipped chain (the NGC key loaded at
   provision time wires everything correctly on first boot — this cluster's intermediate
   state is heavily experimented-on and not representative)

---

## 12. Fleet-scale run learnings (2026-09-30, 58-cluster overnight run)

New tooling in `automation/fleet/` (working tree — commit when reviewed):
- `fleet-smoke.sh` — non-destructive smoke test per cluster: gitops Healthy, NGC key
  length+hash, golden DV, setup Job, VM, dashboard/incident-console routes, fleet
  sandboxes, and a single `openclaw agent --message "Say OK"` agent turn through the
  full inference chain (sandbox → inference.local → interceptor → provider → NGC).
  Agent turn has a 3× retry (the shared NGC key rate-limits under concurrent turns)
  and a 180s watchdog. Exit 0 = participant-ready.
- `fleet-monitor.sh` — one remediation pass over every CSV cluster: skip done, tag
  `:latest` when missing, re-run load-secrets when the inference Secret is missing +
  ESO erroring (vault must be Running first; watchdog-capped — macOS has no
  `timeout`), re-create failed setup Jobs (golden DV must be Succeeded), smoke-test
  Complete setup Jobs and mark done in `clusters.status`. Run in a
  `while true; do ...; sleep 300; done` loop.
- `setup-job.yaml` — sanitized re-creation spec for `openshell-saw-setup` (Job
  labels stripped of controller-uid; selectors removed). The standard remedy:
  delete the failed Job, `oc apply` this.

Fork fixes pushed to `saw-emulation-fixes` (taylorjordanNC fork):
- `cfbed15` mirror: retry + verify the `:latest` tag after the in-cluster mirror
- `2a4b780` mirror: tag `:latest` on the Completed-job skip path — the RHDP order's
  chart pre-creates the unsuffixed mirror Jobs, so `copy-images` skips and the tag
  never lands; the golden-image DV import then crash-loops and the VM never provisions

Failure modes + remedies (all verified live):
1. **Golden-DV import crash-loops, VM never provisions** → `:latest` missing from the
   imagestream (the order chart's mirror Jobs don't tag it; the fork's copy-images
   skipped them). Remedy: `oc tag openshell-agents/openshell-gateway-docker:0.0.103
   openshell-agents/openshell-gateway-docker:latest` — the crash-looping CDI importer
   recovers on its next retry.
2. **setup Job Failed (BackoffLimitExceeded)** — the BOM started before the DV was
   ready (the crash-window above). Remedy once the DV is Succeeded: delete the Job,
   `oc apply -f setup-job.yaml`. It then completes in ~10-30 min.
3. **setup Job DeadlineExceeded** — same origin; the re-created Job gets a fresh
   deadline.
4. **Vault empty (ESO SecretSyncedError, inference Secret NotFound)** — load-secrets
   silently missed the cluster during install. Remedy: from a fork checkout,
   `KUBECONFIG=<cluster kc> ./pattern.sh make load-secrets`, then force-sync the
   ExternalSecrets (`external-secrets.io/force-sync` annotation). ESO error retries
   alone do not recover.
5. **VM's sshd down (guest SSH "connection refused")** — a bad VM boot.
   Remedy: `virtctl restart openshell-saw` — the waiting setup Job then connects.
6. **Pattern install "succeeds" without landing the SAW apps** (seen on 9pkbs,
   8qw2p first attempts) — re-run `fleet-install.sh --only <name>`; idempotent.

Smoke-test findings:
- The sandbox env `NVIDIA_API_KEY` is a gateway-issued credential (~57-58 chars), NOT
  the raw NGC key — the interceptor translates at forward time. The agent turn is the
  real proof; don't gate on the env key length.
- The gateway VM serves the dashboard (18789) but the webui (8080) is not listening:
  `setup-dashboard.sh: line 73` fails writing the systemd user service
  (Permission denied) — "WARN: dashboard setup failed" in the setup Job log. The
  dashboard route still works; the webui is the remaining gap (fork fix pending).

Known open items after the run: pod→VM networking "no route to host" on lw4r9
(post-VM-restart; needs VM re-provision), dashboard route 502 on a few scale-out
clusters (VM serves locally, endpoints/masquerade/iptables all correct — OVN/router
state), and 3 clusters with bad credentials in `clusters.csv` (chbdc, dpcnv, 7zv64
at various points — refresh from the RHDP order).

---

## 13. Quick reference: the failing-path diagnostics

If agent model calls 401 after a fresh install:

1. `oc -n openshell-agents get secret inference -o jsonpath='{.data.api_key}' | base64 -d | wc -c`
   — expect the key length (70 for the shared NGC key). 67 = the stale provision-time key:
   re-run `./pattern.sh make load-secrets`.
2. `openshell --gateway openshell-saw sandbox exec -n cuda-sandbox --workspace cuda-dev -- sh -c 'echo ${#NVIDIA_API_KEY}'`
   — must match the Secret's length. Mismatch = the sandbox predates the credential:
   re-create the sandboxes.
3. Pipe the sandbox's env key out (without printing) and test against
   `https://integrate.api.nvidia.com/v1/models` — 200 means the credential is valid.
4. Direct chat test from the control node with the NGC key against
   `https://integrate.api.nvidia.com/v1/chat/completions` — 200 means key + model are good;
   a remaining 401 at `inference.local` is the gateway proxy (upstream).
5. Check the governance interceptor logs for denials
   (`oc -n openshell-agents logs deploy/governance-interceptor`) — clean means the egress
   layer is not the blocker.
