# Deploying New Containers

This document outlines the standard procedure and lessons learned for adding and deploying new OCI (Podman) containers to the NixOS homelab.

## 1. Container Configuration
Create a new file in the `containers/` directory (e.g., `containers/myapp.nix`). Define the container under `virtualisation.oci-containers.containers`.

**Important Lessons:**
* **Environment Variables vs Volume Mounts**: Avoid mounting static config files (like `settings.yml` or `.json`) as read-only volumes directly from the Nix store if the container expects to be able to modify or `chown` them on startup (this caused startup crashes for apps like SearXNG). Whenever possible, use environment variables for configuration.
* **Data Directories & Permissions**: If your container needs persistent storage, mount it to the host (e.g., `volumes = [ "${configDir}/myapp/data:/data" ];`). Be aware that if Podman creates the directory automatically, it will be owned by `root:root`. If the container runs as a non-root user, you will run into "Permission Denied" errors. You can pre-create these directories with the correct ownership using Nix `systemd.tmpfiles.rules` if necessary.

## 2. Port Management & Collisions
Containers running in the host network or sharing the same network namespace might try to bind to default overlapping ports (e.g., 8080 or 7000).
* Always verify that the internal application port does not conflict with existing services.
* Use application-specific environment variables to change the default listening port if a collision occurs (e.g., `SEARXNG_PORT = "8081";`).

## 3. VPN Routing (Gluetun)
To route a container's traffic exclusively through a VPN (like Gluetun), add the following extra option:
```nix
extraOptions = [ "--network=container:gluetun" ];
```

**CRITICAL RULES for VPN-Routed Containers:**
* When a container shares another container's network namespace (e.g., Gluetun's), **it loses its own network namespace**. 
* You **cannot** expose ports in the routed container using the `ports = [ ... ]` directive. Doing so will result in an error.
* Instead, if you need to access a service that is routed through the VPN, you must either access it directly over the local network via the VPN container's IP/ports, or map the port on the *VPN container itself* (i.e. add the port to Gluetun's `ports` list).
* Beware of port collisions *within* the VPN network namespace. Multiple containers routing through the same VPN cannot listen on the same port.

## 4. Reverse Proxy (Caddy)
To expose the new container, update `network/caddy.nix` with a new proxy block.

**Internal / Tailscale Restricting:**
If the service should strictly be available on the internal network (Tailscale + Local) and blocked from external IPs (even if routed through a public Cloudflare DNS), use the `@external` IP matcher:

```caddy
"app.${domain}" = {
  useACMEHost = domain;
  extraConfig = ''
    @external {
      not remote_ip 100.64.0.0/10 192.168.0.0/16 127.0.0.0/8
    }
    respond @external "Access Denied - Internal Only" 403
    
    reverse_proxy http://127.0.0.1:8081
  '';
};
```

## 5. DNS Configuration
Before deploying, make sure the new subdomain exists in DNS!
1. Add the domain to `network/dns_zones.yaml`.
2. For internal-only services, point the `target` to the **Tailscale IP** of the homelab (e.g., `100.73.119.72`) and ensure `proxied: false`.
3. Apply the DNS update by running:
   ```bash
   ./deploy-dns.sh
   ```

## 6. Deployment
1. Ensure your new container file is imported in `containers/default.nix`.
2. Deploy the Nix configuration to the homelab:
   ```bash
   ./deploy-nix.sh
   ```
3. Check the status if needed via `ssh homelab sudo systemctl status podman-myapp.service`.
