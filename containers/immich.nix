{ config, pkgs, ... }:

let
  podmanNetwork = "immich_net";
  podmanSubnet = "10.90.0.0/16";
  
  # Host Paths (Where data lives on your NixOS server)
  hostUploadDir = "/var/lib/media/photos";
  hostDbDir = "/var/lib/immich/postgres";
  
  # Configuration matching your provided .env
  commonEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ = "America/Chicago";
    IMMICH_VERSION = "v2";
    
    # Database Config
    DB_HOSTNAME = "immich-postgres";
    DB_USERNAME = "postgres";
    DB_DATABASE_NAME = "immich";
    
    # Redis (Valkey) Config
    REDIS_HOSTNAME = "immich_redis"; # Must match container name below
  };

in {
  sops.secrets.immich_db_password = { owner = "root"; };

  # --- Networking ---
  systemd.services."create-${podmanNetwork}-network" = {
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${pkgs.podman}/bin/podman network exists ${podmanNetwork} || \
      ${pkgs.podman}/bin/podman network create ${podmanNetwork}
    '';
    # Ensure network is up before containers
    before = [
      "podman-immich-server.service"
      "podman-immich-machine-learning.service"
      "podman-immich_redis.service" # Note the underscore to match official name
      "podman-immich_postgres.service"
    ];
    requiredBy = [
      "podman-immich-server.service"
      "podman-immich-machine-learning.service"
      "podman-immich_redis.service"
      "podman-immich_postgres.service"
    ];
  };

  # --- Persistence ---
  systemd.tmpfiles.rules = [
    "d ${hostUploadDir} 0775 1000 1000 - -"
    "d ${hostDbDir} 0755 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers = {
    
    # 1. Immich Server
    immich-server = {
      image = "ghcr.io/immich-app/immich-server:v2"; # Matches IMMICH_VERSION=v2
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      ports = [ "2283:2283" ]; # Official Port
      environment = commonEnv // {
        DB_PASSWORD_FILE = "/run/secrets/immich_db_password";
        IMMICH_MACHINE_LEARNING_URL = "http://immich_machine_learning:3003";
      };
      volumes = [
        # [CRITICAL CHANGE] Official guide mounts to /data, not /usr/src/app/upload
        "${hostUploadDir}:/data" 
        # "/etc/localtime:/etc/localtime:ro"
        "${config.sops.secrets.immich_db_password.path}:/run/secrets/immich_db_password:ro"
      ];
      dependsOn = [ "immich_redis" "immich_postgres" ];
    };

    # 2. Machine Learning
    immich_machine_learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:v2";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      environment = commonEnv;
      volumes = [ "model-cache:/cache" ];
    };

    # 3. Redis (Actually Valkey now)
    immich_redis = {
      # Official guide uses Valkey 9
      image = "docker.io/valkey/valkey:9"; 
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" "--hostname=immich_redis" ];
      # Healthcheck (Podman style)
      cmd = [ "valkey-server" ];
    };

    # 4. Postgres (VectorChord)
    immich_postgres = {
      # Official guide uses this specific VectorChord image
      image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
      autoStart = true;
      extraOptions = [ 
        "--network=${podmanNetwork}" 
        "--hostname=immich-postgres" 
        "--shm-size=128m" # Required by official guide
      ];
      environment = {
        POSTGRES_PASSWORD_FILE = "/run/secrets/immich_db_password";
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums"; # Required by official guide
      };
      volumes = [
        "${hostDbDir}:/var/lib/postgresql/data"
        "${config.sops.secrets.immich_db_password.path}:/run/secrets/immich_db_password:ro"
      ];
    };
  };
}