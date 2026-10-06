#!/usr/bin/env bash
set -euo pipefail

required=(oc helm openshell jq make curl openssl)
expected_openshell_version="${OPENSHELL_VERSION:-0.1.2-rhaiv.0}"
missing=()

for command_name in "${required[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    missing+=("$command_name")
  fi
done

if ((${#missing[@]})); then
  printf 'Missing required commands: %s\n' "${missing[*]}" >&2
  printf 'Install them using the workshop prerequisites, then run this check again.\n' >&2
  exit 1
fi

oc whoami >/dev/null

installed_openshell_version="$(openshell --version | awk '{print $NF}')"
if [[ "${installed_openshell_version}" != "${expected_openshell_version}" ]]; then
  printf 'OpenShell %s is required; found %s at %s\n' \
    "${expected_openshell_version}" \
    "${installed_openshell_version}" \
    "$(command -v openshell)" >&2
  exit 1
fi

printf 'CLI prerequisites:\n'
helm version --short
openshell --version
jq --version
make --version

printf 'Cluster context:\n'
oc whoami
oc whoami --show-server
