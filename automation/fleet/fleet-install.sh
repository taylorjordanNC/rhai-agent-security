#!/usr/bin/env bash
# Fleet SAW installer — the SAW fork's documented install procedure, looped
# over the clusters in a credentials CSV.
#
# This script adds no cluster logic of its own: it calls the fork's documented
# entry points verbatim (make copy-images, ./pattern.sh make install, the HCO
# software-emulation loop) so fork updates flow through unchanged. If the
# fork's procedure changes, update only this script's per-cluster function.
#
# Usage:
#   ./fleet-install.sh [options]
#
# Options:
#   --csv FILE        credentials CSV (default: clusters.csv next to this script)
#                     rows: name,server,username,password[,token] — an optional
#                     5th token column logs in with a bearer token instead of
#                     username/password (token takes precedence when present).
#   --jobs N          parallel clusters (default 1). Parallel workers each get
#                     their own fork clone — the framework writes state in the
#                     checkout, so one clone cannot serve two clusters.
#   --wait            after each install, wait for the SAW setup Job to
#                     complete (default: apply-and-move-on; the VM setup runs
#                     in-cluster for up to ~3h — poll with fleet-status.sh)
#   --only NAME       bootstrap ONE cluster (the facilitator remedy): install,
#                     then block until the workshop Application
#                     (module-7-prereqs) is Synced/Healthy — participants
#                     proceed the moment this returns
#   --no-emulation    skip the HCO software-emulation step (KVM-capable clusters)
#   --dry-run         print the per-cluster plan without logging in or installing#
# Shared one-time assets (created once, reused for every cluster):
#   SAW_DIR   fork checkout   (default ~/git/secure-agent-workspace)
#   SAW_REF   fork revision   (default saw-emulation-fixes)
#   ~/values-secret.yaml      secret values file (see the SAW install doc)
#
# Requires podman on this host (pattern.sh). Never commit the credentials CSV.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV="${CSV:-$SCRIPT_DIR/clusters.csv}"
SAW_DIR="${SAW_DIR:-$HOME/git/secure-agent-workspace}"
SAW_REPO_URL="${SAW_REPO_URL:-https://github.com/taylorjordanNC/secure-agent-workspace.git}"
SAW_REF="${SAW_REF:-saw-emulation-fixes}"
SAW_GITOPS_NS="${SAW_GITOPS_NS:-openshift-gitops}"
SAW_NS="${SAW_NS:-openshell-agents}"
SETUP_JOB="${SETUP_JOB:-openshell-saw-setup}"
WORKSHOP_APP="${WORKSHOP_APP:-module-7-prereqs}"
FLEET_KC_DIR="${FLEET_KC_DIR:-$HOME/.saw-fleet}"

JOBS=1
WAIT=0
EMULATION=1
DRY_RUN=0
ONLY=""

usage() { grep -E '^# (Usage:|Options:|  --)' "$0" | sed 's/^# \{0,2\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --csv) CSV="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --wait) WAIT=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --no-emulation) EMULATION=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

[[ -f "$CSV" ]] || { echo "Credentials CSV not found: $CSV" >&2; echo "Copy clusters.csv.example to clusters.csv and fill it in." >&2; exit 1; }
[[ -d "$SAW_DIR/.git" ]] || { echo "SAW checkout not found: $SAW_DIR (set SAW_DIR)" >&2; exit 1; }
if [[ $JOBS -gt 1 ]]; then
  command -v git >/dev/null 2>&1 || { echo "git required for parallel workers" >&2; exit 1; }
fi

# --- per-cluster steps (the ONLY fork-coupled logic) -------------------------

worker_dir() { # one fork clone per worker for parallel installs
  local n="$1"
  if [[ $JOBS -le 1 ]]; then printf '%s' "$SAW_DIR"; return; fi
  local d="$SCRIPT_DIR/.workers/worker-$n"
  if [[ ! -d "$d/.git" ]]; then
    git clone --branch "$SAW_REF" "$SAW_REPO_URL" "$d" >/dev/null 2>&1
  fi
  printf '%s' "$d"
}

worker_dir_print() { # side-effect-free path for --dry-run (no clone)
  local n="$1"
  if [[ $JOBS -le 1 ]]; then printf '%s' "$SAW_DIR"; return; fi
  printf '%s' "$SCRIPT_DIR/.workers/worker-$n"
}

ensure_emulation() { # fork-documented HCO loop; idempotent
  # 45 min: fresh clusters provision the CNV operator and its HCO slower than
  # the pattern install returns — 20 min skipped emulation on a non-KVM host,
  # which leaves the VM unable to start.
  local deadline=$((SECONDS + 2700))
  until oc get hco kubevirt-hyperconverged -n openshift-cnv >/dev/null 2>&1; do
    (( SECONDS > deadline )) && { echo "  [$1] HCO never appeared; skipping emulation" >&2; return 1; }
    echo "  [$1] Waiting for the HyperConverged resource..."
    sleep 15
  done
  local current
  current=$(oc get kubevirt kubevirt-kubevirt-hyperconverged -n openshift-cnv \
    -o jsonpath='{.spec.configuration.developerConfiguration.useEmulation}' 2>/dev/null || true)
  if [[ "$current" == "true" ]]; then
    echo "  [$1] Software emulation already enabled"
    return 0
  fi
  local patch='[{"op":"add","path":"/spec/configuration/developerConfiguration/useEmulation","value":true}]'
  oc annotate hco kubevirt-hyperconverged -n openshift-cnv \
    "kubevirt.kubevirt.io/jsonpatch=$patch" --overwrite >/dev/null
  echo "  [$1] Software emulation enabled"
}

wait_for_setup_job() {
  local name="$1" deadline=$((SECONDS + 11100)) # 3h05m: setup Job deadline (10800s) + margin
  echo "  [$name] Waiting for the SAW setup Job (up to ~3h; poll fleet-status.sh instead)..."
  until oc get "job/$SETUP_JOB" -n "$SAW_NS" >/dev/null 2>&1; do
    (( SECONDS > deadline )) && return 1
    sleep 30
  done
  oc -n "$SAW_NS" wait --for=condition=complete "job/$SETUP_JOB" --timeout="${deadline}s" >/dev/null 2>&1 \
    && echo "  [$name] SAW setup Job complete" \
    || { echo "  [$name] SAW setup Job did not complete in time (check fleet-status.sh)" >&2; return 1; }
}

wait_for_workshop_app() { # --only remedy: block until the workshop child converges
  local deadline=$((SECONDS + 1800)) # 30 min: DSC + MLflow + waves 0-4 + PostSync seed
  echo "  [remedy] Waiting for application/$WORKSHOP_APP to converge (up to 30 min; poll fleet-status.sh instead)..."
  until oc get "application/$WORKSHOP_APP" -n "$SAW_GITOPS_NS" -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null | grep -q 'Synced Healthy'; do
    (( SECONDS > deadline )) && { echo "  [remedy] application/$WORKSHOP_APP did not converge in time (check fleet-status.sh)" >&2; return 1; }
    sleep 30
  done
  echo "  [remedy] application/$WORKSHOP_APP Synced and Healthy — participants may proceed"
}

install_cluster() {
  local name="$1" server="$2" user="$3" password="$4" token="$5" worker="$6"
  echo "[$name] $server"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [dry-run] oc login (redacted)"
    echo "  [dry-run] (cd $(worker_dir_print "$worker") && make copy-images)"
    echo "  [dry-run] (cd $(worker_dir_print "$worker") && ./pattern.sh make install)"
    [[ $EMULATION -eq 1 ]] && echo "  [dry-run] HCO software-emulation annotate"
    [[ $WAIT -eq 1 ]] && echo "  [dry-run] wait for job/$SETUP_JOB -n $SAW_NS"
    return 0
  fi
  local dir; dir="$(worker_dir "$worker")"
  # Per-worker kubeconfig: parallel workers must not share ~/.kube/config —
  # `oc login` flips the current context, so two concurrent installs would
  # send each other's helm/oc calls at the wrong cluster. A dedicated file
  # per worker (under HOME, so pattern.sh's bind mount reaches it) isolates
  # each install and leaves the caller's own login untouched.
  local kc; kc="$FLEET_KC_DIR/worker-$worker.kubeconfig"
  mkdir -p "$FLEET_KC_DIR"
  if [[ -n "${token:-}" ]]; then
    oc login "$server" --token="$token" --kubeconfig="$kc" --insecure-skip-tls-verify >/dev/null
  else
    oc login "$server" --username="$user" --password="$password" --kubeconfig="$kc" --insecure-skip-tls-verify >/dev/null
  fi
  export KUBECONFIG="$kc"
  echo "  [$name] Logged in"
  echo "  [$name] Mirroring quickstart images (in-cluster Skopeo)..."
  (cd "$dir" && make copy-images) >/dev/null
  echo "  [$name] Installing the SAW pattern (fork entry point; returns after the pattern GitOps lands)..."
  (cd "$dir" && ./pattern.sh make install) >/dev/null
  if [[ $EMULATION -eq 1 ]]; then
    ensure_emulation "$name" || true
  fi
  if [[ $WAIT -eq 1 ]]; then
    wait_for_setup_job "$name" || true
  fi
  if [[ -n "$ONLY" && $DRY_RUN -eq 0 ]]; then
    # Facilitator remedy: participants need the workshop child green, not just
    # the pattern bootstrap — block until module-7-prereqs is Synced/Healthy.
    wait_for_workshop_app || true
  fi
  if [[ $WAIT -eq 0 && -z "$ONLY" ]]; then
    echo "  [$name] Install submitted. VM setup continues in-cluster (~1-3h); poll fleet-status.sh"
  fi
}

# --- runner ------------------------------------------------------------------

ROWS=()
while IFS= read -r row; do
  case "$row" in
    \#*|"") continue ;;
    name,server*) continue ;; # header row
    *) ROWS+=("$row") ;;
  esac
done < "$CSV"
[[ ${#ROWS[@]} -gt 0 ]] || { echo "No cluster rows in $CSV" >&2; exit 1; }
if [[ -n "$ONLY" ]]; then
  FILTERED=()
  for row in "${ROWS[@]}"; do
    IFS=, read -r name _rest <<<"$row"
    [[ "$name" == "$ONLY" ]] && FILTERED+=("$row")
  done
  [[ ${#FILTERED[@]} -eq 1 ]] || { echo "Cluster '$ONLY' not found in $CSV (exactly one row required)" >&2; exit 1; }
  ROWS=("${FILTERED[@]}")
  JOBS=1 # single cluster — no parallel workers needed
fi
echo "Fleet SAW install: ${#ROWS[@]} cluster(s), jobs=$JOBS, wait=$WAIT, emulation=$EMULATION"

run_one() { # idx, row, worker number
  local idx="$1" row="$2" worker="$3"
  IFS=, read -r name server user password token <<<"$row"
  install_cluster "$name" "$server" "$user" "$password" "${token:-}" "$worker" || \
    echo "  [$name] FAILED — see output above; the script is idempotent, re-run to retry" >&2
}

if [[ $JOBS -le 1 ]]; then
  idx=0
  for row in "${ROWS[@]}"; do
    run_one "$idx" "$row" 1
    idx=$((idx + 1))
  done
else
  # Each worker takes a stride (w, w+JOBS, ...) so no cluster runs twice.
  mkdir -p "$SCRIPT_DIR/.workers"
  w=0
  while [[ $w -lt $JOBS ]]; do
    (
      idx=$w
      while [[ $idx -lt ${#ROWS[@]} ]]; do
        run_one "$idx" "${ROWS[$idx]}" "$((w + 1))"
        idx=$((idx + JOBS))
      done
    ) &
    w=$((w + 1))
  done
  wait
fi

echo "Fleet install pass complete. Check status with: $SCRIPT_DIR/fleet-status.sh"
