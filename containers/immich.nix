{ config, pkgs, ... }:

let
  podmanNetwork = "immich_net";
  podmanSubnet = "10.90.0.0/16";
  
  uploadDir = "/var/lib/media/photos";
  dbDir = "/var/lib/immich/postgres";
  
  commonEnv = {
    PUID = "1000";
    PGID = "1000";
    DB_HOSTNAME = "immich-postgres";
    DB_USERNAME = "postgres";
    DB_DATABASE_NAME = "immich";
    REDIS_HOSTNAME = "immich-redis";
  };

in {
  sops.secrets.immich_db_password = { owner = "root"; };

  # --- Networking ---
  systemd.services."create-${podmanNetwork}-network" = {
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${pkgs.podman}/bin/podman network exists ${podmanNetwork} || \
      ${pkgs.podman}/bin/podman network create --subnet ${podmanSubnet} ${podmanNetwork}
    '';
    # [Fix] Explicitly force this to run BEFORE the containers
    before = [
      "podman-immich-server.service"
      "podman-immich-machine-learning.service"
      "podman-immich-redis.service"
      "podman-immich-postgres.service"
    ];
    # [Fix] Ensure containers fail if this fails
    requiredBy = [
      "podman-immich-server.service"
      "podman-immich-machine-learning.service"
      "podman-immich-redis.service"
      "podman-immich-postgres.service"
    ];
  };

  # --- Persistence ---
  systemd.tmpfiles.rules = [
    "d ${uploadDir} 0775 1000 1000 - -"
    "d ${dbDir} 0755 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers = {
    
    # 1. Immich Server
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:release";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "2283:3001" ]; 
      environment = commonEnv // {
        DB_PASSWORD_FILE = "/run/secrets/immich_db_password";
        IMMICH_MACHINE_LEARNING_URL = "http://immich-machine-learning:3003";
      };
      volumes = [
        "${uploadDir}:/usr/src/app/upload"
        "${config.sops.secrets.immich_db_password.path}:/run/secrets/immich_db_password:ro"
      ];
      # Depends on DB/Redis readiness
      dependsOn = [ "immich-redis" "immich-postgres" ];
    };

    # 2. Machine Learning
    immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:release";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=immich-machine-learning" ];
      environment = commonEnv;
      volumes = [
        "model-cache:/cache"
      ];
    };

    # 3. Redis
    immich-redis = { 
      image = "redis:8.6-rc1-trixie";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=immich-redis" ];
    };

    # 4. Postgres
    immich-postgres = {
      image = "tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=immich-postgres" ];
      environment = {
        POSTGRES_PASSWORD_FILE = "/run/secrets/immich_db_password";
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };
      volumes = [
        "${dbDir}:/var/lib/postgresql/data"
        "${config.sops.secrets.immich_db_password.path}:/run/secrets/immich_db_password:ro"
      ];
    };
  };
}