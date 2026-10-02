# SAW GitOps (automation/argocd/saw)

ArgoCD app-of-apps scaffold for the Secure Agent Workspace on this workshop's
`openshift-gitops` instance. This is the **Argo path of install**; the
Validated Patterns framework (`pattern.sh make install` from the SAW fork's
values-prod) remains a separate, alternative mechanism. An admin picks one or
the other per cluster — do not run both against one cluster for chart
deployments.

## Repo topology

```
validatedpatterns-sandbox/secure-agent-workspace   upstream (untouched)
        ↑ merge — gated, tested
taylorjordanNC/secure-agent-workspace              fork (workshop branch = what Argo tracks)
        ↑ repoURL chart reference
taylorjordanNC/rhai-agent-security                 this repo (scaffold + site values)
```

- **fork `main`** is a pristine mirror of upstream (fast-forward only; never
  commit to it).
- **fork `workshop`** is the long-lived integration branch: it carries the
  workshop delta (softwareEmulation knob, tavily web search, profile
  decisions) and continuously merges `main`.
- **Tags** (e.g. `workshop-2026.10`) mark cluster-validated versions; pin
  `targetRevision` to a tag for stable releases.
- `automation/argocd/capstone/` (module 7 prereqs) is untouched and keeps
  running alongside; shared objects (openshell-agents namespace, RHOAI
  operator) are capstone-owned and deliberately not declared here.

## Sync waves

    w0 namespaces -> w1 subscriptions -> w2 vault -> w3 vault-config
    -> w4 eso -> w5 openshift-cnv -> w6 pattern-secrets
    -> w7 keycloak + governance -> w8 saw-bom -> w9 saw-users

All SAW charts are referenced by `repoURL` from the fork's `workshop` branch —
upstream merges flow to the cluster on the next Argo sync with no scaffold
changes. Only chart *values contract* changes touch this directory, and those
surface in the fork's test suite first. The vault/eso framework charts are
vendored under `vendor/` (no upstream coupling).

## Deploy

Requires: the fork's `workshop` branch pushed to GitHub, and `oc` admin.

    oc apply -f automation/argocd/saw/root-application.yaml

Then watch the tree converge:

    oc get applications -n openshift-gitops
    oc -n openshift-cnv get csv                  # CNV operator installs
    oc -n openshift-cnv get kubevirt kubevirt-kubevirt-hyperconverged \
      -o jsonpath='{.spec.configuration.developerConfiguration.useEmulation}'

## Seed vault (one-time, after wave 3 converges)

The user provides the secret values — Argo never carries Secret payloads.
Once `saw-vault-config` has initialized + unsealed the vault and configured
the kubernetes auth role:

    oc -n vault port-forward svc/vault 8200:8200 &
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$(oc -n vault get secret vault-init \
      -o jsonpath='{.data.root_token}' | base64 -d)
    # the workshop's shared NGC key pattern: one inference key per cluster
    vault kv put secret/data/hub/inference \
      provider=build model=nvidia/nemotron-3-super-120b-a12b api_key=$NGC_API_KEY
    vault kv put secret/data/hub/web-search \
      provider=tavily api_key=$TAVILY_API_KEY
    vault kv put secret/data/hub/ssh \
      private_key=$'--ssh private key--' public_key=$'--ssh public key--'

The ExternalSecrets (wave 6) pick the values up on their next refresh; the
per-user prepare Jobs (`waitForSecrets: true`) then proceed.

## Teardown

    oc -n openshift-gitops delete application saw-gitops   # prunes the tree
    # OLM subscriptions remain (mirrors the capstone's before-hook-creation
    # policy); delete manually if the cluster is fully going away:
    oc delete subscription -l app.kubernetes.io/part-of=secure-agent-workspace -A
