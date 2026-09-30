# NeMo Guardrails Helm Chart

Deploys a [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails) server on OpenShift AI using the TrustyAI operator.

## Prerequisites

- OpenShift AI with the **TrustyAI** operator installed
- A running LLM inference endpoint (e.g. a KServe InferenceService serving a model via vLLM)

## What Gets Deployed

| Resource | Template | Description |
|----------|----------|-------------|
| `NemoGuardrails` CR | `nemo-guardrails.yaml` | The guardrails server — the TrustyAI operator manages the underlying Deployment, Service, and ServiceAccount |
| `ConfigMap` | `nemo-guardrails-config.yaml` | Contains `config.yaml` (model + rails config) and `rails.co` (Colang flows) |
| `Secret` | `nemo-guardrails-secret.yaml` | LLM API key credentials (created only when `llm.apiKey` is set) |
| `ServingRuntime` + `InferenceService` | `nemo-guardrails-model.yaml` | Optional content safety detector model (gated by `contentSafety.deploy`) |

## Installation

```bash
helm install nemo-guardrails . -n <namespace>
```

To upgrade after changing values:

```bash
helm upgrade nemo-guardrails . -n <namespace>
```

Note: Helm discards values supplied at install time when an upgrade introduces
any new `--set` flag. Repeat the full model connection on every upgrade
(`--set llm.baseUrl=... --set llm.modelName=... --set llm.apiKey=...`).

## RBAC

The TrustyAI operator automatically creates:

- A `ServiceAccount` named `<cr-name>-serviceaccount` (e.g. `nemo-guardrails-serviceaccount`)
- A `RoleBinding` granting `view` ClusterRole in the deployment namespace

No additional RBAC is needed in this chart. The guardrails server communicates with the LLM via its in-cluster HTTP service URL (e.g. `http://<model>-predictor.<namespace>.svc.cluster.local/v1`), which does not require cross-namespace RBAC — Kubernetes allows cross-namespace HTTP by default unless restricted by NetworkPolicies.

## Configuration

All values are at the top level in `values.yaml` (not nested). Key fields:

| Value | Description |
|-------|-------------|
| `name` | Name of the NemoGuardrails CR and related resources |
| `llm.baseUrl` | OpenAI-compatible LLM endpoint (in-cluster predictor URL or remote MaaS gateway) |
| `llm.modelName` | Served model name |
| `llm.engine` | LLM engine type (typically `openai`) |
| `llm.apiKey` | API key for the endpoint — supplied at install time, never committed. If set, the chart creates a `<name>-llm-credentials` Secret and injects the key as `llm.apiKeyEnvVar` into the guardrails pod |
| `llm.apiKeyEnvVar` | Environment variable name carrying the API key (default `OPENAI_API_KEY`) |
| `llm.apiKeySecretName` | Alternatively, reference an existing Secret containing an `api-key` key (injected via `valueFrom.secretKeyRef` — verify the TrustyAI operator passes it through before relying on it) |
| `config` | Raw `config.yaml` content — models, rails, regex patterns, sensitive data detection |
| `colang` | Raw Colang flow definitions |
| `contentSafety.deploy` | Set `true` to deploy the NemoGuard content safety detector model (requires GPU) |
| `contentSafety.modelUri` | OCI URI for the content safety model weights |
| `llamaGuard.enabled` | Set `true` to wire a remote Llama Guard model into the rails (no GPU needed): adds a `llama_guard` model entry, the `llama guard check` flows, and the moderation prompts to the rendered config |
| `llamaGuard.baseUrl` | OpenAI-compatible endpoint serving the Llama Guard model. Placeholder by default; set it at upgrade time together with `llamaGuard.apiKey` (your facilitator provides both) |
| `llamaGuard.modelName` | Served Llama Guard model name (default `Llama-Guard-3-1B`) |
| `llamaGuard.apiKey` | API key for the Llama Guard endpoint — supplied at install time, never committed. If set (with `enabled`), the chart creates a `<name>-llama-guard-credentials` Secret and injects the key as `llamaGuard.apiKeyEnvVar` |
| `llamaGuard.apiKeyEnvVar` | Environment variable name carrying the Llama Guard API key (default `LLAMA_GUARD_API_KEY`) |

The `config` and `colang` values are rendered as Helm templates, so they can
reference chart values (the default `config` wires the model section to
`llm.engine`, `llm.baseUrl`, and `llm.modelName`). Escape literal `{{ }}` as
`{{`{{`}}` when pasting content that contains Go template syntax.

### Supplying your own API key

Do not commit API keys to `values.yaml`. Supply the key at install time:

```bash
export LLM_API_KEY='<your MaaS API key>'
helm install nemo-guardrails . -n <namespace> \
  --set llm.apiKey="$LLM_API_KEY"
```

The key is stored in the `<name>-llm-credentials` Secret and injected into the
guardrails pod as `OPENAI_API_KEY`. It is also visible in the NemoGuardrails CR
spec and pod spec; on shared clusters, pre-create the Secret yourself and set
`llm.apiKeySecretName` instead. When no key is set, the chart injects
`OPENAI_API_KEY=unused`, which suits in-cluster endpoints without auth.

## Environment Variables

The NemoGuardrails CR injects these env vars into the guardrails pod:

- `OPENAI_API_KEY` — the LLM API key (from `llm.apiKey` or the Secret named by `llm.apiKeySecretName`), or `"unused"` when no key is set (required by the NeMo Guardrails runtime even when not using OpenAI)
- `PYTHONHTTPSVERIFY=0` — disables Python TLS verification for in-cluster communication
- `MAIN_MODEL_BASE_URL` — points to the LLM endpoint
- `MAIN_MODEL_ENGINE` — engine type for the guardrails runtime

## References

- [NeMo Guardrails documentation](https://docs.nvidia.com/nemo/guardrails/latest/index.html)
- [TrustyAI operator on OpenShift AI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/latest/html/serving_models/nvidia-nim-guardrails_model-serving)
- [NeMo Guardrails GitHub](https://github.com/NVIDIA/NeMo-Guardrails)
- [Colang language reference](https://docs.nvidia.com/nemo/guardrails/latest/colang-2/overview.html)
