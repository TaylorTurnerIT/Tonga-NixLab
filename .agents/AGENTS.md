# ❄️ Agent Guidelines for Tonga NixLab

Welcome, Agent. This file outlines the architectural constraints, network boundaries, and repository practices required to maintain the stability and security of the **Tonga NixLab** infrastructure.

---

## 🏗️ 1. Architecture Overview
This is a hybrid system split between two hosts:
1. **Homelab (`homelab`):** Runs pure, immutable **NixOS** (NixOS 25.05). All local/private services run here.
2. **VPS Gateway (`vps-proxy`):** Runs **Ubuntu** bootstrapped with **Nix + Home Manager**. It acts as the public-facing bastion host/ingress gateway.

---

## 🔒 2. Zero-Trust Network & Security Boundaries
A strict security model is enforced across the entire infrastructure:
* **Zero Public Ports on Homelab:** The home server is completely closed to the public internet. It only allows traffic from the local network and the **Tailscale VPN mesh** (`100.64.0.0/10`).
* **Ingress Routing (VPS Caddy):**
  * **Layer 4 (TCP Proxying):** Raw TCP streams (Minecraft range `25565-25600`) are proxied over Tailscale to the home server.
  * **Layer 7 (HTTP/HTTPS Proxying):** Public web traffic (`tv.*`, `photos.*`, `vault.*`, `audiobooks.*`, `foundry.*`) is reverse-proxied over the Tailscale VPN to the home server's internal ports.
* **Internal-Only Restrictions (Homelab Caddy):**
  * Core administration GUIs (Proxmox, pgAdmin, Gitea), AI tools (`omni.*`, `litellm.*`, `ai.*`), and sensitive downloader/database workloads (`sonarr.*`, `radarr.*`, `qbit.*`, `mysql.*`, `postgres.*`) are restricted.
  * You **MUST** protect all internal-only subdomains in `network/caddy.nix` with the `@external` IP restriction block:
    ```caddy
    @external {
      not remote_ip 100.64.0.0/10 192.168.0.0/16 127.0.0.0/8
    }
    respond @external "Access Denied - Internal Only" 403
    ```

---

## 📦 3. Container Backends (Podman vs. Docker)
* **Podman:** Used for all **system-defined, declarative OCI containers** managed via NixOS configurations (`virtualisation.oci-containers`).
* **Docker:** Enabled *only* for the **Pterodactyl Wings game server manager** to dynamically spawn, manage, and sandbag user game servers.
* **Security Rule:** Avoid mounting raw sockets (like `/var/run/podman/podman.sock`) directly inside containers. When read-only metrics/status checks are needed (e.g. for the Homepage dashboard), utilize a socket-proxy wrapper like `tecnativa/docker-socket-proxy` to enforce read-only API access.

---

## 🔑 4. Secret Management
* **SOPS-Nix:** Do **NOT** store plain-text credentials in the repository. All secrets are managed in `secrets/secrets.yaml` via SOPS.
* Reference secrets using `config.sops.secrets.<secret_name>.path` in Nix configurations.

---

## 🚀 5. Deployment Procedures
* **Homelab (NixOS):** Apply configurations by running `./deploy-nix.sh`. Wipes and reinstalls can be performed using `./deploy-nix.sh --install`.
* **VPS Gateway (Ubuntu):** Bootstrap and apply the Home Manager configurations using `./deploy-vps.sh`.
* **DNS Settings:** Declarative DNS changes are managed using DNSControl from `network/dns_zones.yaml`. Sync records with Cloudflare via `./deploy-dns.sh`.

---

## 📝 6. Key Invariants for Future Work
When modifying code or creating new services:
1. **Network Default is Private:** Point new domains to the Tailscale IP (`100.73.119.72`) in `dns_zones.yaml` and protect them with `@external` blocks in `network/caddy.nix` by default. Do not proxy new web apps publicly unless explicitly instructed.
2. **Container Permissions:** Pre-create host data directories using `systemd.tmpfiles.rules` with appropriate ownership (e.g. user `1000` for media services) to prevent permission conflicts.
3. **No Unpinned Images:** Avoid using `:latest` tags. Prefer specific semantic tags or SHA256 digests for predictability and reproducibility.
