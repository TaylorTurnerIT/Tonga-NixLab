{ config, pkgs, ... }:

let
  podmanNetwork = "media_net";
  podmanSubnet = "10.89.0.0/16"; # Subnet for media containers
  
  # Common options for LinuxServer.io images
  # PUID/PGID 1000 usually maps to the primary user, ensuring you can edit files via SMB/SSH.
  commonEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = "UTC";
  };

  # Shared paths
  mediaDir = "/var/lib/media";
  configDir = "/var/lib/config";
in {
  
  # --- Networking ---
  # Create a dedicated bridge network so containers can talk to each other by name
  # e.g., Sonarr talks to "prowlarr" and "qbittorrent"
  systemd.services."create-${podmanNetwork}-network" = {
    script = ''
      ${pkgs.podman}/bin/podman network exists ${podmanNetwork} || \
      ${pkgs.podman}/bin/podman network create --subnet ${podmanSubnet} ${podmanNetwork}
    '';
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers = {

    # --- Jellyfin (Media Server) ---
    jellyfin = {
      image = "lscr.io/linuxserver/jellyfin:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8096:8096" ]; # Web UI
      environment = commonEnv;
      volumes = [
        "${configDir}/jellyfin:/config"
        "${mediaDir}:/data/media" # Library root
      ];
    };

    # --- Prowlarr (Indexer Manager) ---
    # Handles indexers for Sonarr/Radarr
    prowlarr = {
      image = "lscr.io/linuxserver/prowlarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      environment = commonEnv;
      volumes = [
        "${configDir}/prowlarr:/config"
      ];
      # Port 9696 is internal to the network, exposed via Caddy if needed
    };

    # --- Sonarr (TV Shows) ---
    sonarr = {
      image = "lscr.io/linuxserver/sonarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      environment = commonEnv;
      volumes = [
        "${configDir}/sonarr:/config"
        "${mediaDir}:/data/media" # Needs access to move files
        "${mediaDir}/downloads:/data/downloads" # Access to downloads
      ];
    };

    # --- Radarr (Movies) ---
    radarr = {
      image = "lscr.io/linuxserver/radarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      environment = commonEnv;
      volumes = [
        "${configDir}/radarr:/config"
        "${mediaDir}:/data/media"
        "${mediaDir}/downloads:/data/downloads"
      ];
    };

    # --- QBittorrent (Download Client) ---
    qbittorrent = {
      image = "lscr.io/linuxserver/qbittorrent:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      environment = commonEnv // {
        WEBUI_PORT = "8080";
      };
      volumes = [
        "${configDir}/qbittorrent:/config"
        "${mediaDir}/downloads:/data/downloads"
      ];
      # Expose the WebUI port to the host if you want direct access, 
      # otherwise Caddy handles it.
      # ports = [ "8080:8080" ]; 
    };
  };

  # --- Persistence ---
  # Ensure directories exist with correct permissions (UID 1000)
  systemd.tmpfiles.rules = [
    "d ${mediaDir} 0775 1000 1000 - -"
    "d ${mediaDir}/movies 0775 1000 1000 - -"
    "d ${mediaDir}/tv 0775 1000 1000 - -"
    "d ${mediaDir}/downloads 0775 1000 1000 - -"
    "d ${configDir}/jellyfin 0755 1000 1000 - -"
    "d ${configDir}/sonarr 0755 1000 1000 - -"
    "d ${configDir}/radarr 0755 1000 1000 - -"
    "d ${configDir}/prowlarr 0755 1000 1000 - -"
    "d ${configDir}/qbittorrent 0755 1000 1000 - -"
  ];
}