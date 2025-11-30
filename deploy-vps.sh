#!/usr/bin/env bash

TARGET_HOST="129.153.13.212" # Your VPS IP
TARGET_USER="ubuntu"
FLAKE=".#ubuntu" # Matches homeConfigurations."ubuntu"
SSH_KEY="$HOME/.ssh/homelab"

set -e

echo "🚀 Deploying to $TARGET_USER@$TARGET_HOST..."

# 1. Bootstrapping: Check if Nix is installed on the remote server
if ! ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" "command -v nix-env &> /dev/null"; then
    echo "📦 Nix not found. Installing Nix on remote host..."
    # We use the Determinate Systems installer (fast, reliable)
    ssh -t -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm"
    echo "✅ Nix installed!"
fi

# 2. Build configuration LOCALLY
echo "🔨 Building Home Manager configuration..."
# We build the activation script locally
DRV=$(nix build --no-link --print-out-paths "$FLAKE.activationPackage")

# 3. Copy to Remote
echo "Ns Copying closure to remote..."
nix copy --to "ssh://$TARGET_USER@$TARGET_HOST?ssh-key=$SSH_KEY" "$DRV"

# 4. Activate on Remote
echo "🔄 Activating configuration..."
ssh -t -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" "$DRV/activate"

echo "✅ Deployment Complete!"