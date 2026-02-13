{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.postgres = {
    image = "postgres:16"; # Version 16 provides better performance for large datasets
    autoStart = true;
    
    # Map Host Port 5432 -> Container Port 5432
    # If 5432 is taken, change the left side (e.g., "5433:5432")
    ports = [ "5432:5432" ];

    # PERFORMANCE TUNING FOR DATA SCIENCE (~300M Rows)
    # 1. shared_buffers: Cache more data in RAM (Set to ~25% of total System RAM)
    # 2. work_mem: Increase for complex sorts/joins (Critical for Data Science queries)
    # 3. maintenance_work_mem: Speed up index creation and vacuuming
    # 4. max_parallel_workers: Utilize multiple cores for big queries
    cmd = [ 
      "postgres"
      "-c" "shared_buffers=32GB" 
      "-c" "work_mem=64MB"
      "-c" "maintenance_work_mem=512MB"
      "-c" "effective_cache_size=12GB"
      "-c" "max_worker_processes=8"
      "-c" "max_parallel_workers_per_gather=4"
    ];

    # CRITICAL: Postgres needs shared memory for parallel queries.
    # The default 64MB is insufficient for 300M rows and will cause crashes.
    extraOptions = [ "--shm-size=4g" ];

    volumes = [
      "/var/lib/postgres:/var/lib/postgresql/data"
      "${config.sops.secrets.postgres_password.path}:/run/secrets/postgres_password:ro"
    ];

    environment = {
      POSTGRES_USER = "datascience";
      POSTGRES_DB = "analytics";
      POSTGRES_PASSWORD_FILE = "/run/secrets/postgres_password";
      PGDATA = "/var/lib/postgresql/data";
    };
  };

  # Define the Secret
  sops.secrets.postgres_password = {
    owner = "root"; # Podman runs as root
  };

  # Ensure data directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/postgres 0750 root root - -"
  ];
}