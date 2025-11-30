#!/usr/bin/env bash

TARGET_HOST="129.153.13.212"
TARGET_USER="ubuntu"
FLAKE=".#homeConfigurations.ubuntu"
SSH_KEY_NAME="homelab"
DEPLOYER_IMAGE="homelab-deployer:latest"

set -e

if [[ ! -f "$HOME/.ssh/$SSH_KEY_NAME" ]]; then
    echo "❌ CRITICAL ERROR: SSH Key '$HOME/.ssh/$SSH_KEY_NAME' not found!"
    exit 1
fi

echo "🚀 Starting Deployment to $TARGET_USER@$TARGET_HOST..."

# Create a temporary bootstrap script
BOOTSTRAP_SCRIPT=$(mktemp)
cat > "$BOOTSTRAP_SCRIPT" << 'BOOTSTRAP_EOF'
#!/usr/bin/env bash
set -e

TARGET_USER="$1"

echo "🔍 Checking remote setup..."
if ! command -v nix-env &> /dev/null; then
    echo "📦 Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi

echo "🛡️ Configuring System & Security..."

# Enable Lingering
sudo loginctl enable-linger "$TARGET_USER"

# Add to trusted-users (with explicit verification)
echo "🔓 Adding $TARGET_USER to trusted-users..."
if ! sudo grep -q "trusted-users.*$TARGET_USER" /etc/nix/nix.conf; then
    echo "trusted-users = root $TARGET_USER" | sudo tee -a /etc/nix/nix.conf
else
    echo "✓ $TARGET_USER already in trusted-users"
fi

# Add require-sigs = false
if ! sudo grep -q "require-sigs = false" /etc/nix/nix.conf; then
    echo "require-sigs = false" | sudo tee -a /etc/nix/nix.conf
else
    echo "✓ require-sigs already set to false"
fi

# Restart daemon
echo "🔄 Restarting Nix Daemon..."
sudo systemctl restart nix-daemon
sleep 3

# Verify configuration was applied
echo "✓ Verifying configuration..."
sudo cat /etc/nix/nix.conf | grep -E "(trusted-users|require-sigs)" || echo "⚠️  Warning: config lines not found"

# Swap Configuration
if [ ! -f /swapfile ]; then
    echo "💾 Creating 3GB Swap File..."
    sudo fallocate -l 3G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    echo "✅ Swap Active"
else
    echo "✅ Swap already exists"
fi

BOOTSTRAP_EOF

chmod +x "$BOOTSTRAP_SCRIPT"

# Run the deployer container
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -v "$BOOTSTRAP_SCRIPT:/mnt/bootstrap.sh:ro" \
  -w /work \
  --net=host \
  -e TARGET_HOST="$TARGET_HOST" \
  -e TARGET_USER="$TARGET_USER" \
  -e FLAKE="$FLAKE" \
  -e SSH_KEY_NAME="$SSH_KEY_NAME" \
  "$DEPLOYER_IMAGE" \
  bash -c "
    set -e
    
    # --- Setup SSH ---
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    cat >> /root/.ssh/config <<'SSHCONFIG'
Host $TARGET_HOST
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile /root/.ssh/$SSH_KEY_NAME
SSHCONFIG

    SSH_CMD=\"ssh -i /root/.ssh/$SSH_KEY_NAME $TARGET_USER@$TARGET_HOST\"

    # --- 1. Run bootstrap script on remote ---
    \$SSH_CMD 'bash -s \"$TARGET_USER\"' < /mnt/bootstrap.sh

    # --- 2. Build Configuration ---
    echo '🔨 Building Home Manager configuration...'
    DRV=\$(nix build --no-link --print-out-paths \"\${FLAKE}.activationPackage\" --extra-experimental-features 'nix-command flakes')
    
    if [ -z \"\$DRV\" ]; then
        echo '❌ Build failed.'
        exit 1
    fi
    echo \"✅ Build successful: \$DRV\"

    # --- 3. Copy & Activate ---
    echo '📦 Copying closure to remote...'
    export NIX_SSHOPTS=\"-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /root/.ssh/$SSH_KEY_NAME\"
    nix copy --to \"ssh://$TARGET_USER@$TARGET_HOST\" \\
      --option require-sigs false \\
      \"\$DRV\" \\
      --extra-experimental-features 'nix-command flakes'

    echo '🔄 Activating configuration...'
    \$SSH_CMD \"\$DRV/activate\"

    echo '✅ Deployment Complete!'
"

# Cleanup
rm "$BOOTSTRAP_SCRIPT"
