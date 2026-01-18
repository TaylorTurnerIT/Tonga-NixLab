{ config, lib, pkgs, ... }:

let
  cfg = config.services.foundry-cluster;
  
  # --- Dynamic Instance Loading ---
  instancesFile = ./instances.json;
  
  # Read file if it exists, otherwise return empty string
  fileContents = if builtins.pathExists instancesFile 
                 then builtins.readFile instancesFile 
                 else "";

  # Parse JSON if content exists, otherwise return empty set
  storedInstances = if fileContents != "" 
                    then builtins.fromJSON fileContents 
                    else {};

  # The Default Fallback (If JSON is missing or empty)
  defaultInstances = {
    admin = {
      port = 30000;
      imageTag = "release";
      title = "Foundry Admin Portal";
    };
  };

  # Final selection: Use stored if available, otherwise default
  allInstances = if storedInstances != {} then storedInstances else defaultInstances;

in {
  options.services.foundry-cluster = {
    enable = lib.mkEnableOption "Foundry VTT Cluster";
    domain = lib.mkOption { type = lib.types.str; default = "foundry.tongatime.us"; };
  };

  config = lib.mkIf cfg.enable {
    
    virtualisation.oci-containers.containers = 
      lib.mkMerge (lib.mapAttrsToList (name: instance: let
        safeName = "foundry_${name}";
        nurseryName = "nursery_${name}";
        
        # Admin gets full access, others get specific world folders
        dataVolume = if name == "admin" 
          then "/var/lib/foundry:/data" 
          else "/var/lib/foundry/worlds/${name}:/data/Data/worlds/${name}";

        nurseryConfig = pkgs.writeText "nursery-${name}.yml" (lib.generators.toYAML {} {
          proxyListeningPort = 80;
          proxyHosts = [{
            domain = cfg.domain;
            containerName = safeName;
            displayName = "${instance.title or name}";
            proxyHost = safeName;
            proxyPort = 30000;
            timeoutSeconds = 3600;
          }];
        });

      in {
        # --- Game Container ---
        "${safeName}" = {
          # Use instance tag or default to release if missing
          image = "felddy/foundryvtt:${instance.imageTag or "release"}";
          autoStart = false; 
          extraOptions = [ "--network=foundry_net" ];
          volumes = [
            dataVolume
            "${config.sops.templates."foundry_secrets.json".path}:/run/secrets/config.json:ro"
          ];
          environment = {
            FOUNDRY_TELEMETRY = "false";
            FOUNDRY_HOSTNAME = cfg.domain;
            FOUNDRY_ROUTE_PREFIX = name;
            FOUNDRY_PROXY_SSL = "true";
            FOUNDRY_PROXY_PORT = "443";
            FOUNDRY_UID = "1000";
            FOUNDRY_GID = "1000";
            # Admin needs to be able to browse all worlds, so we don't lock it
            FOUNDRY_WORLD = if name == "admin" then "" else name; 
          } // (lib.optionalAttrs (name == "admin") {
             FOUNDRY_ROUTE_PREFIX = "admin"; 
          });
        };

        # --- Nursery Container (Pinned 1.9.0) ---
        "${nurseryName}" = {
          image = "ghcr.io/itsecholot/containernursery:1.9.0";HERE
          autoStart = true;
          ports = [ "${toString instance.port}:80" ];
          extraOptions = [ "--network=foundry_net" ];
          volumes = [
            "/var/run/podman/podman.sock:/var/run/docker.sock"
            "${nurseryConfig}:/usr/src/app/config/config.yml:ro"
          ];
        };
      }) allInstances);

    systemd.services."create-foundry_net-network" = {
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = "${pkgs.podman}/bin/podman network exists foundry_net || ${pkgs.podman}/bin/podman network create --subnet 10.88.0.0/16 foundry_net";
    };
  };
}