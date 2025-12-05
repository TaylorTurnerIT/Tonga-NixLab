#!/usr/bin/env bash
set -e

DEPLOYER_IMAGE="homelab-deployer:latest"

# Check for Deployer Image
if ! podman image exists "$DEPLOYER_IMAGE"; then
    echo "⚠️  Deployer image not found. Please run ./build-deployer.sh first."
    exit 1
fi

echo "🚀 Starting DNS Deployment..."

# Run Container
# We mount the SSH/Age keys so sops works inside the container.
# We mount the current directory so it can see secrets.yaml and dnsconfig.js.
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.config/sops:/root/.config/sops:ro" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  -w /work \
  "$DEPLOYER_IMAGE" \
  bash -c "
    set -e

    # Define the 'Magic Command' to fetch credentials
    # Decrypt secrets.yaml
    # Use yq to construct the JSON object: { \"cloudflare\": { \"TYPE\": \"...\", \"apitoken\": ... } }
    # Output as JSON (-o=json)
    CRED_CMD='!sops -d secrets/secrets.yaml | yq -o=json \"{\\\"cloudflare\\\": {\\\"TYPE\\\": \\\"CLOUDFLAREAPI\\\", \\\"apitoken\\\": .cloudflare_token}}\"'

    echo '🔍 Checking Configuration...'
    # We pass the command string directly to --creds
    dnscontrol check --creds \"\$CRED_CMD\" --config network/dnsconfig.js

    echo '----------------------------------------'
    echo '🔮 PREVIEWING CHANGES'
    echo '----------------------------------------'
    dnscontrol preview --creds \"\$CRED_CMD\" --config network/dnsconfig.js

    echo '----------------------------------------'
    read -p '⚠️  Apply these changes to Cloudflare? (y/N) ' -n 1 -r
    echo
    if [[ \$REPLY =~ ^[Yy]$ ]]; then
        echo '🚀 Pushing changes...'
        dnscontrol push --creds \"\$CRED_CMD\" --config network/dnsconfig.js
    else
        echo '🚫 Aborted.'
    fi
"