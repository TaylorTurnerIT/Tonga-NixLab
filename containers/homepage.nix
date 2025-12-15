{ config, pkgs, ... }:

{
    virtualisation.oci-containers.containers.homepage = {
        # The Bodyguard (Socket Proxy)
        # This is the security layer that sits between the real socket and Homepage since it needs socket access.
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

        /*
        Homepage Container
        This container runs homepage using the ghcr.io/gethomepage/homepage:latest image.

        Configuration:
        - Image:
            - Uses the latest ghcr.io/gethomepage/homepage image from GitHub Container Registry.
        - Ports:
            - Maps port 3000 on the host to port 3000 in the container.
            - Host: 3000 <--> Container: 3000
        - Volumes:
            - Maps /var/lib/homepage on the host to /data in the container for persistent storage.
            - Host:/var/lib/homepage <--> Container:/data
        - Environment Variables:
            - HOMEPAGE_ALLOWED_HOSTS: Set to "tongatime.us" to allow access.
        - Extra Options:
            - Uses host networking to ensure connectivity to the socket proxy.
        */
        homepage = {
        image = "ghcr.io/gethomepage/homepage:latest";
        autoStart = true;
        ports = [ "3000:3000" ];
        volumes = [
            "/var/lib/homepage:/app/config"
            # REMOVED: Direct socket mount
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
        systemd.tmpfiles.rules = [
                "d /var/lib/homepage 0755 1000 100 10d"
    
        ];
}


