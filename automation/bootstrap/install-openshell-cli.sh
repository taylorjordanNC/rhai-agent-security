#!/usr/bin/env bash
# Install the workshop OpenShell CLI: a PATH wrapper script that runs the
# RHAIV-packaged OpenShell CLI container through Podman. The wrapper works in
# both interactive shells and make recipe shells (aliases do not).
set -euo pipefail

# Digest-pinned RHAIV CLI image (0.1.2-rhaiv.0, amd64 single-platform digest).
OPENSHELL_CLI_IMAGE="${OPENSHELL_CLI_IMAGE:-quay.io/opendatahub/odh-openshell-cli@sha256:7d04766147c6960da7d06580f3efd6538679d147aa3b0cd364993c534c3a6c7b}"
EXPECTED_VERSION="${OPENSHELL_CLI_VERSION:-0.1.2-rhaiv.0}"
BIN_DIR="${OPENSHELL_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="$HOME/.config/openshell"

if ! command -v podman >/dev/null 2>&1; then
  printf 'podman is required to run the OpenShell CLI container.\n' >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONFIG_DIR"
cat > "$BIN_DIR/openshell" <<EOF
#!/bin/bash
exec podman run --rm --platform linux/amd64 \\
  -v "$CONFIG_DIR:/.config/openshell" \\
  "$OPENSHELL_CLI_IMAGE" \\
  "\$@"
EOF
chmod 0755 "$BIN_DIR/openshell"

if [[ "$(uname -s)" == "Darwin" ]]; then
  xattr -d com.apple.quarantine "$BIN_DIR/openshell" 2>/dev/null || true
fi

# Warm the image and verify the version pin.
if ! "$BIN_DIR/openshell" --version | grep -q "$EXPECTED_VERSION"; then
  printf 'Version verification failed: expected %s\n' "$EXPECTED_VERSION" >&2
  exit 1
fi

printf 'Installed OpenShell %s CLI wrapper at %s\n' "$EXPECTED_VERSION" "$BIN_DIR/openshell"
printf 'Add this directory to PATH if needed: %s\n' "$BIN_DIR"
