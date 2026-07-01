{ config, pkgs, ... }:

let
  configDir = "/var/lib/homelab/config";
in
{
  systemd.tmpfiles.rules = [
    "d ${configDir}/omnigent 0755 root root - -"
    "d ${configDir}/omnigent/data 0755 root root - -"
    "d ${configDir}/omnigent/db 0755 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    omnigent-postgres = {
      image = "postgres:16-alpine";
      autoStart = true;
      environment = {
        POSTGRES_USER = "omnigent";
        POSTGRES_DB = "omnigent";
        POSTGRES_PASSWORD = "omnigent"; # NOTE: Consider managing this with SOPS in the future
      };
      volumes = [
        "${configDir}/omnigent/db:/var/lib/postgresql/data"
      ];
      ports = [
        "10.88.0.1:5433:5432" # Bind to podman gateway
      ];
    };

    omnigent = {
      image = "ghcr.io/omnigent-ai/omnigent-server:latest";
      autoStart = true;
      dependsOn = [ "omnigent-postgres" ];
      environment = {
        # Using podman gateway IP to reach the mapped port 5433
        DATABASE_URL = "postgresql+psycopg://omnigent:omnigent@10.88.0.1:5433/omnigent";
        HOST = "0.0.0.0";
        PORT = "8000";
        OMNIGENT_DOMAIN = "omni.tongatime.us";
        OMNIGENT_ADMIN_CREDENTIALS_PATH = "/data/admin-credentials";
        ARTIFACT_DIR = "/data/artifacts";
        OMNIGENT_AUTH_ENABLED = "1";
      };
      ports = [
        "127.0.0.1:8000:8000"
      ];
      volumes = [
        "${configDir}/omnigent/data:/data"
      ];
    };
  };
}
