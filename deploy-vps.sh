#!/usr/bin/env bash

TARGET_HOST="129.153.13.212"
TARGET_USER="ubuntu"
FLAKE=".#homeConfigurations.ubuntu"
SSH_KEY_NAME="homelab"
DEPLOYER_IMAGE="homelab-deployer:latest"

set -e

# Check for SSH Key locally
if [[ ! -f "$HOME/.ssh/$SSH_KEY_NAME" ]]; then
    echo "❌ CRITICAL ERROR: SSH Key '$HOME/.ssh/$SSH_KEY_NAME' not found!"
    exit 1
fi

echo "🚀 Starting Deployment to $TARGET_USER@$TARGET_HOST..."

# Run the deployment INSIDE the container
podman run --rm -it \
  --security-opt label=disable \
  -v "$(pwd):/work:Z" \
  -v "$HOME/.ssh:/mnt/ssh_keys:ro" \
  -w /work \
  --net=host \
  -e TARGET_HOST="$TARGET_HOST" \
  -e TARGET_USER="$TARGET_USER" \
  -e FLAKE="$FLAKE" \
  -e SSH_KEY_NAME="$SSH_KEY_NAME" \
  "$DEPLOYER_IMAGE" \
  bash -c "
    # --- Setup SSH ---
    mkdir -p /root/.ssh
    cp -r /mnt/ssh_keys/* /root/.ssh/ 2>/dev/null || true
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/* 2>/dev/null || true
    
    cat >> /root/.ssh/config <<EOF
Host $TARGET_HOST
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile /root/.ssh/$SSH_KEY_NAME
EOF

    SSH_CMD=\"ssh -i /root/.ssh/$SSH_KEY_NAME $TARGET_USER@$TARGET_HOST\"

    # --- 1. Bootstrap Nix ---
    echo '🔍 Checking remote setup...'
    if ! \$SSH_CMD \"command -v nix-env &> /dev/null\"; then
        echo '📦 Installing Nix...'
        \$SSH_CMD \"curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm\"
    fi

    # --- 2. System Configuration ---
    echo '🛡️ Configuring System & Security...'
    
    \$SSH_CMD \"
        set -e
        # 1. Enable Lingering
        sudo loginctl enable-linger $TARGET_USER

        # 2. Fix 'Lacks Signature' Error
        if ! grep -q 'trusted-users = root $TARGET_USER' /etc/nix/nix.conf; then
            echo '🔓 Adding $TARGET_USER to trusted-users...'
            echo 'trusted-users = root $TARGET_USER' | sudo tee -a /etc/nix/nix.conf
        fi

        # Also disable require-sigs for smoother deployments
        if ! grep -q 'require-sigs = false' /etc/nix/nix.conf; then
            echo 'require-sigs = false' | sudo tee -a /etc/nix/nix.conf
        fi

        # CRITICAL: Restart daemon to ensure config is loaded
        echo '🔄 Restarting Nix Daemon...'
        sudo systemctl restart nix-daemon
        sleep 2  # Give daemon time to restart

        # 3. Swap Configuration
        if [ ! -f /swapfile ]; then
            echo '💾 Creating 3GB Swap File...'
            sudo fallocate -l 3G /swapfile
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
            fi
            echo '✅ Swap Active'
        else
            echo '✅ Swap already exists'
        fi
    \"

    # --- 3. Build Configuration ---
    echo '🔨 Building Home Manager configuration...'
    DRV=\$(nix build --no-link --print-out-paths \"\${FLAKE}.activationPackage\" --extra-experimental-features 'nix-command flakes')
    
    if [ -z \"\$DRV\" ]; then
        echo '❌ Build failed.'
        exit 1
    fi
    echo \"✅ Build successful: \$DRV\"

    # --- 4. Copy & Activate ---
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
