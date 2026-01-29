{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.mysql = {
    image = "mysql:oraclelinux9";
    autoStart = true;
    
    # Map Host Port 3360 -> Container Port 3306
    ports = [ "3360:3306" ];

    volumes = [
      "/var/lib/mysql:/var/lib/mysql"
      "${config.sops.secrets.mysql_root_password.path}:/run/secrets/mysql_root_password:ro"
    ];

    environment = {
        MYSQL_ROOT_PASSWORD_FILE = "/run/secrets/mysql_root_password";
        MYSQL_TCP_PORT = "3306";
    };
  };

  # Define the Secrets in sops
  sops.secrets.mysql_root_password = {
    owner = "root"; # Podman runs as root
  };

  # Ensure the data directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/mysql 0755 root root - -"
  ];
}