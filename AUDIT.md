Security Audit & Remediation Plan for NixServer
Executive Summary
This plan addresses 11 security vulnerabilities discovered in your nixserver infrastructure, organized into 4 tiers of increasing complexity:
Tier 1: Quick wins (< 1 hour) - 4 vulnerabilities
Tier 2: Moderate changes (few hours) - 4 vulnerabilities
Tier 3: Significant refactors (days) - 2 CRITICAL vulnerabilities + 1 medium
Tier 4: Major architectural overhaul (weeks) - Long-term hardening
Most Critical Issues:
Containers running as root (CRITICAL) - container escape = full host compromise
Missing RCON password (CRITICAL) - unauthenticated remote console access
Docker socket exposure (CRITICAL) - container can control all other containers
TIER 1: Quick Wins (< 1 hour)
Impact: Address 4 vulnerabilities with simple configuration changes
1.1 Add RCON Password to Minecraft Server
Severity: CRITICAL | Effort: 5 minutes Problem: RCON is enabled but no password is set (containers/minecraft.nix:65) Solution:
Add RCON password to SOPS secrets
Reference in minecraft.nix configuration
Deploy changes
Files to modify:
secrets/secrets.yaml - Add encrypted minecraft_rcon_password entry
configuration.nix:36-38 - Add new sops secret definition:
sops.secrets.minecraft_rcon_password = {
  owner = "root";
};
containers/minecraft.nix:66 - Add after line 65:
RCON_PASSWORD = "${config.sops.secrets.minecraft_rcon_password.path}";
Validation:
./deploy-nix.sh
podman exec minecraft env | grep RCON_PASSWORD
1.2 Fix Secret File Permissions
Severity: MEDIUM | Effort: 2 minutes Problem: Encrypted secret files are world-readable (644 permissions) Solution: Restrict permissions to owner-only (600)
chmod 600 secrets/dns_creds.json
chmod 600 secrets/secrets.yaml
Validation:
ls -la secrets/
# Should show: -rw-------
1.3 Add HTTP Security Headers
Severity: MEDIUM | Effort: 15 minutes Problem: Missing security headers expose services to XSS, clickjacking, MIME-sniffing Files to modify:
network/caddy.nix:76-85 - Add to Proxmox virtualHost
network/caddy.nix:93-97 - Add to Homepage virtualHost
Configuration to add (insert in both virtualHost extraConfig blocks):
extraConfig = ''
  header {
    X-Frame-Options "DENY"
    X-Content-Type-Options "nosniff"
    Referrer-Policy "strict-origin-when-cross-origin"
    Permissions-Policy "geolocation=(), microphone=(), camera=()"
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
  }

  # Existing reverse_proxy config...
'';
Validation:
./deploy-nix.sh
curl -I https://tongatime.us | grep -E "X-Frame|X-Content|Strict-Transport"
1.4 Pin Container Image Tags
Severity: HIGH | Effort: 20 minutes Problem: Using :latest tags creates supply chain risk and non-reproducible builds Files to modify:
containers/minecraft.nix:35
containers/homepage.nix:21
Solution: Replace :latest with SHA256 digests Get current digests:
podman pull itzg/minecraft-server:latest
podman pull ghcr.io/gethomepage/homepage:latest
podman images --digests | grep -E "minecraft-server|homepage"
Update configuration:
# Before
image = "itzg/minecraft-server:latest";
image = "ghcr.io/gethomepage/homepage:latest";

# After (use actual current digest)
image = "itzg/minecraft-server@sha256:<digest-from-above>";
image = "ghcr.io/gethomepage/homepage@sha256:<digest-from-above>";
Note: Add comment explaining how to update digests in future
TIER 2: Moderate Complexity (few hours)
Impact: Address 4 vulnerabilities with contained refactoring
2.1 Create Centralized Network Variables Module
Severity: MEDIUM | Effort: 1-2 hours Problem: Hardcoded IPs in multiple files (network/caddy.nix:79, vps/home.nix:22) Solution: Create reusable network variables module Files to create:
network/variables.nix:
{
  network = {
    tailscale = {
      homelab_ip = "100.73.119.72";
    };
    lan = {
      proxmox_ip = "192.168.4.36";
      proxmox_port = 8006;
    };
    domain = "tongatime.us";
  };
}
Files to modify:
flake.nix - Import variables module
network/caddy.nix:16 - Replace hardcoded domain
network/caddy.nix:79 - Use variable for Proxmox IP
vps/home.nix:22 - Use variable for Tailscale IP
Validation:
./deploy-nix.sh --dry-run
./deploy-nix.sh
curl -I https://proxmox.tongatime.us
2.2 Enable Nix Signature Verification
Severity: MEDIUM | Effort: 2-3 hours Problem: Package signature verification disabled (deploy-vps.sh:49, deploy-vps.sh:137) Files to modify:
deploy-vps.sh:48-53 - Remove require-sigs = false lines
deploy-vps.sh:137 - Remove --option require-sigs false
configuration.nix - Add binary cache configuration:
nix.settings = {
  substituters = [ "https://cache.nixos.org" ];
  trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  require-sigs = true;
};
Validation:
./deploy-vps.sh
nix store verify --all
2.3 Implement SSH Host Key Management
Severity: HIGH | Effort: 2-3 hours Problem: SSH host key checking disabled (deploy-vps.sh:113-114) - vulnerable to MITM attacks Solution: Create and use proper SSH known_hosts file Steps:
Collect host keys:
ssh-keyscan homelab > secrets/ssh_known_hosts
ssh-keyscan 129.153.13.212 >> secrets/ssh_known_hosts
Files to modify:
deploy-vps.sh:111-116 - Replace SSH config:
cat >> /root/.ssh/config <<'SSHCONFIG'
Host $TARGET_HOST
    IdentityFile /root/.ssh/$SSH_KEY_NAME
SSHCONFIG
deploy-vps.sh:135 - Remove NIX_SSHOPTS override or fix it:
export NIX_SSHOPTS="-i /root/.ssh/$SSH_KEY_NAME"
Containerfile:37-39 - Remove SSH config that disables checking
Mount known_hosts in container:
-v "$PWD/secrets/ssh_known_hosts:/root/.ssh/known_hosts:ro"
Validation:
./deploy-vps.sh  # Should succeed with proper verification
2.4 Replace TLS Insecure Skip Verify with Custom CA
Severity: MEDIUM | Effort: 2-3 hours Problem: TLS verification disabled for Proxmox (network/caddy.nix:81) Solution: Trust Proxmox's self-signed CA certificate Steps:
Extract Proxmox CA from Proxmox host: /etc/pve/pve-root-ca.pem
Add to SOPS secrets as proxmox_ca_cert
Files to modify:
secrets/secrets.yaml - Add Proxmox CA cert
configuration.nix:36-38 - Add sops secret:
sops.secrets.proxmox_ca_cert = {
  owner = "caddy";
  mode = "0400";
};
network/caddy.nix:79-82 - Replace with:
reverse_proxy https://192.168.4.36:8006 {
  transport http {
    tls_trusted_ca_certs ${config.sops.secrets.proxmox_ca_cert.path}
  }
}
Validation:
./deploy-nix.sh
curl -I https://proxmox.tongatime.us
journalctl -u caddy -n 50  # Check for TLS errors
TIER 3: Significant Refactor (1-2 days)
Impact: Addresses 2 CRITICAL + 1 MEDIUM vulnerabilities
3.1 Convert Containers to Rootless Mode ⚠️ PRIORITY 1
Severity: CRITICAL | Effort: 1-2 days Problem: Both containers run as root (containers/minecraft.nix:33 comment acknowledges this)
Container escape = full host compromise
Homepage container has Docker socket access as root
Solution Overview: This is already in your TODO.md:29. Requires coordinated changes across multiple files.
Phase 1: Minecraft Container Rootless (4-6 hours)
Files to modify:
containers/minecraft.nix:
virtualisation.oci-containers.containers.minecraft = {
  image = "itzg/minecraft-server@sha256:...";  # From Tier 1.4
  autoStart = true;

  # ADD THIS - specify non-root user
  user = "1000:1000";

  ports = [ "25565:25565" ];

  # Update volume with :U flag for UID mapping
  volumes = [ "/var/lib/minecraft:/data:U" ];

  environment = {
    # Existing config...
    RCON_PASSWORD = "${config.sops.secrets.minecraft_rcon_password.path}";

    # ADD THIS - tell container to run as UID/GID
    UID = "1000";
    GID = "1000";
  };
};

# Existing tmpfiles rule already sets correct ownership (line 78)
Testing:
./deploy-nix.sh
podman exec minecraft whoami  # Should NOT be root
podman inspect minecraft | jq '.[0].HostConfig.Privileged'  # Should be false
nc -zv homelab 25565  # Test connectivity
# Connect with Minecraft client to verify functionality
Phase 2: Homepage Container Rootless (Complex - 8-12 hours)
Challenge: Homepage needs Docker socket access. Two approaches: Option A: Socket Proxy (RECOMMENDED for security) Create intermediate proxy container that filters Docker API calls: Files to modify:
containers/homepage.nix:
# Add socket proxy container
virtualisation.oci-containers.containers.docker-socket-proxy = {
  image = "tecnativa/docker-socket-proxy";
  user = "root:root";  # This one needs root for socket access
  volumes = [ "/var/run/podman/podman.sock:/var/run/docker.sock:ro" ];
  ports = [ "127.0.0.1:2375:2375" ];
  environment = {
    CONTAINERS = "1";  # Allow container info
    POST = "0";        # Deny writes
    DELETE = "0";      # Deny deletes
  };
};

# Update homepage container
virtualisation.oci-containers.containers.homepage = {
  image = "ghcr.io/gethomepage/homepage@sha256:...";
  autoStart = true;

  # ADD THIS - run as non-root
  user = "1000:100";

  ports = [ "3000:3000" ];

  # REMOVE docker socket mount, use proxy instead
  volumes = [ "/var/lib/homepage:/app/config:U" ];

  environment = {
    HOMEPAGE_ALLOWED_HOSTS = "tongatime.us";
    DOCKER_HOST = "docker-socket-proxy:2375";
    PUID = "1000";
    PGID = "100";
  };

  dependsOn = [ "docker-socket-proxy" ];
};
Option B: ACL-based socket access (simpler but less secure) Grant homepage user access to podman socket via group membership. Not recommended for production but faster to implement. Validation:
./deploy-nix.sh
podman exec homepage whoami  # Should NOT be root
curl https://tongatime.us  # Verify dashboard loads
# Verify container status widgets work on dashboard
podman inspect homepage | jq '.[0].HostConfig.Privileged'  # Should be false
Phase 3: System-wide Rootless Configuration
Files to modify:
configuration.nix:51-55 - Enhance Podman config:
virtualisation.podman = {
  enable = true;
  dockerCompat = true;
  defaultNetwork.settings.dns_enabled = true;
  autoPrune.enable = true;  # Clean up old containers
};

# Create container users with subuid/subgid ranges
users.users.containeruser = {
  isSystemUser = true;
  group = "containeruser";
  uid = 1000;
  subUidRanges = [{ startUid = 100000; count = 65536; }];
  subGidRanges = [{ startGid = 100000; count = 65536; }];
};
users.groups.containeruser.gid = 1000;
Trade-offs:
Initial complexity in setup
Docker socket proxy adds extra container layer
File permission adjustments may be needed
Performance impact minimal
3.2 Remove SELinux Label Disabling
Severity: MEDIUM | Effort: 4-6 hours Problem: SELinux labels disabled (deploy-vps.sh:90, deploy-dns.sh:65) First, check if SELinux is active:
getenforce  # If "Disabled", this is trivial. If "Enforcing/Permissive", need proper setup
Files to modify:
deploy-vps.sh:90 - Remove --security-opt label=disable
deploy-dns.sh:65 - Remove --security-opt label=disable
If SELinux is enabled, also need to:
Set proper contexts: semanage fcontext -a -t container_file_t "/work(/.*)?"
Apply: restorecon -Rv /work
Use :Z or :z flags on volume mounts
Validation:
./deploy-vps.sh
./deploy-dns.sh
ausearch -m avc -ts recent  # Check for SELinux denials
3.3 Implement Secure Secrets Injection
Severity: MEDIUM | Effort: 1 day Problem: Deployment scripts could expose secrets in process arguments Solution: Use sops exec-env pattern for all secret handling Follow pattern from secrets/cat-creds.sh:
sops -d "$SCRIPT_DIR/dns_creds.json"
Files to modify:
deploy-dns.sh - Decrypt secrets before container, pass as env vars
deploy-vps.sh - Same pattern
Example refactor:
# Before: mounting raw encrypted files
-v "$HOME/.config/sops:/root/.config/sops:ro"

# After: decrypt and inject
CLOUDFLARE_TOKEN=$(sops -d --extract '["cloudflare_token"]' secrets/secrets.yaml)
podman run --rm -it \
  -e CLOUDFLARE_TOKEN="$CLOUDFLARE_TOKEN" \
  ...
Validation:
ps aux | grep deploy  # Verify secrets not in process list
./deploy-dns.sh  # Verify still works
TIER 4: Major Architectural Overhaul (weeks)
Impact: Long-term security hardening and infrastructure resilience
4.1 Zero-Trust Network Architecture (2-3 weeks)
Current state: Already using Tailscale VPN, but containers have direct network access Enhancements:
Phase 1: Service Mesh with mTLS (1 week)
Deploy step-ca (Smallstep CA) as private CA
Issue certificates for each service
Configure Caddy to require client certificates
Implement certificate rotation
Files to create:
network/pki.nix - Private CA configuration
network/service-mesh.nix - Service mesh config
Phase 2: Network Segmentation (1 week)
Create isolated Podman networks per service
Implement strict firewall rules between networks
Only allow necessary service-to-service communication
Configuration example:
virtualisation.podman.networks = {
  minecraft-net = {
    driver = "bridge";
    internal = false;
    subnets = [{ subnet = "10.89.1.0/24"; }];
  };
  homepage-net = {
    driver = "bridge";
    internal = true;  # No external access
    subnets = [{ subnet = "10.89.2.0/24"; }];
  };
};

networking.firewall.extraCommands = ''
  # Only allow Tailscale to Minecraft
  iptables -A INPUT -p tcp --dport 25565 -s 100.64.0.0/10 -j ACCEPT
  iptables -A INPUT -p tcp --dport 25565 -j DROP
'';
Phase 3: Runtime Security Monitoring (1 week)
Deploy Falco for runtime security monitoring
Alert on suspicious container behavior
Automated response to security events
4.2 CI/CD Pipeline with Security Scanning (3-4 weeks)
Current state: Manual deployments via shell scripts Enhancements:
Phase 1: GitOps with Gitea (1 week)
Deploy Gitea (already in TODO.md:9)
Configure Gitea Actions for CI/CD
Automated deployment on git push
Phase 2: Security Scanning (1 week)
Trivy for container image vulnerability scanning
nixpkgs-hammering for Nix code quality
SOPS validation for secret encryption
NixOS test framework integration
Example workflow:
name: Security Scan and Deploy
on: [push]
jobs:
  security-scan:
    steps:
      - name: Scan container images
        run: trivy image --severity CRITICAL,HIGH itzg/minecraft-server@sha256:...
      - name: Validate Nix
        run: nix flake check
      - name: Verify secrets encrypted
        run: sops --decrypt secrets/secrets.yaml > /dev/null
  deploy:
    needs: security-scan
    steps:
      - run: ./deploy-nix.sh
Phase 3: Rollback and Canary Deployments (1-2 weeks)
Automated rollback on failure
Health checks for services
Blue-green deployment strategy
4.3 Centralized Logging and SIEM (2-3 weeks)
Implementation:
Phase 1: Centralized Logging (1 week)
Deploy Loki for log aggregation
Deploy Promtail for log collection
Grafana dashboards for visualization
Files to create:
containers/loki.nix
containers/promtail.nix
observability/grafana.nix
Phase 2: Security Event Monitoring (1 week)
Monitor SSH authentication attempts
Track container lifecycle events
Alert on firewall denials
Detect privilege escalation attempts
Phase 3: Alerting (1 week)
AlertManager for incident response
Failed SSH > 5 in 10 minutes
Unusual network traffic patterns
Certificate expiration warnings
4.4 Backup and Disaster Recovery (2 weeks)
Phase 1: Automated Encrypted Backups (1 week)
Restic or Borg backup for persistent data
S3-compatible storage for off-site backups
Daily automated backups with retention policy
Example configuration:
services.restic.backups.homelab = {
  initialize = true;
  repository = "s3:s3.amazonaws.com/tongatime-backups";
  passwordFile = config.sops.secrets.restic_password.path;
  paths = [
    "/var/lib/minecraft"
    "/var/lib/homepage"
    "/var/lib/acme"
  ];
  timerConfig.OnCalendar = "daily";
  pruneOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
};
Phase 2: Configuration Backup (3 days)
Gitea mirror setup (already in TODO.md:9)
Automated configuration snapshots
Immutable backup storage
Phase 3: DR Testing (4 days)
Document recovery procedures
Define RTO/RPO targets
Quarterly disaster recovery tests
Verify encrypted backup restoration
Implementation Roadmap
Week 1: Immediate Security Fixes
Day 1: Complete all Tier 1 (1 hour total)
Add RCON password
Fix secret permissions
Add security headers
Pin image tags
Weeks 2-3: Tier 2 Improvements
Week 2: Network variables, Nix signatures, SSH host keys (8-10 hours)
Week 3: TLS CA trust (2-3 hours)
Weeks 4-6: Tier 3 Critical Fixes
Week 4-5: Rootless containers (priority 1) - 1-2 days
Week 6: SELinux and secrets injection - 2 days
Months 2-4: Tier 4 Long-term Hardening
Month 2: Zero-trust architecture
Month 3: CI/CD pipeline
Month 4: SIEM and backup/DR
Critical Files Summary
Immediate attention required:
containers/minecraft.nix - CRITICAL: root container, RCON, image pinning
containers/homepage.nix - CRITICAL: root container, Docker socket
network/caddy.nix - Security headers, TLS verification, hardcoded IPs
configuration.nix - Rootless Podman, sops secrets, system hardening
deploy-vps.sh - SSH host checking, Nix signatures, SELinux
Supporting files:
secrets/secrets.yaml - Add new secrets (RCON, Proxmox CA)
vps/home.nix - Network variables
deploy-dns.sh - SELinux labels
Validation Strategy
After Tier 1:
./deploy-nix.sh --dry-run  # Syntax check
./deploy-nix.sh            # Deploy
curl -I https://tongatime.us  # Verify services
podman ps                  # Verify containers running
journalctl -u caddy -n 50  # Check for errors
After Tier 2:
nix flake check            # Validate flake
nix store verify --all     # Check signatures
ssh homelab "systemctl status podman-*"
After Tier 3:
# Critical security validation
podman exec minecraft whoami  # Must NOT be root
podman exec homepage whoami   # Must NOT be root
podman inspect minecraft | jq '.[0].HostConfig.Privileged'  # Must be false
ausearch -m avc -ts recent    # SELinux denials check
After Tier 4:
Full penetration testing
Security audit by third party
Performance benchmarking
Compliance verification
Risk-Based Priority
Issue	Risk	Tier	Effort	Priority
Root containers	CRITICAL	3.1	High	1
Missing RCON pwd	CRITICAL	1.1	Low	2
Docker socket	CRITICAL	3.1	High	3
SSH host checking	HIGH	2.3	Med	4
:latest tags	HIGH	1.4	Low	5
SELinux disabled	MED	3.2	Med	6
Missing headers	MED	1.3	Low	7
TLS skip verify	MED	2.4	Med	8
Hardcoded IPs	MED	2.1	Low	9
Secret perms	MED	1.2	Low	10
Nix signatures	MED	2.2	Med	11
Success Metrics
Tier 1-2 (Short-term):
✅ All secrets encrypted and access-controlled (600 permissions)
✅ Container images pinned to SHA256 digests
✅ HTTP security headers present on all endpoints
✅ RCON password set and functional
✅ SSH host keys verified on all connections
✅ Nix package signatures verified
Tier 3 (Medium-term):
✅ Zero containers running as root
✅ No privileged containers
✅ SELinux enforcing (if enabled)
✅ Secrets never in process arguments
Tier 4 (Long-term):
✅ Full audit trail for all changes
✅ Automated security scanning in CI/CD
✅ DR tested quarterly
✅ MTTD < 5 minutes for security events
Emergency Rollback Procedures
Tier 1-2 Rollback:
git checkout HEAD~1 -- <modified-file>
./deploy-nix.sh
Tier 3 Rollback:
systemctl stop podman-minecraft.service
systemctl stop podman-homepage.service
git checkout HEAD~1
./deploy-nix.sh
Nuclear Option:
nixos-rebuild --rollback
# Or select previous generation at boot
Notes
You already have rootless containers in TODO.md:29 - this plan provides detailed implementation
Your existing security posture is strong (SOPS, SSH hardening, Tailscale, zero-trust network)
Main risks are container-level (running as root) and deployment security (SSH, Nix signatures)
Tier 1 fixes can be done immediately with minimal risk
Tier 3 (rootless containers) requires careful testing but provides maximum security benefit
Tier 4 is optional long-term hardening for production-grade security
Estimated Total Effort:
Tier 1: 1 hour
Tier 2: 10 hours
Tier 3: 4-5 days
Tier 4: 9-12 weeks (optional)
Recommended Start: Begin with Tier 1 today (< 1 hour), then Tier 3.1 (rootless containers) as priority.
Stayed in plan mode
I've already written the complete plan to the file at: /home/taylort3450/.claude/plans/adaptive-sleeping-dolphin.md The plan is comprehensive and ready for your review. It includes:
Detailed analysis of 11 security vulnerabilities
4 tiers of remediation organized by increasing complexity
Specific file paths, line numbers, and code examples for each fix
Validation procedures and rollback strategies
Effort estimates and priority rankings
Implementation roadmap with timeline
You can review the plan file and let me know when you're ready to proceed with implementation, or if you'd like any modifications to the approach.
Claude’s Plan
Security Audit & Remediation Plan for NixServer
Executive Summary
This plan addresses 11 security vulnerabilities discovered in your nixserver infrastructure, organized into 4 tiers of increasing complexity:
Tier 1: Quick wins (< 1 hour) - 4 vulnerabilities
Tier 2: Moderate changes (few hours) - 4 vulnerabilities
Tier 3: Significant refactors (days) - 2 CRITICAL vulnerabilities + 1 medium
Tier 4: Major architectural overhaul (weeks) - Long-term hardening
Most Critical Issues:
Containers running as root (CRITICAL) - container escape = full host compromise
Missing RCON password (CRITICAL) - unauthenticated remote console access
Docker socket exposure (CRITICAL) - container can control all other containers
TIER 1: Quick Wins (< 1 hour)
Impact: Address 4 vulnerabilities with simple configuration changes
1.1 Add RCON Password to Minecraft Server
Severity: CRITICAL | Effort: 5 minutes Problem: RCON is enabled but no password is set (containers/minecraft.nix:65) Solution:
Add RCON password to SOPS secrets
Reference in minecraft.nix configuration
Deploy changes
Files to modify:
secrets/secrets.yaml - Add encrypted minecraft_rcon_password entry
configuration.nix:36-38 - Add new sops secret definition:
sops.secrets.minecraft_rcon_password = {
  owner = "root";
};
containers/minecraft.nix:66 - Add after line 65:
RCON_PASSWORD = "${config.sops.secrets.minecraft_rcon_password.path}";
Validation:
./deploy-nix.sh
podman exec minecraft env | grep RCON_PASSWORD
1.2 Fix Secret File Permissions
Severity: MEDIUM | Effort: 2 minutes Problem: Encrypted secret files are world-readable (644 permissions) Solution: Restrict permissions to owner-only (600)
chmod 600 secrets/dns_creds.json
chmod 600 secrets/secrets.yaml
Validation:
ls -la secrets/
# Should show: -rw-------
1.3 Add HTTP Security Headers
Severity: MEDIUM | Effort: 15 minutes Problem: Missing security headers expose services to XSS, clickjacking, MIME-sniffing Files to modify:
network/caddy.nix:76-85 - Add to Proxmox virtualHost
network/caddy.nix:93-97 - Add to Homepage virtualHost
Configuration to add (insert in both virtualHost extraConfig blocks):
extraConfig = ''
  header {
    X-Frame-Options "DENY"
    X-Content-Type-Options "nosniff"
    Referrer-Policy "strict-origin-when-cross-origin"
    Permissions-Policy "geolocation=(), microphone=(), camera=()"
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
  }

  # Existing reverse_proxy config...
'';
Validation:
./deploy-nix.sh
curl -I https://tongatime.us | grep -E "X-Frame|X-Content|Strict-Transport"
1.4 Pin Container Image Tags
Severity: HIGH | Effort: 20 minutes Problem: Using :latest tags creates supply chain risk and non-reproducible builds Files to modify:
containers/minecraft.nix:35
containers/homepage.nix:21
Solution: Replace :latest with SHA256 digests Get current digests:
podman pull itzg/minecraft-server:latest
podman pull ghcr.io/gethomepage/homepage:latest
podman images --digests | grep -E "minecraft-server|homepage"
Update configuration:
# Before
image = "itzg/minecraft-server:latest";
image = "ghcr.io/gethomepage/homepage:latest";

# After (use actual current digest)
image = "itzg/minecraft-server@sha256:<digest-from-above>";
image = "ghcr.io/gethomepage/homepage@sha256:<digest-from-above>";
Note: Add comment explaining how to update digests in future
TIER 2: Moderate Complexity (few hours)
Impact: Address 4 vulnerabilities with contained refactoring
2.1 Create Centralized Network Variables Module
Severity: MEDIUM | Effort: 1-2 hours Problem: Hardcoded IPs in multiple files (network/caddy.nix:79, vps/home.nix:22) Solution: Create reusable network variables module Files to create:
network/variables.nix:
{
  network = {
    tailscale = {
      homelab_ip = "100.73.119.72";
    };
    lan = {
      proxmox_ip = "192.168.4.36";
      proxmox_port = 8006;
    };
    domain = "tongatime.us";
  };
}
Files to modify:
flake.nix - Import variables module
network/caddy.nix:16 - Replace hardcoded domain
network/caddy.nix:79 - Use variable for Proxmox IP
vps/home.nix:22 - Use variable for Tailscale IP
Validation:
./deploy-nix.sh --dry-run
./deploy-nix.sh
curl -I https://proxmox.tongatime.us
2.2 Enable Nix Signature Verification
Severity: MEDIUM | Effort: 2-3 hours Problem: Package signature verification disabled (deploy-vps.sh:49, deploy-vps.sh:137) Files to modify:
deploy-vps.sh:48-53 - Remove require-sigs = false lines
deploy-vps.sh:137 - Remove --option require-sigs false
configuration.nix - Add binary cache configuration:
nix.settings = {
  substituters = [ "https://cache.nixos.org" ];
  trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  require-sigs = true;
};
Validation:
./deploy-vps.sh
nix store verify --all
2.3 Implement SSH Host Key Management
Severity: HIGH | Effort: 2-3 hours Problem: SSH host key checking disabled (deploy-vps.sh:113-114) - vulnerable to MITM attacks Solution: Create and use proper SSH known_hosts file Steps:
Collect host keys:
ssh-keyscan homelab > secrets/ssh_known_hosts
ssh-keyscan 129.153.13.212 >> secrets/ssh_known_hosts
Files to modify:
deploy-vps.sh:111-116 - Replace SSH config:
cat >> /root/.ssh/config <<'SSHCONFIG'
Host $TARGET_HOST
    IdentityFile /root/.ssh/$SSH_KEY_NAME
SSHCONFIG
deploy-vps.sh:135 - Remove NIX_SSHOPTS override or fix it:
export NIX_SSHOPTS="-i /root/.ssh/$SSH_KEY_NAME"
Containerfile:37-39 - Remove SSH config that disables checking
Mount known_hosts in container:
-v "$PWD/secrets/ssh_known_hosts:/root/.ssh/known_hosts:ro"
Validation:
./deploy-vps.sh  # Should succeed with proper verification
2.4 Replace TLS Insecure Skip Verify with Custom CA
Severity: MEDIUM | Effort: 2-3 hours Problem: TLS verification disabled for Proxmox (network/caddy.nix:81) Solution: Trust Proxmox's self-signed CA certificate Steps:
Extract Proxmox CA from Proxmox host: /etc/pve/pve-root-ca.pem
Add to SOPS secrets as proxmox_ca_cert
Files to modify:
secrets/secrets.yaml - Add Proxmox CA cert
configuration.nix:36-38 - Add sops secret:
sops.secrets.proxmox_ca_cert = {
  owner = "caddy";
  mode = "0400";
};
network/caddy.nix:79-82 - Replace with:
reverse_proxy https://192.168.4.36:8006 {
  transport http {
    tls_trusted_ca_certs ${config.sops.secrets.proxmox_ca_cert.path}
  }
}
Validation:
./deploy-nix.sh
curl -I https://proxmox.tongatime.us
journalctl -u caddy -n 50  # Check for TLS errors
TIER 3: Significant Refactor (1-2 days)
Impact: Addresses 2 CRITICAL + 1 MEDIUM vulnerabilities
3.1 Convert Containers to Rootless Mode ⚠️ PRIORITY 1
Severity: CRITICAL | Effort: 1-2 days Problem: Both containers run as root (containers/minecraft.nix:33 comment acknowledges this)
Container escape = full host compromise
Homepage container has Docker socket access as root
Solution Overview: This is already in your TODO.md:29. Requires coordinated changes across multiple files.
Phase 1: Minecraft Container Rootless (4-6 hours)
Files to modify:
containers/minecraft.nix:
virtualisation.oci-containers.containers.minecraft = {
  image = "itzg/minecraft-server@sha256:...";  # From Tier 1.4
  autoStart = true;

  # ADD THIS - specify non-root user
  user = "1000:1000";

  ports = [ "25565:25565" ];

  # Update volume with :U flag for UID mapping
  volumes = [ "/var/lib/minecraft:/data:U" ];

  environment = {
    # Existing config...
    RCON_PASSWORD = "${config.sops.secrets.minecraft_rcon_password.path}";

    # ADD THIS - tell container to run as UID/GID
    UID = "1000";
    GID = "1000";
  };
};

# Existing tmpfiles rule already sets correct ownership (line 78)
Testing:
./deploy-nix.sh
podman exec minecraft whoami  # Should NOT be root
podman inspect minecraft | jq '.[0].HostConfig.Privileged'  # Should be false
nc -zv homelab 25565  # Test connectivity
# Connect with Minecraft client to verify functionality
Phase 2: Homepage Container Rootless (Complex - 8-12 hours)
Challenge: Homepage needs Docker socket access. Two approaches: Option A: Socket Proxy (RECOMMENDED for security) Create intermediate proxy container that filters Docker API calls: Files to modify:
containers/homepage.nix:
# Add socket proxy container
virtualisation.oci-containers.containers.docker-socket-proxy = {
  image = "tecnativa/docker-socket-proxy";
  user = "root:root";  # This one needs root for socket access
  volumes = [ "/var/run/podman/podman.sock:/var/run/docker.sock:ro" ];
  ports = [ "127.0.0.1:2375:2375" ];
  environment = {
    CONTAINERS = "1";  # Allow container info
    POST = "0";        # Deny writes
    DELETE = "0";      # Deny deletes
  };
};

# Update homepage container
virtualisation.oci-containers.containers.homepage = {
  image = "ghcr.io/gethomepage/homepage@sha256:...";
  autoStart = true;

  # ADD THIS - run as non-root
  user = "1000:100";

  ports = [ "3000:3000" ];

  # REMOVE docker socket mount, use proxy instead
  volumes = [ "/var/lib/homepage:/app/config:U" ];

  environment = {
    HOMEPAGE_ALLOWED_HOSTS = "tongatime.us";
    DOCKER_HOST = "docker-socket-proxy:2375";
    PUID = "1000";
    PGID = "100";
  };

  dependsOn = [ "docker-socket-proxy" ];
};
Option B: ACL-based socket access (simpler but less secure) Grant homepage user access to podman socket via group membership. Not recommended for production but faster to implement. Validation:
./deploy-nix.sh
podman exec homepage whoami  # Should NOT be root
curl https://tongatime.us  # Verify dashboard loads
# Verify container status widgets work on dashboard
podman inspect homepage | jq '.[0].HostConfig.Privileged'  # Should be false
Phase 3: System-wide Rootless Configuration
Files to modify:
configuration.nix:51-55 - Enhance Podman config:
virtualisation.podman = {
  enable = true;
  dockerCompat = true;
  defaultNetwork.settings.dns_enabled = true;
  autoPrune.enable = true;  # Clean up old containers
};

# Create container users with subuid/subgid ranges
users.users.containeruser = {
  isSystemUser = true;
  group = "containeruser";
  uid = 1000;
  subUidRanges = [{ startUid = 100000; count = 65536; }];
  subGidRanges = [{ startGid = 100000; count = 65536; }];
};
users.groups.containeruser.gid = 1000;
Trade-offs:
Initial complexity in setup
Docker socket proxy adds extra container layer
File permission adjustments may be needed
Performance impact minimal
3.2 Remove SELinux Label Disabling
Severity: MEDIUM | Effort: 4-6 hours Problem: SELinux labels disabled (deploy-vps.sh:90, deploy-dns.sh:65) First, check if SELinux is active:
getenforce  # If "Disabled", this is trivial. If "Enforcing/Permissive", need proper setup
Files to modify:
deploy-vps.sh:90 - Remove --security-opt label=disable
deploy-dns.sh:65 - Remove --security-opt label=disable
If SELinux is enabled, also need to:
Set proper contexts: semanage fcontext -a -t container_file_t "/work(/.*)?"
Apply: restorecon -Rv /work
Use :Z or :z flags on volume mounts
Validation:
./deploy-vps.sh
./deploy-dns.sh
ausearch -m avc -ts recent  # Check for SELinux denials
3.3 Implement Secure Secrets Injection
Severity: MEDIUM | Effort: 1 day Problem: Deployment scripts could expose secrets in process arguments Solution: Use sops exec-env pattern for all secret handling Follow pattern from secrets/cat-creds.sh:
sops -d "$SCRIPT_DIR/dns_creds.json"
Files to modify:
deploy-dns.sh - Decrypt secrets before container, pass as env vars
deploy-vps.sh - Same pattern
Example refactor:
# Before: mounting raw encrypted files
-v "$HOME/.config/sops:/root/.config/sops:ro"

# After: decrypt and inject
CLOUDFLARE_TOKEN=$(sops -d --extract '["cloudflare_token"]' secrets/secrets.yaml)
podman run --rm -it \
  -e CLOUDFLARE_TOKEN="$CLOUDFLARE_TOKEN" \
  ...
Validation:
ps aux | grep deploy  # Verify secrets not in process list
./deploy-dns.sh  # Verify still works
TIER 4: Major Architectural Overhaul (weeks)
Impact: Long-term security hardening and infrastructure resilience
4.1 Zero-Trust Network Architecture (2-3 weeks)
Current state: Already using Tailscale VPN, but containers have direct network access Enhancements:
Phase 1: Service Mesh with mTLS (1 week)
Deploy step-ca (Smallstep CA) as private CA
Issue certificates for each service
Configure Caddy to require client certificates
Implement certificate rotation
Files to create:
network/pki.nix - Private CA configuration
network/service-mesh.nix - Service mesh config
Phase 2: Network Segmentation (1 week)
Create isolated Podman networks per service
Implement strict firewall rules between networks
Only allow necessary service-to-service communication
Configuration example:
virtualisation.podman.networks = {
  minecraft-net = {
    driver = "bridge";
    internal = false;
    subnets = [{ subnet = "10.89.1.0/24"; }];
  };
  homepage-net = {
    driver = "bridge";
    internal = true;  # No external access
    subnets = [{ subnet = "10.89.2.0/24"; }];
  };
};

networking.firewall.extraCommands = ''
  # Only allow Tailscale to Minecraft
  iptables -A INPUT -p tcp --dport 25565 -s 100.64.0.0/10 -j ACCEPT
  iptables -A INPUT -p tcp --dport 25565 -j DROP
'';
Phase 3: Runtime Security Monitoring (1 week)
Deploy Falco for runtime security monitoring
Alert on suspicious container behavior
Automated response to security events
4.2 CI/CD Pipeline with Security Scanning (3-4 weeks)
Current state: Manual deployments via shell scripts Enhancements:
Phase 1: GitOps with Gitea (1 week)
Deploy Gitea (already in TODO.md:9)
Configure Gitea Actions for CI/CD
Automated deployment on git push
Phase 2: Security Scanning (1 week)
Trivy for container image vulnerability scanning
nixpkgs-hammering for Nix code quality
SOPS validation for secret encryption
NixOS test framework integration
Example workflow:
name: Security Scan and Deploy
on: [push]
jobs:
  security-scan:
    steps:
      - name: Scan container images
        run: trivy image --severity CRITICAL,HIGH itzg/minecraft-server@sha256:...
      - name: Validate Nix
        run: nix flake check
      - name: Verify secrets encrypted
        run: sops --decrypt secrets/secrets.yaml > /dev/null
  deploy:
    needs: security-scan
    steps:
      - run: ./deploy-nix.sh
Phase 3: Rollback and Canary Deployments (1-2 weeks)
Automated rollback on failure
Health checks for services
Blue-green deployment strategy
4.3 Centralized Logging and SIEM (2-3 weeks)
Implementation:
Phase 1: Centralized Logging (1 week)
Deploy Loki for log aggregation
Deploy Promtail for log collection
Grafana dashboards for visualization
Files to create:
containers/loki.nix
containers/promtail.nix
observability/grafana.nix
Phase 2: Security Event Monitoring (1 week)
Monitor SSH authentication attempts
Track container lifecycle events
Alert on firewall denials
Detect privilege escalation attempts
Phase 3: Alerting (1 week)
AlertManager for incident response
Failed SSH > 5 in 10 minutes
Unusual network traffic patterns
Certificate expiration warnings
4.4 Backup and Disaster Recovery (2 weeks)
Phase 1: Automated Encrypted Backups (1 week)
Restic or Borg backup for persistent data
S3-compatible storage for off-site backups
Daily automated backups with retention policy
Example configuration:
services.restic.backups.homelab = {
  initialize = true;
  repository = "s3:s3.amazonaws.com/tongatime-backups";
  passwordFile = config.sops.secrets.restic_password.path;
  paths = [
    "/var/lib/minecraft"
    "/var/lib/homepage"
    "/var/lib/acme"
  ];
  timerConfig.OnCalendar = "daily";
  pruneOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
};
Phase 2: Configuration Backup (3 days)
Gitea mirror setup (already in TODO.md:9)
Automated configuration snapshots
Immutable backup storage
Phase 3: DR Testing (4 days)
Document recovery procedures
Define RTO/RPO targets
Quarterly disaster recovery tests
Verify encrypted backup restoration
Implementation Roadmap
Week 1: Immediate Security Fixes
Day 1: Complete all Tier 1 (1 hour total)
Add RCON password
Fix secret permissions
Add security headers
Pin image tags
Weeks 2-3: Tier 2 Improvements
Week 2: Network variables, Nix signatures, SSH host keys (8-10 hours)
Week 3: TLS CA trust (2-3 hours)
Weeks 4-6: Tier 3 Critical Fixes
Week 4-5: Rootless containers (priority 1) - 1-2 days
Week 6: SELinux and secrets injection - 2 days
Months 2-4: Tier 4 Long-term Hardening
Month 2: Zero-trust architecture
Month 3: CI/CD pipeline
Month 4: SIEM and backup/DR
Critical Files Summary
Immediate attention required:
containers/minecraft.nix - CRITICAL: root container, RCON, image pinning
containers/homepage.nix - CRITICAL: root container, Docker socket
network/caddy.nix - Security headers, TLS verification, hardcoded IPs
configuration.nix - Rootless Podman, sops secrets, system hardening
deploy-vps.sh - SSH host checking, Nix signatures, SELinux
Supporting files:
secrets/secrets.yaml - Add new secrets (RCON, Proxmox CA)
vps/home.nix - Network variables
deploy-dns.sh - SELinux labels
Validation Strategy
After Tier 1:
./deploy-nix.sh --dry-run  # Syntax check
./deploy-nix.sh            # Deploy
curl -I https://tongatime.us  # Verify services
podman ps                  # Verify containers running
journalctl -u caddy -n 50  # Check for errors
After Tier 2:
nix flake check            # Validate flake
nix store verify --all     # Check signatures
ssh homelab "systemctl status podman-*"
After Tier 3:
# Critical security validation
podman exec minecraft whoami  # Must NOT be root
podman exec homepage whoami   # Must NOT be root
podman inspect minecraft | jq '.[0].HostConfig.Privileged'  # Must be false
ausearch -m avc -ts recent    # SELinux denials check
After Tier 4:
Full penetration testing
Security audit by third party
Performance benchmarking
Compliance verification
Risk-Based Priority
Issue	Risk	Tier	Effort	Priority
Root containers	CRITICAL	3.1	High	1
Missing RCON pwd	CRITICAL	1.1	Low	2
Docker socket	CRITICAL	3.1	High	3
SSH host checking	HIGH	2.3	Med	4
:latest tags	HIGH	1.4	Low	5
SELinux disabled	MED	3.2	Med	6
Missing headers	MED	1.3	Low	7
TLS skip verify	MED	2.4	Med	8
Hardcoded IPs	MED	2.1	Low	9
Secret perms	MED	1.2	Low	10
Nix signatures	MED	2.2	Med	11
Success Metrics
Tier 1-2 (Short-term):
✅ All secrets encrypted and access-controlled (600 permissions)
✅ Container images pinned to SHA256 digests
✅ HTTP security headers present on all endpoints
✅ RCON password set and functional
✅ SSH host keys verified on all connections
✅ Nix package signatures verified
Tier 3 (Medium-term):
✅ Zero containers running as root
✅ No privileged containers
✅ SELinux enforcing (if enabled)
✅ Secrets never in process arguments
Tier 4 (Long-term):
✅ Full audit trail for all changes
✅ Automated security scanning in CI/CD
✅ DR tested quarterly
✅ MTTD < 5 minutes for security events
Emergency Rollback Procedures
Tier 1-2 Rollback:
git checkout HEAD~1 -- <modified-file>
./deploy-nix.sh
Tier 3 Rollback:
systemctl stop podman-minecraft.service
systemctl stop podman-homepage.service
git checkout HEAD~1
./deploy-nix.sh
Nuclear Option:
nixos-rebuild --rollback
# Or select previous generation at boot
Notes
You already have rootless containers in TODO.md:29 - this plan provides detailed implementation
Your existing security posture is strong (SOPS, SSH hardening, Tailscale, zero-trust network)
Main risks are container-level (running as root) and deployment security (SSH, Nix signatures)
Tier 1 fixes can be done immediately with minimal risk
Tier 3 (rootless containers) requires careful testing but provides maximum security benefit
Tier 4 is optional long-term hardening for production-grade security
Estimated Total Effort:
Tier 1: 1 hour
Tier 2: 10 hours
Tier 3: 4-5 days
Tier 4: 9-12 weeks (optional)
