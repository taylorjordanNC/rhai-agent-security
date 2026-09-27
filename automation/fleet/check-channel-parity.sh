#!/usr/bin/env bash
# RHOAI channel parity guard.
#
# The workshop (automation/argocd/capstone/50-rhods-operator.yaml) and the SAW
# fork (values-prod.yaml, the `openshift-ai` subscription) both declare the
# RHOAI operator subscription, and both paths self-heal the same object. They
# only stay stable while the specs match — a channel bumped in one repo and
# not the other would flap Argo sync forever. Run this before pushing either
# change (CI or a pre-push hook; same philosophy as `npm run validate:docs`).
#
# Environment overrides:
#   WORKSHOP_FILE  workshop Subscription manifest (default: resolved from this script)
#   FORK_FILE      SAW fork values-prod.yaml (default: $SAW_DIR/values-prod.yaml)
#   SAW_DIR        SAW fork checkout (default ~/git/secure-agent-workspace)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSHOP_FILE="${WORKSHOP_FILE:-$SCRIPT_DIR/../argocd/capstone/50-rhods-operator.yaml}"
FORK_FILE="${FORK_FILE:-${SAW_DIR:-$HOME/git/secure-agent-workspace}/values-prod.yaml}"

[[ -f "$WORKSHOP_FILE" ]] || { echo "Workshop manifest not found: $WORKSHOP_FILE" >&2; exit 1; }
[[ -f "$FORK_FILE" ]] || { echo "SAW fork values not found: $FORK_FILE (set FORK_FILE or SAW_DIR)" >&2; exit 1; }

# Workshop: the channel under the Subscription document.
ch_workshop=$(awk '/^kind: Subscription/{f=1} f && /^  channel:/{print $2; exit}' "$WORKSHOP_FILE")
# Fork: the channel under the openshift-ai subscription block.
ch_fork=$(awk '/^    openshift-ai:/{f=1} f && /^      channel:/{print $2; exit}' "$FORK_FILE")

[[ -n "$ch_workshop" ]] || { echo "No Subscription channel found in $WORKSHOP_FILE" >&2; exit 1; }
[[ -n "$ch_fork" ]] || { echo "No openshift-ai channel found in $FORK_FILE" >&2; exit 1; }

if [[ "$ch_workshop" == "$ch_fork" ]]; then
  echo "RHOAI channel parity OK: $ch_workshop"
  exit 0
fi

echo "RHOAI CHANNEL PARITY FAILED: workshop=$ch_workshop fork=$ch_fork" >&2
echo "Two self-healing managers on one Subscription require identical specs —" >&2
echo "bump the channel in BOTH repos or the Argo sync flaps forever." >&2
exit 1
