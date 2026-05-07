# containers/attic.nix
{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers."attic" = {
    image = "ghcr.io/zhaofengli/attic:latest"; # Use a digest pin in production
    environmentFiles = [
      config.sops.secrets.attic_env.path
    ];
    environment = {
      ATTIC_SERVER_LISTEN = "[::]:8085";
    };
    volumes = [
      "/var/lib/attic:/var/lib/attic"
    ];
    extraOptions = [
      "--network=host"
    ];
    dependsOn = [ "postgres" ];
  };

  services.caddy.virtualHosts."cache.tongatime.us" = {
    useACMEHost = "tongatime.us";
    extraConfig = ''
      reverse_proxy 127.0.0.1:8085
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/attic 0755 root root - -"
  ];
}
