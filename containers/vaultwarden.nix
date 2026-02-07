{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server:latest";
    autoStart = true;
    
    # Map Host Port 8222 -> Container Port 80
    ports = [ "8222:80" ];

    volumes = [
      "/var/lib/vaultwarden:/data"
      # Mount the admin token secret
        "/run/secrets/vaultwarden_admin_token:/run/secrets/vaultwarden_admin_token:ro"
    ];

    environment = {
      # Security settings
      SIGNUPS_ALLOWED = "true";
      INVITATIONS_ALLOWED = "true";
            
      # Admin Portal (Required for first-time setup)
      ADMIN_TOKEN_FILE = "/run/secrets/vaultwarden_admin_token";

      # Experimental Features
      EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
    };
  };

  # Define the Secrets in sops
  sops.secrets.vaultwarden_admin_token = {
    owner = "root"; # Podman runs as root
  };

  # Ensure the data directory exists with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/vaultwarden 0755 root root - -"
  ];
}