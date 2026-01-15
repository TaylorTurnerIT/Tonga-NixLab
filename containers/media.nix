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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists ${podmanNetwork} || \
      ${pkgs.podman}/bin/podman network create --subnet ${podmanSubnet} ${podmanNetwork}
    '';
    # Force this service to run BEFORE the containers
    before = [ 
      "podman-jellyfin.service"
      "podman-prowlarr.service"
      "podman-sonarr.service"
      "podman-radarr.service"
      "podman-qbittorrent.service"
    ];
    # Ensure the containers actually require this service to be successful
    requiredBy = [ 
      "podman-jellyfin.service"
      "podman-prowlarr.service"
      "podman-sonarr.service"
      "podman-radarr.service"
      "podman-qbittorrent.service"
    ];
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

    # --- Readarr (Books & Audiobooks) ---
    readarr = {
      image = "lscr.io/linuxserver/readarr:develop"; # Readarr recommends 'develop' tag
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "8787:8787" ]; 
      environment = commonEnv;
      volumes = [
        "${configDir}/readarr:/config"
        "${mediaDir}:/data/media"
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
    "d ${configDir}/readarr 0755 1000 1000 - -"
  ];
}