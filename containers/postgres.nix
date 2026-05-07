# Tonga-NixLab/containers/postgres.nix
{ config, pkgs, ... }:
{
  virtualisation.oci-containers.containers.postgres = {
    image = "postgres:16";
    autoStart = true;
    ports = [ "5432:5432" ];
    
    # Keeping your high-performance tuning for the 300M row dataset
    cmd = [ 
      "postgres"
      "-c" "shared_buffers=8GB" # Scaled back slightly to leave room for the host
      "-c" "work_mem=64MB"
      "-c" "maintenance_work_mem=512MB"
      "-c" "effective_cache_size=12GB"
    ];

    extraOptions = [ "--shm-size=4g" ];

    volumes = [
      "/var/lib/postgres:/var/lib/postgresql/data"
      "${config.sops.secrets.postgres_password.path}:/run/secrets/postgres_password:ro"
    ];

    environment = {
      POSTGRES_USER = "atticd";
      POSTGRES_DB   = "atticd";
      POSTGRES_PASSWORD_FILE = "/run/secrets/postgres_password";
    };
  };

  sops.secrets.postgres_password = { owner = "root"; };
}