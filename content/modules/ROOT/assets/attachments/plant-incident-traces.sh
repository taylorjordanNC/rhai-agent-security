#!/usr/bin/env bash
# plant-incident-traces.sh — facilitator script for Module 7 (SRE Copilot Capstone).
#
# Plants the agent-session traces of a *prior* incident response (INC-4127)
# into the RHOAI MLflow experiment the traces specialist (`traces`, running
# hermes) searches during the module. The traces tell the same story arc the
# live incident loop in Exercise 4 replays: detect -> quantify -> audit ->
# synthesize -> root cause -> recommend -> human approval -> verify recovery.
#
# Runs on the Secure Agent Workspace VM (or anywhere that can reach the
# telemetry proxy and has an OCP bearer token with MLflow API access).
#
# Usage:
#   OCP_TOKEN="$(oc whoami -t)" ./plant-incident-traces.sh
#
# Optional environment overrides:
#   TELEMETRY_PROXY_URL  default http://telemetry-proxy.openshell-agents.svc.cluster.local:8081
#   MLFLOW_WORKSPACE     default openshell
#   EXPERIMENT_NAME      default sre-copilot-fleet
#   INCIDENT_ID          default INC-4127
#   INCIDENT_AGE_MIN     default 180 (how long ago the planted incident ran)
#   KEEP_PAYLOADS        default 0 (1 = keep generated OTLP JSON for inspection)
set -euo pipefail

TELEMETRY_PROXY_URL="${TELEMETRY_PROXY_URL:-http://telemetry-proxy.openshell-agents.svc.cluster.local:8081}"
MLFLOW_WORKSPACE="${MLFLOW_WORKSPACE:-openshell}"
EXPERIMENT_NAME="${EXPERIMENT_NAME:-sre-copilot-fleet}"
INCIDENT_ID="${INCIDENT_ID:-INC-4127}"
INCIDENT_AGE_MIN="${INCIDENT_AGE_MIN:-180}"
KEEP_PAYLOADS="${KEEP_PAYLOADS:-0}"

: "${OCP_TOKEN:?OCP_TOKEN is required (e.g. OCP_TOKEN=\$(oc whoami -t) $0)}"

WORKDIR="$(mktemp -d /tmp/plant-traces.XXXXXX)"
trap '[[ "$KEEP_PAYLOADS" == "1" ]] || rm -rf "$WORKDIR"' EXIT

log() { printf '[plant-traces] %s\n' "$*"; }
die() { printf '[plant-traces] ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Health checks: proxy reachable, MLflow answering, experiment present.
# ---------------------------------------------------------------------------
log "checking telemetry proxy -> $TELEMETRY_PROXY_URL"
HEALTH_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  "$TELEMETRY_PROXY_URL/mlflow/health")" || die "telemetry proxy unreachable"
[[ "$HEALTH_CODE" == "200" ]] || die "MLflow health check returned HTTP $HEALTH_CODE"

log "resolving experiment '$EXPERIMENT_NAME' in workspace '$MLFLOW_WORKSPACE'"
EXPERIMENT_JSON="$(curl -s --max-time 10 \
  -H "Authorization: Bearer $OCP_TOKEN" \
  -H "X-MLFLOW-WORKSPACE: $MLFLOW_WORKSPACE" \
  "$TELEMETRY_PROXY_URL/mlflow/api/2.0/mlflow/experiments/get-by-name?experiment_name=$EXPERIMENT_NAME")"
EXPERIMENT_ID="$(printf '%s' "$EXPERIMENT_JSON" | jq -r '.experiment.experiment_id // empty')"
[[ -n "$EXPERIMENT_ID" ]] || die "experiment '$EXPERIMENT_NAME' not found: $EXPERIMENT_JSON"
log "experiment id: $EXPERIMENT_ID"

# ---------------------------------------------------------------------------
# 2. Idempotency: remove any previous planting of this incident so a re-run
#    leaves exactly one copy of the story.
# ---------------------------------------------------------------------------
log "removing any previous planting of incident '$INCIDENT_ID'"
PRIOR_SEARCH="$(curl -s --max-time 15 -X POST \
  -H "Authorization: Bearer $OCP_TOKEN" \
  -H "X-MLFLOW-WORKSPACE: $MLFLOW_WORKSPACE" \
  -H "Content-Type: application/json" \
  -d "{\"locations\":[{\"mlflow_experiment\":{\"experiment_id\":\"$EXPERIMENT_ID\"}}],\"max_results\":200,\"filter\":\"tags.\\\"incident.id\\\" = '$INCIDENT_ID'\"}" \
  "$TELEMETRY_PROXY_URL/mlflow/api/3.0/mlflow/traces/search")"
PRIOR_IDS="$(printf '%s' "$PRIOR_SEARCH" | jq -c '[.traces[]?.trace_id] // []')"
PRIOR_COUNT="$(printf '%s' "$PRIOR_IDS" | jq 'length')"
if [[ "$PRIOR_COUNT" -gt 0 ]]; then
  curl -s -o /dev/null -w '' --max-time 15 -X POST \
    -H "Authorization: Bearer $OCP_TOKEN" \
    -H "X-MLFLOW-WORKSPACE: $MLFLOW_WORKSPACE" \
    -H "Content-Type: application/json" \
    -d "{\"experiment_id\":\"$EXPERIMENT_ID\",\"request_ids\":$PRIOR_IDS}" \
    "$TELEMETRY_PROXY_URL/mlflow/api/2.0/mlflow/traces/delete-traces"
  log "removed $PRIOR_COUNT previously planted trace(s)"
fi

# ---------------------------------------------------------------------------
# 3. Generate the incident-story OTLP payloads with relative timestamps.
#    Trace ids are 32-hex, span ids 16-hex; times are unix nano strings.
# ---------------------------------------------------------------------------
python3 - "$WORKDIR" "$INCIDENT_ID" "$INCIDENT_AGE_MIN" <<'PYGEN'
import json, os, secrets, sys, time

workdir, incident_id, age_min = sys.argv[1], sys.argv[2], int(sys.argv[3])
now_ns = time.time_ns()
ago = lambda minutes: str(now_ns - minutes * 60 * 1000_000_000)

def span(trace_id, span_id, name, start, end, attributes=None, parent=None):
    s = {
        "traceId": trace_id, "spanId": span_id, "name": name,
        "kind": 1, "startTimeUnixNano": start, "endTimeUnixNano": end,
        "attributes": [
            {"key": k, "value": {"stringValue": v}} for k, v in (attributes or {}).items()
        ],
        "status": {"code": 1},
    }
    if parent:
        s["parentSpanId"] = parent
    return s

# (root span, service.name, agent role, incident state, start_min, end_min, [tool spans])
STORY = [
    ("incident-alert-triage", "sre-fleet-metrics", "metrics", "detected",
     [("tool:prom.query", "up{namespace=\"demo\"}", 179, 178),
      ("tool:prom.query", "alertmanager_alerts{alertname=\"ShopUnavailable\"}", 178, 177)],
     180, 176),
    ("quantify-replica-collapse", "sre-fleet-metrics", "metrics", "investigating",
     [("tool:prom.query", "kube_deployment_status_replicas_available{deployment=\"shop\"}", 177, 176),
      ("tool:prom.query", "kube_deployment_spec_replicas{deployment=\"shop\"}", 176, 175)],
     177, 173),
    ("audit-fleet-actions", "sre-fleet-traces", "traces", "investigating",
     [("tool:mlflow.search-traces", "service.name = sre-fleet-metrics", 175, 174),
      ("tool:mlflow.get-trace", "drill into the replica-collapse query", 174, 173)],
     175, 171),
    ("synthesize-findings", "sre-fleet-analyst", "analyst", "investigating",
     [("tool:report.write", "combine metrics + trace findings", 173, 171)],
     173, 170),
    ("root-cause-analysis", "sre-fleet-metrics", "metrics", "investigating",
     [("tool:prom.query", "kube_pod_container_status_waiting_reason", 170, 169),
      ("tool:prom.query", "kube_deployment_status_conditions", 169, 168),
      ("tool:prom.query", "kube_replicaset_status", 168, 167)],
     170, 166),
    ("recommend-remediation", "sre-fleet-analyst", "analyst", "remediation-proposed",
     [("tool:report.write", "recommendation: scale shop back to 2 replicas", 166, 164)],
     166, 163),
    ("human-approval", "sre-fleet-ops", "ops", "remediation-approved",
     [("decision:approve", "operator confirmed scale-up via incident console", 162, 161)],
     162, 159),
    ("verify-recovery", "sre-fleet-metrics", "metrics", "resolved",
     [("tool:prom.query", "kube_deployment_status_replicas_available{deployment=\"shop\"}", 159, 158)],
     159, 155),
]

manifest = []
for root, service, role, state, tools, start_min, end_min in STORY:
    trace_id = secrets.token_hex(16)
    root_span_id = secrets.token_hex(8)
    root_start = ago(start_min)
    root_end = ago(end_min)
    spans = [span(trace_id, root_span_id, root, root_start, root_end, {
        "service.name": service,
        # Root-span attributes prefixed "mlflow.traceTag." are promoted to
        # trace-level tags by the MLflow OTLP ingest — these are the keys the
        # traces agent searches by.
        "mlflow.traceTag.agent.role": role,
        "mlflow.traceTag.incident.id": incident_id,
        "mlflow.traceTag.incident.severity": "sev2",
        "mlflow.traceTag.incident.state": state,
    })]
    cursor = start_min
    for tool_name, tool_detail, t_start, t_end in tools:
        spans.append(span(trace_id, secrets.token_hex(8), tool_name,
                          ago(t_start), ago(t_end),
                          {"tool.detail": tool_detail, "incident.id": incident_id},
                          parent=root_span_id))
        cursor = t_end
    payload = {"resourceSpans": [{
        "resource": {"attributes": [{"key": "service.name",
                                     "value": {"stringValue": service}}]},
        "scopeSpans": [{"scope": {"name": "sre-copilot-fleet"}, "spans": spans}],
    }]}
    path = os.path.join(workdir, f"{start_min:03d}-{root}.json")
    with open(path, "w") as f:
        json.dump(payload, f)
    manifest.append({"root": root, "service": service, "role": role,
                     "state": state, "path": path})

with open(os.path.join(workdir, "manifest.json"), "w") as f:
    json.dump(manifest, f)
print(f"{len(manifest)} payloads written to {workdir}")
PYGEN
log "generated incident-story payloads (times end ${INCIDENT_AGE_MIN}-155 min ago)"

# ---------------------------------------------------------------------------
# 3. Ingest every trace via the OTLP endpoint through the telemetry proxy.
# ---------------------------------------------------------------------------
INGESTED=0
FAILED=0
for payload in "$WORKDIR"/*.json; do
  [[ "$(basename "$payload")" == "manifest.json" ]] && continue
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
    -H "Authorization: Bearer $OCP_TOKEN" \
    -H "X-MLFLOW-WORKSPACE: $MLFLOW_WORKSPACE" \
    -H "x-mlflow-experiment-id: $EXPERIMENT_ID" \
    -H "Content-Type: application/json" \
    --data-binary "@$payload" \
    "$TELEMETRY_PROXY_URL/v1/traces")" || CODE="000"
  if [[ "$CODE" == "200" ]]; then
    INGESTED=$((INGESTED + 1))
  else
    FAILED=$((FAILED + 1))
    log "WARN: $(basename "$payload") -> HTTP $CODE"
  fi
done
log "ingested $INGESTED traces, $FAILED failures"
[[ "$FAILED" == "0" ]] || die "$FAILED trace(s) failed to ingest"

# ---------------------------------------------------------------------------
# 4. Verify: search the planted incident back out the way hermes will.
# ---------------------------------------------------------------------------
log "verifying with an incident-tag search (as the traces agent will)"
SEARCH_BODY="{\"locations\":[{\"mlflow_experiment\":{\"experiment_id\":\"$EXPERIMENT_ID\"}}],\"max_results\":20,\"order_by\":[\"timestamp DESC\"],\"filter\":\"tags.\\\"incident.id\\\" = '$INCIDENT_ID'\"}"
SEARCH_RESULT="$(curl -s --max-time 15 -X POST \
  -H "Authorization: Bearer $OCP_TOKEN" \
  -H "X-MLFLOW-WORKSPACE: $MLFLOW_WORKSPACE" \
  -H "Content-Type: application/json" \
  -d "$SEARCH_BODY" \
  "$TELEMETRY_PROXY_URL/mlflow/api/3.0/mlflow/traces/search")"

FOUND="$(printf '%s' "$SEARCH_RESULT" | jq -r '.traces | length // 0')"
[[ "$FOUND" -ge 8 ]] || die "verification search found only $FOUND trace(s): $SEARCH_RESULT"

printf '\n[plant-traces] planted incident %s — %s trace(s) verified searchable\n\n' "$INCIDENT_ID" "$FOUND"
printf '%s\n' "$SEARCH_RESULT" | jq -r '.traces[] | "  \(.tags["service.name"] // "?")  \(.tags["incident.state"] // "?")  \(.trace_id)"'
printf '\n[plant-traces] the traces agent can now search: tags."incident.id" = '"'"'%s'"'"'\n' "$INCIDENT_ID"

# ---------------------------------------------------------------------------
# 5. Stage the participant hand-off files inside the traces sandbox so the
#    module's search step is a single exec command: the exact search payload
#    and the OCP token the agent needs for plain-language queries.
# ---------------------------------------------------------------------------
TRACES_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E -- '-traces-[0-9a-f-]+$' | head -1)"
if [[ -n "$TRACES_CONTAINER" ]]; then
  printf '%s\n' "$SEARCH_BODY" | docker exec -i "$TRACES_CONTAINER" \
    sh -c 'cat > /tmp/incident-search.json && chmod 644 /tmp/incident-search.json'
  printf '%s\n' "$OCP_TOKEN" | docker exec -i "$TRACES_CONTAINER" \
    sh -c 'cat > /tmp/mlflow.token && chmod 644 /tmp/mlflow.token'
  # A small sample session trace the participant ingests themselves in the
  # module, then searches back by its tag — a complete write+read round trip.
  printf '%s\n' "$(python3 - "$INCIDENT_ID" <<'PYSAMPLE'
import json, secrets, sys, time
now_ns = time.time_ns()
trace_id, span_id = secrets.token_hex(16), secrets.token_hex(8)
payload = {"resourceSpans": [{
    "resource": {"attributes": [{"key": "service.name",
                                 "value": {"stringValue": "workshop-participant"}}]},
    "scopeSpans": [{"scope": {"name": "sre-copilot-fleet"}, "spans": [{
        "traceId": trace_id, "spanId": span_id,
        "name": "participant-session", "kind": 1,
        "startTimeUnixNano": str(now_ns - 5_000_000_000),
        "endTimeUnixNano": str(now_ns),
        "attributes": [
            {"key": "service.name", "value": {"stringValue": "workshop-participant"}},
            {"key": "mlflow.traceTag.session.demo", "value": {"stringValue": "participant"}},
            {"key": "mlflow.traceTag.incident.id", "value": {"stringValue": sys.argv[1]}},
        ],
        "status": {"code": 1},
    }]}],
}]}
print(json.dumps(payload))
PYSAMPLE
)" | docker exec -i "$TRACES_CONTAINER" \
    sh -c 'cat > /tmp/agent-session-trace.json && chmod 644 /tmp/agent-session-trace.json'
  log "staged /tmp/incident-search.json, /tmp/mlflow.token and /tmp/agent-session-trace.json in sandbox $TRACES_CONTAINER"
else
  log "WARN: traces sandbox container not found; skip staging (search payload kept at $WORKDIR/search-body.json)"
  printf '%s\n' "$SEARCH_BODY" > "$WORKDIR/search-body.json"
fi
