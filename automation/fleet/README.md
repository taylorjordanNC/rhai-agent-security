# Fleet SAW deployment

Scriptable form of the Secure Agent Workspace install for Red Hat Demo
Platform orders (~50 clusters). This is the **SAW as script** path: the same
procedure participants run in module 3, looped over clusters. The SAW fork's
procedure stays canonical — these scripts only loop it and never duplicate
fork logic.

## Division of labor

| Path | What | Where |
|---|---|---|
| RHDP order gitops path | workshop prerequisites (capstone child) | `../argocd/apps` — the order points Argo at that path |
| Fleet script (this dir) | SAW install per cluster | `fleet-install.sh` |
| Manual (module 3) | participant-run SAW install | the SAW fork's documented procedure |

The workshop root app-of-apps works in any order: apply the RHDP pointer at
order time and the capstone child retries until this script has installed
SAW on the cluster.

## One-time setup (shared across all clusters)

```bash
# 1. Fork checkout (one local clone is reused for every cluster):
mkdir -p ~/git && git clone --branch saw-emulation-fixes \
  https://github.com/taylorjordanNC/secure-agent-workspace.git ~/git/secure-agent-workspace

# 2. Secret values file (see the SAW fork install doc for the content):
cp ~/git/secure-agent-workspace/values-secret.yaml.template ~/values-secret.yaml

# 3. SSH keypair (one keypair is reused for every cluster):
cd ~/git/secure-agent-workspace && make generate-keys
```

## Credentials

```bash
cp clusters.csv.example clusters.csv   # gitignored — fill in from the RHDP order
```

`clusters.csv` holds cluster-admin logins. It is gitignored; never commit it,
and keep it off shared hosts.

## Install

```bash
./fleet-install.sh                       # sequential, apply-and-move-on
./fleet-install.sh --jobs 5              # 5 parallel workers → 50 clusters ≈ 2-3h
./fleet-install.sh --wait                # block per cluster until the setup Job completes
./fleet-install.sh --no-emulation        # KVM-capable clusters only
./fleet-install.sh --dry-run             # print the plan, change nothing
```

Per cluster the script runs the fork's documented steps, in order:
`make copy-images` → `./pattern.sh make install` → HCO software-emulation
annotate (idempotent; skipped with `--no-emulation`) → optional setup-Job
wait. After the install returns, VM setup continues in-cluster for ~1-3h.

Parallel workers (`--jobs`) each clone the fork into `.workers/` — the
Validated Patterns framework writes state in the checkout, so one clone
cannot serve two clusters at once.

## Status

```bash
./fleet-status.sh            # poll every cluster in clusters.csv
./fleet-status.sh --current  # poll only the current oc context
```

Shows Argo CD Applications (sync/health), the SAW VM phase, the setup Job,
and the workshop namespaces per cluster.

## Environment knobs

| Variable | Default | Purpose |
|---|---|---|
| `SAW_DIR` | `~/git/secure-agent-workspace` | fork checkout (sequential mode) |
| `SAW_REF` | `saw-emulation-fixes` | fork revision (`--jobs` clones) |
| `SAW_GITOPS_NS` | `vp-gitops` | SAW pattern Argo CD namespace (status) |
| `SAW_NS` | `openshell-agents` | SAW namespace |
| `CSV` | `clusters.csv` | credentials file |

If the SAW fork changes its Argo CD instance namespace, update `SAW_GITOPS_NS`
here and the `saw_gitops_namespace` attribute in both Antora `antora.yml`
files (parity-checked by `npm run validate:docs`).
