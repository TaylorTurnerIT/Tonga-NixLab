{ config, pkgs, lib, ... }:

let
    # --- Declarative Configuration ---
    # We define the config here, and Nix writes it to the store.
    portalConfig = {
        shared_data_mode = false;
        instances = [
            {
                name = "Chef's Games";
                url = "https://foundry.tongatime.us/chef";
            }
            # {
            #     name = "Crunch's Games";
            #     url = "https://foundry.tongatime.us/crunch";
            # }
            # {
            #     name = "ColossusDirge's Games";
            #     url = "https://foundry.tongatime.us/colossusdirge";
            # }
            # {
            #     name = "Laz's Games";
            #     url = "https://foundry.tongatime.us/laz";
            # }
        ];
    };

    # Convert the set to YAML and write it to the Nix Store
    configYaml = pkgs.writeText "foundry-portal-config.yaml" (lib.generators.toYAML {} portalConfig);

    in {
    # --- Build Service ---
    # Since Foundry Portal does not have an official docker image, we build it from source using Podman.
    # This service ensures the image exists before the container starts.
    systemd.services.build-foundry-portal = {
        description = "Build Foundry Portal Docker Image";
        path = [ pkgs.git pkgs.podman ]; # Tools needed for the script
        script = ''
        set -e
        WORK_DIR="/var/lib/foundry-portal/source"
        
        # Ensure directory exists
        mkdir -p "$WORK_DIR"
        cd "$WORK_DIR"
        if [ -d ".git" ]; then
            output=$(git pull)
            # Only build if git pull reported changes or if the image doesn't exist
            if [[ "$output" != *"Already up to date."* ]] || ! podman image exists foundry-portal:latest; then
                podman build -t foundry-portal:latest .
            fi
        else
            git clone https://github.com/TaylorTurnerIT/foundry-portal.git .
            podman build -t foundry-portal:latest .
        fi

        # Build the image using Podman
        # We tag it as 'foundry-portal:latest' so the container service can find it.
        echo "Building Podman image..."
        podman build -t foundry-portal:latest .
        '';
        serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "300"; # Allow 5 minutes for the build
        };
    };
    virtualisation.oci-containers.containers.foundry-portal = {
    image = "foundry-portal:latest";
    autoStart = true;
    # NETWORK FIX: Use host networking to bypass firewall blocks on port 30000
    extraOptions = [ "--network=host" ];
    volumes = [
        "${configYaml}:/app/config_declarative.yaml:ro"
        "${config.sops.secrets.foundry_admin_hash.path}:/run/secrets/foundry_admin_hash:ro"
        "/var/lib/foundry-portal:/data:rw" 
    ];
    # Overwrite startup command to install config
    # Runtime Injection
    # 1. Check if persistent config exists in /data. If not, seed it from declarative config.
    # 2. Symlink /data/config.yaml to /app/config.yaml so the app reads/writes the persistent file.
    # 3. Python script: Load yaml -> Read secret -> Inject hash -> Save yaml (preserves other data)
    # 4. Run app
    cmd = [ 
        "/bin/sh" 
        "-c" 
        ''
            # Initialize config if it doesn't exist
            if [ ! -f /data/config.yaml ]; then
                echo "Initializing config from declarative defaults..."
                cp /app/config_declarative.yaml /data/config.yaml
            fi

            # Ensure the app uses the persistent file
            rm -f /app/config.yaml
            ln -sf /data/config.yaml /app/config.yaml

            # Inject the secret hash into the persistent config
            python -c "import yaml; conf=yaml.safe_load(open('/app/config.yaml')); conf['admin_password_hash']=open('/run/secrets/foundry_admin_hash').read().strip(); yaml.dump(conf, open('/app/config.yaml','w'))" && \
            
            # Start the application
            python app.py
        ''
    ];
};

    systemd.services.podman-foundry-portal = {
        requires = [ "build-foundry-portal.service" ];
        after = [ "build-foundry-portal.service" ];
    };

    # Ensure the Foundry Portal config directory exists with correct permissions
    systemd.tmpfiles.rules = [
        "d /var/lib/foundry-portal 0755 root root - -"
    ];
}