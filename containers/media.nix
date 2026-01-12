{ config, pkgs, ... }:

let
  podmanNetwork = "media_net";
  podmanSubnet = "10.89.0.0/16"; 
  
  commonEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = "UTC";
  };

  mediaDir = "/var/lib/media";
  configDir = "/var/lib/config";
in {
  
  # --- Networking ---
  systemd.services."create-${podmanNetwork}-network" = {
    script = ''
      ${pkgs.podman}/bin/podman network exists ${podmanNetwork} || \
      ${pkgs.podman}/bin/podman network create --subnet ${podmanSubnet} ${podmanNetwork}
    '';
    wantedBy = [ "multi-user.target" ];
  };

  # --- Firewall ---
  # Allow the media containers to talk to the host (Required for DNS)
  networking.firewall.extraCommands = ''
    iptables -A INPUT -s ${podmanSubnet} -j ACCEPT
  '';

  virtualisation.oci-containers.containers = {

    # --- Jellyfin ---
    jellyfin = {
      image = "lscr.io/linuxserver/jellyfin:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8096:8096" ]; 
      environment = commonEnv;
      volumes = [
        "${configDir}/jellyfin:/config"
        "${mediaDir}:/data/media"
      ];
    };

    # --- Prowlarr ---
    prowlarr = {
      image = "lscr.io/linuxserver/prowlarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "9696:9696" ]; 
      environment = commonEnv;
      volumes = [
        "${configDir}/prowlarr:/config"
      ];
    };

    # --- Sonarr ---
    sonarr = {
      image = "lscr.io/linuxserver/sonarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8989:8989" ]; 
      environment = commonEnv;
      volumes = [
        "${configDir}/sonarr:/config"
        "${mediaDir}:/data/media"
        "${mediaDir}/downloads:/data/downloads"
      ];
    };

    # --- Radarr ---
    radarr = {
      image = "lscr.io/linuxserver/radarr:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "7878:7878" ]; 
      environment = commonEnv;
      volumes = [
        "${configDir}/radarr:/config"
        "${mediaDir}:/data/media"
        "${mediaDir}/downloads:/data/downloads"
      ];
    };

    # --- QBittorrent ---
    qbittorrent = {
      image = "lscr.io/linuxserver/qbittorrent:latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8080:8080" ]; 
      environment = commonEnv // {
        WEBUI_PORT = "8080";
      };
      volumes = [
        "${configDir}/qbittorrent:/config"
        "${mediaDir}/downloads:/data/downloads"
      ];
    };
  };

  # --- Persistence ---
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