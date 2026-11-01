#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find . -name '*.sh' -type f -print0)

while IFS= read -r -d '' expression; do
    nix-instantiate --parse "$expression" >/dev/null
done < <(find . -name '*.nix' -type f -print0)

# Existing deployment scripts have lint debt; syntax is required for all scripts.
# actionlint checks workflow commands without imposing new lint rules on them.
actionlint -shellcheck='' .github/workflows/*.yml
python3 scripts/ci/check-secrets.py

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir "$work_dir/network"
cp network/dnsconfig.js "$work_dir/network/"
yq -o=json network/dns_zones.yaml > "$work_dir/network/dns_zones.json"
(
    cd "$work_dir"
    dnscontrol check --config network/dnsconfig.js
)
