{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.pgadmin = {
    image = "dpage/pgadmin4:latest";
    autoStart = true;
    ports = [ "5050:80" ]; # Expose Web UI on port 5050
    environment = {
      PGADMIN_DEFAULT_EMAIL = "admin@tongatime.us"; 
      PGADMIN_DEFAULT_PASSWORD_FILE = "/run/secrets/pgadmin_password";
      PGADMIN_LISTEN_PORT = "80";
    };
    volumes = [
      "/var/lib/pgadmin:/var/lib/pgadmin"
      "${config.sops.secrets.pgadmin_password.path}:/run/secrets/pgadmin_password:ro"
    ];
  };

  # Define the secret for the login password
  sops.secrets.pgadmin_password = {
    owner = "root"; # Podman runs as root
  };

  # Ensure the data directory exists with correct permissions (UID 5050 is used by pgAdmin)
  systemd.tmpfiles.rules = [
    "d /var/lib/pgadmin 0755 5050 5050 - -"
  ];
}