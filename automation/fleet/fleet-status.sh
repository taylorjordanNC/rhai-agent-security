#!/usr/bin/env bash
# Fleet SAW status — read-only poll of the SAW pattern and workshop resources
# per cluster (or the current cluster with --current). Changes nothing.
#
# Usage:
#   ./fleet-status.sh [--csv FILE] [--current] [--gate]
#
#   --current   check only the current oc context (single-cluster check)
#   --gate      pre-flight: exit non-zero if any cluster's Argo CD
#               Applications are not all Synced/Healthy — run before
#               participants arrive
#
# CSV rows: name,server,username,password[,token] — an optional 5th token
# column logs in with a bearer token instead of username/password.
#
# Environment overrides (single knobs for fork coupling):
#   SAW_GITOPS_NS   namespace holding the SAW pattern Argo CD Applications (default vp-gitops)
#   SAW_NS          SAW namespace (default openshell-agents)
#   SETUP_JOB       SAW setup Job name (default openshell-saw-setup)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV="${CSV:-$SCRIPT_DIR/clusters.csv}"
SAW_GITOPS_NS="${SAW_GITOPS_NS:-openshift-gitops}"
SAW_NS="${SAW_NS:-openshell-agents}"
SETUP_JOB="${SETUP_JOB:-openshell-saw-setup}"
CURRENT=0
GATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current) CURRENT=1; shift ;;
    --gate) GATE=1; shift ;;
    --csv) CSV="$2"; shift 2 ;;
    --help|-h) grep -E '^# (Usage:|  --)' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# First argument: label. Remaining args: run as a subshell command list.
section() { printf '\n== %s ==\n' "$1"; }

check_one() { # label  (uses the current oc context; caller logged in)
  local label="$1"
  printf '\n----- %s -----\n' "$label"
  section "Argo CD Applications ($SAW_GITOPS_NS)"
  oc get applications.argoproj.io -n "$SAW_GITOPS_NS" -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>/dev/null || \
    echo "  (no Applications or no access)"
  section "SAW VM + setup Job ($SAW_NS)"
  oc get vmi -n "$SAW_NS" -o custom-columns='VMI:.metadata.name,PHASE:.status.phase' 2>/dev/null || true
  oc get "job/$SETUP_JOB" -n "$SAW_NS" -o custom-columns='JOB:.metadata.name,STATUS:.status.conditions[0].type,DURATION:.status.startTime' 2>/dev/null \
    || echo "  setup Job not present yet"
  section "Workshop namespaces"
  oc get ns demo openshell "$SAW_NS" --no-headers 2>/dev/null || true
}

gate_check() { # uses the current oc context; 0 = cluster passes the gate
  # Fail-closed: a failed or empty query means the cluster does NOT pass.
  local apps total bad
  apps=$(oc get applications.argoproj.io -n "$SAW_GITOPS_NS" -o custom-columns='S:.status.sync.status,H:.status.health.status' --no-headers 2>/dev/null) || true
  if [[ -z "$apps" ]]; then
    echo "  [gate] FAIL — no Argo CD Applications in $SAW_GITOPS_NS (or the query failed)"
    return 1
  fi
  total=$(echo "$apps" | wc -l | tr -d ' ')
  # oc custom-columns pads columns to fixed width — match on any whitespace.
  # OutOfSync+Healthy passes: the SAW pattern and the workshop chart both
  # manage parity-declared objects (rhods-operator, kubevirt-hyperconverged),
  # so expected annotation drift keeps those apps OutOfSync while Healthy —
  # that churn is the ignoreDifferences design, not a broken install.
  bad=$(echo "$apps" | grep -cvE '^(Synced|OutOfSync)[[:space:]]+Healthy$' || true)
  if [[ "$bad" -gt 0 ]]; then
    echo "  [gate] FAIL — $bad of $total Argo CD Applications not Healthy"
    return 1
  fi
  if ! oc get ns demo openshell "$SAW_NS" >/dev/null 2>&1; then
    echo "  [gate] FAIL — workshop namespaces missing"
    return 1
  fi
  echo "  [gate] PASS"
}

if [[ $CURRENT -eq 1 ]]; then
  check_one "$(oc whoami --show-server 2>/dev/null || echo current)"
  if [[ $GATE -eq 1 ]]; then
    gate_check || exit 1
  fi
  exit 0
fi

[[ -f "$CSV" ]] || { echo "Credentials CSV not found: $CSV (use --current for the current context)" >&2; exit 1; }
command -v oc >/dev/null 2>&1 || { echo "oc not found" >&2; exit 1; }

# Preserve the caller's login across the poll.
PREV_SERVER="$(oc whoami --show-server 2>/dev/null || true)"
PREV_USER="$(oc whoami 2>/dev/null || true)"

ROWS=()
while IFS= read -r row; do
  case "$row" in
    \#*|"") continue ;;
    name,server*) continue ;; # header row
    *) ROWS+=("$row") ;;
  esac
done < "$CSV"
[[ ${#ROWS[@]} -gt 0 ]] || { echo "No cluster rows in $CSV" >&2; exit 1; }

GATE_FAILED=0
for row in "${ROWS[@]}"; do
  IFS=, read -r name server user password token <<<"$row"
  if [[ -n "${token:-}" ]]; then
    LOGIN_OK=1
    oc login "$server" --token="$token" --insecure-skip-tls-verify >/dev/null 2>&1 || LOGIN_OK=0
  else
    oc login "$server" --username="$user" --password="$password" --insecure-skip-tls-verify >/dev/null 2>&1 && LOGIN_OK=1 || LOGIN_OK=0
  fi
  if [[ $LOGIN_OK -eq 1 ]]; then
    check_one "$name"
    if [[ $GATE -eq 1 ]]; then
      gate_check || GATE_FAILED=$((GATE_FAILED+1))
    fi
  else
    printf '\n----- %s -----\n  login failed for %s\n' "$name" "$server"
    [[ $GATE -eq 1 ]] && GATE_FAILED=$((GATE_FAILED+1))
  fi
done

# Restore the caller's previous context.
if [[ -n "${PREV_SERVER:-}" && -n "${PREV_USER:-}" ]]; then
  oc login "$PREV_SERVER" --username="$PREV_USER" --insecure-skip-tls-verify >/dev/null 2>&1 || true
fi

if [[ $GATE -eq 1 ]]; then
  if [[ $GATE_FAILED -gt 0 ]]; then
    echo "GATE FAILED: $GATE_FAILED of ${#ROWS[@]} cluster(s) not ready for participants" >&2
    exit 1
  fi
  echo "GATE PASSED: all ${#ROWS[@]} cluster(s) ready for participants"
fi
