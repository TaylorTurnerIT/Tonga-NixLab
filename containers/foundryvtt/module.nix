{ config, lib, pkgs, ... }:

let
  cfg = config.services.foundry-cluster;
in {
  options.services.foundry-cluster = {
    enable = lib.mkEnableOption "Foundry VTT Cluster (Imperative Mode)";
    domain = lib.mkOption { type = lib.types.str; default = "foundry.tongatime.us"; };
  };

  config = lib.mkIf cfg.enable {
    
    # 1. Networking Infrastructure
    # Ensure the bridge network exists so the Portal can attach new game containers to it.
    systemd.services."create-foundry_net-network" = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # We use '|| true' to ensure the service doesn't fail if the network already exists
      script = "${pkgs.podman}/bin/podman network exists foundry_net || ${pkgs.podman}/bin/podman network create --subnet 10.88.0.0/16 foundry_net";
    };

    # Persistence Infrastructure
    # Create the directory structure on the Host so the Portal has somewhere to write.
    # We set owner to 1000:1000 (typical foundry/user UID) to avoid permission issues.
    systemd.tmpfiles.rules = [
      # The main directory for all things Foundry
      "d /var/lib/foundry 0775 1000 1000 - -"
      
      # Where active game data will live
      "d /var/lib/foundry/worlds 0775 1000 1000 - -"
      
      # Where your 'Master Copies' (PF2e, etc.) will live
      "d /var/lib/foundry/templates 0775 1000 1000 - -"
      
      # The Registry File: Create an empty JSON object if it doesn't exist
      "f /var/lib/foundry/instances.json 0664 1000 1000 - {}"
    ];
  };
}