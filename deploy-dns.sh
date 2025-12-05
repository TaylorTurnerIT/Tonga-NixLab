#!/usr/bin/env bash
set -e

# --- Configuration ---
DEPLOYER_IMAGE="homelab-deployer:latest"
ZONES_YAML="network/dns_zones.yaml"
ZONES_JSON="network/dns_zones.json"
# ---------------------

# 1. Check for Deployer Image
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "⚠️  Deployer image not found. Please run ./build-deployer.sh first."
    exit 1
fi

echo "🚀 Starting DNS Deployment..."

# 2. Run Container
# We mount everything needed. The script inside handles the lifecycle of the JSON file.
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.config/sops:/root/.config/sops:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -w /work \
  "$DEPLOYER_IMAGE" \
  bash -c "
    set -e
    
    # --- 1. PREPARE ---
    # Ensure we clean up the JSON file when this script exits (success or failure)
    trap 'rm -f $ZONES_JSON' EXIT

    echo '📝 Converting YAML to JSON...'
    # Convert local YAML to temporary JSON artifact
    # yq-go is installed in the container via Containerfile
    yq -o=json '$ZONES_YAML' > '$ZONES_JSON'

    # --- 2. CHECK ---
    echo '🔍 Checking Configuration...'
    dnscontrol check --config network/dnsconfig.js

    # --- 3. PREVIEW ---
    echo '----------------------------------------'
    echo '🔮 PREVIEWING CHANGES'
    echo '----------------------------------------'
    # Use sops to inject credentials on-the-fly
    dnscontrol preview --creds '!sops -d secrets/dns_creds.json' --config network/dnsconfig.js

    # --- 4. CONFIRM & PUSH ---
    echo '----------------------------------------'
    read -p '⚠️  Apply these changes to Cloudflare? (y/N) ' -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        echo '🚀 Pushing changes...'
        dnscontrol push --creds '!sops -d secrets/dns_creds.json' --config network/dnsconfig.js
    else
        echo '🚫 Aborted.'
    fi
"