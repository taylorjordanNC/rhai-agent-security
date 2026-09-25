# Basic OpenShell Workshop Environment

Install OpenShell gateway on OpenShift with no authentication. This is the simplest way to get started and experiment with sandboxed agent runtimes.

## What You Will Learn

- How OpenShell deploys on OpenShift via Helm
- Why sandbox pods need the privileged Security Context Constraint
- How the gateway manages sandbox lifecycle through the Agent Sandbox CRD
- How to create, connect to, and manage sandboxes

## What You'll Build

By the end of this exercise you will have an OpenShell gateway running on OpenShift. The lab connects the `openshell` CLI through `oc port-forward`. You will create a sandboxed runtime and inspect its network, filesystem, and process controls without installing an AI agent or model.

## Architecture

```
+------------------+       +-----------------------+       +------------------+
|                  |  gRPC |                       |  K8s  |                  |
|  openshell CLI   +------>+  OpenShell Gateway     +------>+  Sandbox Pods    |
|  (workstation)   |       |  (StatefulSet)         |       |  (Agent Sandbox) |
|                  |       |                       |       |                  |
+------------------+       +-----------+-----------+       +------------------+
                                       |
                              oc port-forward
                            (default lab path)
```

The gateway runs as a StatefulSet with a 1Gi PVC for its SQLite database. It creates and manages sandbox pods through the Agent Sandbox CRD. The CLI communicates with the gateway over gRPC. The default lab uses a local port-forward because an HTTP OpenShift Route strips required gRPC trailers.

## Prerequisites

- Multinode OpenShift 4.22 cluster with cluster-admin access
- `oc` CLI configured and logged in
- Helm 3.x installed
- `openshell` CLI v0.0.103 installed on your workstation

> **CRD source:** This environment installs the [Red Hat build of Agent Sandbox](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.12/html/deploying_red_hat_build_of_agent_sandbox/) operator via OLM (channel `preview-0.9`). A pre-existing CRD without the expected operator subscription is treated as a stale or incompatible installation.

### Install the openshell CLI

```bash
# From the rhai-agent-security repository root
OPENSHELL_VERSION=0.0.103 ./automation/bootstrap/install-openshell-cli.sh
test "$(openshell --version | awk '{print $NF}')" = "0.0.103"
```

## Quick Start (Automated)

```bash
# Uses a local port-forward for sandbox operations
bash install.sh
```

This installs the gateway resources. Follow the printed commands to start the
port-forward and register the gateway, then continue with sandbox creation.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `NAMESPACE` | `openshell` | OpenShift namespace for all resources |
| `OPENSHELL_VERSION` | `0.0.103` | Helm chart version |
| `OPENSHELL_SANDBOX_IMAGE` | Pinned `base` digest | Default sandbox image |

## Step-by-Step Guide

### Step 1: Install the Agent Sandbox Operator

The Red Hat build of Agent Sandbox provides the `Sandbox` custom resource definition that OpenShell uses to manage sandbox pod lifecycle. Install it via OLM:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: agent-sandbox-operator
  namespace: openshift-operators
spec:
  channel: preview-0.9
  installPlanApproval: Automatic
  name: agent-sandbox-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

Wait for the operator CSV to succeed:

```bash
CSV=$(oc -n openshift-operators get subscription agent-sandbox-operator \
    -o jsonpath='{.status.installedCSV}')
oc -n openshift-operators wait --for=jsonpath='{.status.phase}'=Succeeded \
    csv/"$CSV" --timeout=300s
```

Verify the CRD exists:

```bash
oc get crd sandboxes.agents.x-k8s.io
```

### Step 2: Create the namespace

All OpenShell resources (gateway, sandbox pods) will run in this namespace.

```bash
oc create ns openshell
```

### Step 3: Configure Security Context Constraints

Sandbox pods need the `privileged` SCC because the OpenShell supervisor (which runs inside each sandbox pod as PID 1) sets up:

- **Landlock** - Filesystem access control (restricts which paths the agent can read/write)
- **Seccomp** - System call filtering (blocks dangerous syscalls)
- **Network namespacing** - Runs an HTTP CONNECT proxy to enforce network policy

These security mechanisms require elevated privileges at startup, even though the actual agent process runs as the unprivileged `sandbox` user.

```bash
oc adm policy add-scc-to-user privileged \
    -z openshell-sandbox -n openshell
```

The `openshell-sandbox` ServiceAccount is created by the Helm chart and is used by sandbox pods (not the gateway pod itself).

### Step 4: Create JWT signing keys

The OpenShell gateway uses Ed25519 JWT tokens for sandbox-to-gateway authentication. Normally, the Helm chart includes a PKI init Job that generates these keys, but that Job is not compatible with OpenShift's SCC admission controller.

We create the keys manually instead:

```bash
# Generate Ed25519 keypair
openssl genpkey -algorithm Ed25519 -out /tmp/jwt-signing.pem
openssl pkey -in /tmp/jwt-signing.pem -pubout -out /tmp/jwt-public.pem

# Generate a key ID (KID) from the public key fingerprint
KID=$(openssl pkey -in /tmp/jwt-signing.pem -pubout -outform DER \
    | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
echo "$KID" > /tmp/jwt-kid.txt

# Create the Kubernetes secret
oc -n openshell create secret generic openshell-jwt-keys \
    --from-file=signing.pem=/tmp/jwt-signing.pem \
    --from-file=public.pem=/tmp/jwt-public.pem \
    --from-file=kid=/tmp/jwt-kid.txt

# Clean up local key files
rm -f /tmp/jwt-signing.pem /tmp/jwt-public.pem /tmp/jwt-kid.txt
```

### Step 5: Install OpenShell via Helm

Install the OpenShell Helm chart with OpenShift-specific overrides:

```bash
helm install openshell oci://ghcr.io/nvidia/openshell/helm-chart \
    --namespace openshell \
    --version 0.0.103 \
    --set pkiInitJob.enabled=false \
    --set server.disableTls=true \
    --set server.auth.allowUnauthenticatedUsers=true \
    --set-string server.sandboxImage='ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e' \
    --set podSecurityContext.fsGroup=null \
    --set securityContext.runAsUser=null
```

**Why each override is needed:**

| Override | Reason |
|----------|--------|
| `pkiInitJob.enabled=false` | We pre-created JWT keys in Step 4 (PKI Job is not SCC-compatible) |
| `server.disableTls=true` | Run gateway in plaintext for evaluation. TLS would require cert-manager. |
| `server.auth.allowUnauthenticatedUsers=true` | No authentication on the cluster-internal workshop gateway |
| `podSecurityContext.fsGroup=null` | Clear the chart's hardcoded `fsGroup: 1000` so OpenShift SCC can assign |
| `securityContext.runAsUser=null` | Clear the chart's hardcoded `runAsUser: 1000` so OpenShift SCC can assign |

The chart and workshop CLI are both pinned to `0.0.103`.

### Step 6: Wait for the gateway

```bash
oc -n openshell rollout status statefulset/openshell --timeout=300s
```

Verify the pod is running:

```bash
oc -n openshell get pods
```

Expected output:
```
NAME          READY   STATUS    RESTARTS   AGE
openshell-0   1/1     Running   0          1m
```

### Step 7: Register the gateway

Start a local port-forward in one terminal:

```bash
oc -n openshell port-forward svc/openshell 8080:8080
```

Tell the CLI where the gateway is from another terminal:

```bash
openshell gateway add http://127.0.0.1:8080 --local --name local-gateway
openshell gateway select local-gateway
```

### Step 8: Verify

```bash
openshell status
```

Expected output shows the gateway connection details and that it is healthy.

You can also run the automated verification:

```bash
bash verify.sh
```

### Monitor Live Events

Use `openshell term` to watch sandbox events in real-time:

```bash
openshell term
```

This streams OCSF-formatted events showing sandbox creation, command execution, network policy enforcement (ALLOWED/DENIED), and more. Leave it running in a second terminal while testing sandbox security.

### Step 9: Create your first sandbox

**Quick test (run a command and exit):**

```bash
openshell sandbox create --name test -- echo 'Hello from OpenShell!'
```

**Interactive session:**

```bash
# Create a sandbox without entering it immediately
openshell sandbox create --name my-sandbox --no-tty -- true

# Connect to it (opens a shell inside the sandbox)
openshell sandbox connect my-sandbox

# Inside the sandbox, you are the 'sandbox' user with restricted access.
# Try: whoami, ls /, cat /etc/os-release

# Exit when done
exit

# List sandboxes
openshell sandbox list

# Delete the sandbox
openshell sandbox delete my-sandbox
```

**Autonomous mode (run a task, get results, destroy):**

```bash
openshell sandbox create --name auto-test --no-keep -- bash -c 'echo "Task done" > /sandbox/result.txt && cat /sandbox/result.txt'
```

The `--no-keep` flag automatically deletes the sandbox after the command exits.

## Sandbox Security: Quickstart Policy

The workshop applies the read-only GitHub API policy
(`automation/policies/sandbox-policy-quickstart.yaml`) in Module 2. The
automated test verifies every control layer against that policy.

### Network: Default-Deny via CONNECT Proxy

Every outbound connection goes through OpenShell's HTTP CONNECT proxy. Only endpoints explicitly listed in the policy are reachable - everything else returns HTTP 403.

```bash
# Apply the workshop policy to the Module 1 sandbox
openshell policy set policy-lab --policy ../../policies/sandbox-policy-quickstart.yaml --wait

# From inside the sandbox:
curl https://api.github.com/zen   # -> HTTP 200 (allowed host, read-only)
curl https://google.com           # -> HTTP 403 (not in policy)
```

### Network: Binary Binding

The quickstart policy binds the allowed host to `/usr/bin/curl`. Other binaries are blocked even for the allowed host:

```bash
python3 -c "import urllib.request; urllib.request.urlopen('https://api.github.com/zen', timeout=10)"  # -> blocked (binary not in policy)
```

### Network: L7 Method Control

The read-only preset allows GET, HEAD, and OPTIONS and blocks writes on the allowed host:

```bash
curl -X POST https://api.github.com/repos/octocat/hello-world/issues   # -> HTTP 403 (policy denial)
```

### Filesystem: Landlock Enforcement

Landlock (Linux Security Module) restricts filesystem access at the kernel level. Paths must be explicitly declared as read-only or read-write in the policy. This policy uses `best_effort`; verify the tests below because unsupported kernels can degrade instead of failing sandbox startup:

```bash
echo test > /sandbox/test.txt      # OK (read-write path)
echo test > /tmp/test.txt          # OK (read-write path)
echo test > /etc/test.txt          # Permission denied (read-only)
echo test > /var/tmp/data.txt      # Permission denied by Landlock (directory is otherwise writable)
cat /etc/os-release                # OK (read-only allows reads)
```

### Process Identity

The following check proves the agent user identity. It does not by itself prove
seccomp, capability, namespace, or privilege-escalation controls:

```bash
whoami   # -> sandbox
id       # -> uid=<n>(sandbox) gid=<n>(sandbox) groups=<n>(sandbox)
```

### Run the Full Security Test

```bash
bash test-sandbox-security.sh        # run all tests against policy-lab, see color-coded report
```

This runs all network, filesystem, and process tests against the `policy-lab`
sandbox (the Module 1/2 sandbox with the quickstart policy applied) and prints
a summary showing what OpenShell blocks. Pass an alternative sandbox name as
the first argument.

## Teardown

Remove the resources installed by this environment:

```bash
bash teardown.sh
```

This removes the Helm release, JWT signing secret, PVC, SCC binding, and namespace.

To also remove the Agent Sandbox operator and owned CRDs, only after confirming
that no other workload uses them:

```bash
bash teardown.sh --crd
```

## Troubleshooting

**Gateway pod stuck in Pending:**
Check if the PVC is bound. The gateway needs a 1Gi PVC for its SQLite database. Also verify a default StorageClass exists.
```bash
oc -n openshell get pvc
oc get storageclass
```

**SCC errors on sandbox pods:**
Verify the SCC binding was applied before Helm install:
```bash
oc adm policy who-can use scc privileged -n openshell
```

**openshell CLI `connection refused` or `Disconnected`:**
Verify that `oc -n openshell port-forward svc/openshell 8080:8080` is
still running and that `openshell gateway list` shows
`http://127.0.0.1:8080` for the `local-gateway` gateway.

**Sandbox stuck in `Creating` state:**
Check sandbox pod events for image pull or SCC issues:
```bash
oc -n openshell get pods
oc -n openshell describe pod -l app.kubernetes.io/component=sandbox
```

**`openssl: command not found` or Ed25519 errors (macOS):**
macOS ships LibreSSL which does not support Ed25519. Install OpenSSL 3.x via Homebrew: `brew install openssl@3`. The install script auto-detects Homebrew OpenSSL.

## Workshop Use

The Showroom modules in `content/modules/ROOT/pages/` provide the supported
participant sequence, expected evidence, and transition to Secure Agent
Workspace.
