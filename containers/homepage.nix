{ config, pkgs, ... }:

{
  virtualisation.oci-containers.containers = {
    
    # The Bodyguard (Socket Proxy)
    # This sits between the real socket and Homepage for security
    socket-proxy = {
      image = "tecnativa/docker-socket-proxy:latest";
      autoStart = true;
      environment = {
        CONTAINERS = "1"; # Allow viewing list
        IMAGES = "1";     # Allow viewing images
        POST = "0";       # BLOCK all write commands (Crucial!)
      };
      volumes = [ "/var/run/podman/podman.sock:/var/run/docker.sock:ro" ];
      extraOptions = [ "--network=host" ]; 
    };

    # Homepage
    homepage = {
      image = "ghcr.io/gethomepage/homepage:latest";
      autoStart = true;
      ports = [ "3000:3000" ];
      volumes = [
        "/var/lib/homepage:/app/config"
      ];
      environment = {
        # Point to the proxy instead of a file
        DOCKER_HOST = "tcp://127.0.0.1:2375"; 
        HOMEPAGE_ALLOWED_HOSTS = "tongatime.us";
      };
      # Make sure it can reach the proxy (localhost)
      extraOptions = [ "--network=host" ]; 
    };
  };
}