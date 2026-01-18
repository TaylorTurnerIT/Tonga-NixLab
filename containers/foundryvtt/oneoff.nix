# containers/foundryvtt/oneoff.nix
{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.foundry_oneoff = {
    image = "felddy/foundryvtt:release-12";
    autoStart = true;
    ports = [ "30002:30000" ];
    volumes = [
      "/var/lib/foundry/oneoff:/data"
      "${config.sops.templates."foundry_secrets.json".path}:/run/secrets/config.json:ro"
    ];
    environment = {
      FOUNDRY_TELEMETRY = "false";
      FOUNDRY_HOSTNAME = "foundry.tongatime.us";
      FOUNDRY_ROUTE_PREFIX = "oneoff";
      FOUNDRY_PROXY_SSL = "true";
      FOUNDRY_PROXY_PORT = "443";
      FOUNDRY_MINIFY_STATIC_FILES = "true";


        FOUNDRY_UID = "1000";
        FOUNDRY_GID = "1000";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/foundry/oneoff 0755 1000 1000 - -"
  ];
}