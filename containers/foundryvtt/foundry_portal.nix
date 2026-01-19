{ config, pkgs, lib, ... }:

let
    # --- Declarative Configuration ---
    portalConfig = {
        shared_data_mode = false;
        instances = [];
    };

    configYaml = pkgs.writeText "foundry-portal-config.yaml" (lib.generators.toYAML {} portalConfig);

in {
    # --- Build Service ---
    systemd.services.build-foundry-portal = {
        description = "Build Foundry Portal Docker Image";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [ pkgs.git pkgs.podman ];

        script = ''
        set -e
        WORK_DIR="/var/lib/foundry-portal/source"
        mkdir -p "$WORK_DIR"
        cd "$WORK_DIR"
        
        if [ -d ".git" ]; then
            echo "Repo exists. Checking for updates..."
            
            # Capture the current commit hash
            OLD_HASH=$(git rev-parse HEAD)
            
            # Fetch and Hard Reset
            # This fixes the 'divergent branches' error by forcing local to match remote
            git fetch origin
            # specific branch logic not needed if we rely on the tracking branch, 
            # but usually it's 'main'. We use symbolic-ref to find the current branch.
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git reset --hard "origin/$BRANCH"
            
            NEW_HASH=$(git rev-parse HEAD)

            # Build if hashes differ OR if the image is missing
            if [ "$OLD_HASH" != "$NEW_HASH" ] || ! podman image exists foundry-portal:latest; then
                echo "Update detected or image missing. Building..."
                podman build -t foundry-portal:latest .
            else
                echo "Already up to date and image exists."
            fi
        else
            echo "Cloning fresh repository..."
            git clone https://github.com/TaylorTurnerIT/foundry-portal.git .
            podman build -t foundry-portal:latest .
        fi
        '';

        serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = "900"; 
        };
    };

    virtualisation.oci-containers.containers.foundry-portal = {
        image = "foundry-portal:latest";
        autoStart = true;
        extraOptions = [ "--network=host" ];
        
        environment = {
            FOUNDRY_DATA_DIR = "/var/lib/foundry";
            # Tells the app that the host socket is mounted here
            DOCKER_HOST = "unix:///var/run/docker.sock"; 
        };

        volumes = [
            "${configYaml}:/app/config_declarative.yaml:ro"
            "${config.sops.secrets.foundry_admin_hash.path}:/run/secrets/foundry_admin_hash:ro"
            "/var/lib/foundry-portal:/data:rw" 
            "/var/run/podman/podman.sock:/var/run/docker.sock"
            "/var/lib/foundry:/var/lib/foundry:rw"
        ];

        # The startup script is still valid. It creates config.yaml from your declarative config.
        # The new app will read config.yaml for static settings and create instances.json for dynamic ones.
        cmd = [ 
            "/bin/sh" 
            "-c" 
            ''
                if [ ! -f /data/config.yaml ]; then
                    cp /app/config_declarative.yaml /data/config.yaml
                fi
                rm -f /app/config.yaml
                ln -sf /data/config.yaml /app/config.yaml

                # Initialize instances.json if missing (New requirement)
                if [ ! -f /data/foundry/instances.json ]; then
                     echo "{}" > /data/foundry/instances.json
                     chown 1000:1000 /data/foundry/instances.json
                fi

                # Secret Injection
                python -c "import yaml; conf=yaml.safe_load(open('/app/config.yaml')); conf['admin_password_hash']=open('/run/secrets/foundry_admin_hash').read().strip(); yaml.dump(conf, open('/app/config.yaml','w'))" && \
                
                python app.py
            ''
        ];
    };


    systemd.services.create-foundry-net = {
        description = "Create foundry_net Podman network";
        after = [ "network.target" ];
        serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
        };
        path = [ pkgs.podman ];
        script = ''
            podman network exists foundry_net || podman network create foundry_net
        '';
    };
    
    systemd.services.podman-foundry-portal = {
        requires = [ "build-foundry-portal.service" "create-foundry-net.service" ];
        after = [ "build-foundry-portal.service" "create-foundry-net.service" ];
    };

    systemd.paths.foundry-caddy-watcher = {
        description = "Watch for Foundry Route Changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
            PathChanged = "/var/lib/foundry-portal/routes.caddy";
        };
    };

    systemd.services.foundry-caddy-watcher = {
        description = "Reload Caddy on Route Change";
        serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl reload caddy.service";
        };
    };

    # Ensure permissions allow the container to write and Caddy to read
    systemd.tmpfiles.rules = [
        "d /var/lib/foundry-portal 0775 root caddy - -"
        "f /var/lib/foundry-portal/routes.caddy 0644 root caddy - -"
    ];
}