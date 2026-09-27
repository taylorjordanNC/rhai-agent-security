#!/bin/bash
# Test OpenShell sandbox security enforcement against the workshop's
# quickstart policy (read-only GitHub REST API via curl).
# Tests: default-deny network, binary binding, L7 method control,
# Landlock filesystem, and process identity.
#
# Usage:
#   bash test-sandbox-security.sh [sandbox-name]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=functions.sh
source "$SCRIPT_DIR/functions.sh"

SANDBOX_NAME="${1:-policy-lab}"

export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

PASS=0 FAIL=0 TOTAL=0
track() {
    local actual="$1" expected="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "================================================================"
echo " OpenShell Security Test - Quickstart Policy"
echo " Sandbox: $SANDBOX_NAME"
echo "================================================================"

# --- Network: Default-Deny ---
echo ""
step "1. CONNECT Proxy: Default-Deny Network"
echo "   Every outbound connection goes through the CONNECT proxy."
echo "   Only endpoints in the policy are reachable."
echo ""

test_curl "curl https://api.github.com (allowed host)" "https://api.github.com/zen" "$SANDBOX_NAME"
track $? 0

test_curl "curl https://google.com" "https://google.com" "$SANDBOX_NAME"
track $? 1

test_curl "curl https://api.anthropic.com" "https://api.anthropic.com/v1/models" "$SANDBOX_NAME"
track $? 1

test_curl "curl https://registry.npmjs.org" "https://registry.npmjs.org/express" "$SANDBOX_NAME"
track $? 1

# --- Network: Binary Binding ---
echo ""
step "2. CONNECT Proxy: Binary Binding"
echo "   The quickstart policy binds the allowed host to /usr/bin/curl."
echo "   python3 is blocked even for the allowed endpoint."
echo ""

test_python_url "python3 urllib to api.github.com" "https://api.github.com/zen" "$SANDBOX_NAME"
track $? 1

# --- Network: L7 Method Control ---
echo ""
step "3. L7 Enforcement: HTTP Method Control"
echo "   api.github.com is an allowed host, but the read-only policy"
echo "   blocks POST while GET succeeds."
echo ""

test_curl_method "POST api.github.com (read-only policy)" "POST" \
    "https://api.github.com/repos/octocat/hello-world/issues" "$SANDBOX_NAME"
track $? 1

# --- Filesystem: Landlock ---
echo ""
step "4. Landlock: Filesystem Enforcement"
echo "   Landlock LSM enforces filesystem access at the kernel level."
echo "   Only paths declared in the policy are accessible."
echo ""

test_file_write "write /sandbox/test-$$" "/sandbox/test-$$" "$SANDBOX_NAME"
track $? 0

test_file_write "write /tmp/test-$$" "/tmp/test-$$" "$SANDBOX_NAME"
track $? 0

test_file_write "write /etc/test-$$ (read-only)" "/etc/test-$$" "$SANDBOX_NAME"
track $? 1

test_file_write "write /usr/test-$$ (read-only)" "/usr/test-$$" "$SANDBOX_NAME"
track $? 1

test_file_write "write /var/tmp/test-$$ (not in policy)" "/var/tmp/test-$$" "$SANDBOX_NAME"
track $? 1

test_file_read "read /etc/os-release (read-only path)" "/etc/os-release" "$SANDBOX_NAME"
track $? 0

test_file_read "read /proc/self/status (read-only path)" "/proc/self/status" "$SANDBOX_NAME"
track $? 0

# --- Process Isolation ---
echo ""
step "5. Process Isolation"
echo "   The agent runs as the unprivileged 'sandbox' user."
echo ""

test_process "whoami" "whoami" "sandbox" "$SANDBOX_NAME"
track $? 0

# --- Summary ---
echo ""
echo "================================================================"
echo " Results: $PASS passed, $FAIL unexpected out of $TOTAL tests"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo " Network:    Default-deny + binary binding + L7 method enforced"
    echo " Filesystem: Landlock restricts to declared paths"
    echo " Process:    Running as non-root sandbox user"
else
    echo " One or more controls did not produce the expected evidence."
fi
echo "================================================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
