{ config, pkgs, lib, ... }:

let
    # --- Declarative Configuration ---
    # Defines the static instances and public host
    portalConfig = {
        shared_data_mode = false;
        public_host = "https://foundry.tongatime.us";
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
        
        # Pull latest code from your repo
        if [ ! -d ".git" ]; then
            git clone https://github.com/TaylorTurnerIT/foundry-portal.git .
        else
            git fetch origin
            # Reset to match remote exactly
            git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)
        fi

        # Build image
        podman build -t foundry-portal:latest .
        '';
        serviceConfig = { Type = "oneshot"; TimeoutStartSec = "900"; };
    };

    # --- Network Service ---
    systemd.services.create-foundry-net = {
        description = "Create foundry_net Podman network";
        after = [ "network.target" ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        path = [ pkgs.podman ];
        script = "podman network exists foundry_net || podman network create foundry_net";
    };

    # --- Main Container Service ---
    virtualisation.oci-containers.containers.foundry-portal = {
        image = "foundry-portal:latest";
        autoStart = true;
        extraOptions = [ "--network=host" ];
        
        environment = {
            # Align internal path with host path so orchestrator volume mounts work
            FOUNDRY_DATA_DIR = "/var/lib/foundry"; 
            DOCKER_HOST = "unix:///var/run/docker.sock"; 
        };

        volumes = [
            "${configYaml}:/app/config_declarative.yaml:ro"
            
            # [CRITICAL] Secrets Mounting
            # 1. Admin Password for the Portal itself
            "${config.sops.secrets.foundry_admin_hash.path}:/run/secrets/foundry_admin_hash:ro"
            # 2. Bulk Secrets (License/Admin Key) for Child Containers
            "${config.sops.templates."foundry_secrets.json".path}:/run/secrets/foundry_secrets.json:ro"
            
            # Persistent Data
            "/var/lib/foundry-portal:/data:rw" 
            "/var/run/podman/podman.sock:/var/run/docker.sock"
            # Mount host data dir to same path in container
            "/var/lib/foundry:/var/lib/foundry:rw"
        ];

        cmd = [ 
            "/bin/sh" 
            "-c" 
            ''
                # 1. Config Management
                if [ ! -f /data/config.yaml ]; then
                    cp /app/config_declarative.yaml /data/config.yaml
                fi
                rm -f /app/config.yaml
                ln -sf /data/config.yaml /app/config.yaml

                # 2. Instance Registry Init
                if [ ! -f /var/lib/foundry/instances.json ]; then
                     echo "{}" > /var/lib/foundry/instances.json
                     chown 1000:1000 /var/lib/foundry/instances.json
                fi

                # 3. Permission Fixes
                # Ensure child containers (uid 1000) can write to cache and data
                mkdir -p /var/lib/foundry/cache
                chown -R 1000:1000 /var/lib/foundry/cache
                chown 1000:1000 /var/lib/foundry

                # 4. Start App (Admin Hash injected via Python one-liner)
                python -c "import yaml; conf=yaml.safe_load(open('/app/config.yaml')); conf['admin_password_hash']=open('/run/secrets/foundry_admin_hash').read().strip(); yaml.dump(conf, open('/app/config.yaml','w'))" && \
                python app.py
            ''
        ];
    };

    systemd.services.podman-foundry-portal = {
        requires = [ "build-foundry-portal.service" "create-foundry-net.service" ];
        after = [ "build-foundry-portal.service" "create-foundry-net.service" ];
    };

    # --- Path Watcher (Reloads Caddy) ---
    systemd.paths.foundry-caddy-watcher = {
        description = "Watch for Foundry Route Changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = { PathChanged = "/var/lib/foundry-portal/routes.caddy"; };
    };

    systemd.services.foundry-caddy-watcher = {
        description = "Reload Caddy on Route Change";
        serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl reload caddy.service";
        };
    };

    systemd.tmpfiles.rules = [
        "d /var/lib/foundry-portal 0775 root caddy - -"
        "f /var/lib/foundry-portal/routes.caddy 0644 root caddy - -"
        "d /var/lib/foundry 0775 1000 1000 - -"
    ];
}