{ config, pkgs, ... }:

let
  configDir = "/var/lib/homelab/config";
  podmanNetwork = "media_net";
in
{
  /*
    Vane — AI-powered answering engine (slim/lite mode)

    Slim image: no bundled SearxNG. Points at the existing SearxNG
    instance exposed by the gluetun container on media_net port 8081.

    Port 3000 is bound on the host so Caddy can reverse proxy it.
  */

  systemd.tmpfiles.rules = [
    "d ${configDir}/vane/data 0755 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    vane = {
      image = "docker.io/itzcrazykns1337/vane:slim-latest";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];

      environment = {
        # SearxNG reachable via gluetun container on media_net
        SEARXNG_API_URL = "http://gluetun:8081";
      };

      ports = [
        "3100:3000"  # host:3100 → container:3000 (host:3000 is taken by Homepage)
      ];

      volumes = [
        "${configDir}/vane/data:/home/vane/data"
      ];
    };
  };
}
