{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:latest";
    autoStart = true;
    # Map Host Port 13378 -> Container Port 80
    ports = [ "13378:80" ];
    
    volumes = [
      "/var/lib/audiobookshelf/config:/config"
      "/var/lib/audiobookshelf/metadata:/metadata"
      # We organize media under the existing /var/lib/media directory defined in media.nix
      "/var/lib/media/audiobooks:/audiobooks"
      "/var/lib/media/podcasts:/podcasts"
    ];

    environment = {
      TZ = "America/Chicago";
      # Run as the same user as your media stack (1000:1000) for file permission consistency
      AUDIOBOOKSHELF_UID = "1000";
      AUDIOBOOKSHELF_GID = "1000";
    };
  };

  # Create necessary directories with correct permissions (User 1000)
  systemd.tmpfiles.rules = [
    "d /var/lib/audiobookshelf/config 0755 1000 1000 - -"
    "d /var/lib/audiobookshelf/metadata 0755 1000 1000 - -"
    "d /var/lib/media/audiobooks 0775 1000 1000 - -"
    "d /var/lib/media/podcasts 0775 1000 1000 - -"
  ];
}