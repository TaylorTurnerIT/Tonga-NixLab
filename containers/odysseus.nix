{ config, pkgs, ... }:

let
  configDir = "/var/lib/homelab/config";
  podmanNetwork = "media_net";
in
{
  # --- Setup SearXNG Custom Settings ---
  # We generate the settings.yml here so that SearXNG runs on 8081
  # to avoid conflicting with qBittorrent on 8080 inside the gluetun network namespace.
  systemd.tmpfiles.rules = [
    "d ${configDir}/searxng 0755 root root - -"
    "d ${configDir}/searxng/data 0755 root root - -"
    "f ${configDir}/searxng/settings.yml 0644 root root - use_default_settings: true\nserver:\n  port: 8081\n  bind_address: \"0.0.0.0\"\n  secret_key: \"odysseus_nixos_deploy_secret\"\nsearch:\n  formats:\n    - html\n    - json\n"
  ];

  virtualisation.oci-containers.containers = {
    # --- SearXNG (via VPN) ---
    searxng = {
      image = "docker.io/searxng/searxng:2026.5.31-7159b8aed";
      autoStart = true;
      dependsOn = [ "gluetun" ];
      # Run in gluetun network namespace so traffic goes through VPN
      extraOptions = [ "--network=container:gluetun" ];
      
      environment = {
        SEARXNG_BASE_URL = "https://ai.tongatime.us/";
      };
      volumes = [
        "${configDir}/searxng/data:/etc/searxng"
        "${configDir}/searxng/settings.yml:/etc/searxng/settings.yml:ro"
      ];
    };

    # --- Odysseus ---
    odysseus = {
      image = "localhost/odysseus:latest";
      autoStart = true;
      # Connect to the media_net so it can reach gluetun and other services
      extraOptions = [ "--network=${podmanNetwork}" ];
      
      environment = {
        # SearXNG is reachable via the gluetun container on port 8081
        SEARXNG_INSTANCE = "http://gluetun:8081";
      };
      ports = [
        "7000:7000"
      ];
      volumes = [
        "${configDir}/odysseus/data:/app/data"
        "${configDir}/odysseus/logs:/app/logs"
      ];
    };
  };
}
