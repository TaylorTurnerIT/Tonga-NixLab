{ config, pkgs, ... }:

let
  configDir = "/var/lib/homelab/config";
in
{
  systemd.tmpfiles.rules = [
    "d ${configDir}/vane 0755 root root - -"
    "d ${configDir}/vane/data 0755 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    vane = {
      image = "itzcrazykns1337/vane:slim-latest";
      autoStart = true;
      dependsOn = [ "gluetun" "searxng" ];
      # Connect to the media_net so it can reach gluetun and the SearXNG instance
      extraOptions = [ "--network=media_net" ];
      
      environment = {
        # Point to the existing SearXNG instance running in the gluetun network namespace
        SEARXNG_API_URL = "http://gluetun:8081";
      };
      
      ports = [
        "127.0.0.1:3002:3000" # Map to a unique port on the host
      ];
      
      volumes = [
        "${configDir}/vane/data:/home/vane/data"
      ];
    };
  };
}
