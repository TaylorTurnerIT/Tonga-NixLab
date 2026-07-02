{ config, pkgs, pkgs-unstable, lib, ... }:

/*
    VPS Proxy Server Configuration
    
    This configuration sets up a VPS server to act as a secure proxy gateway to a home server using Tailscale and Caddy's Layer 4 proxy.
    
    Key Components:
        - Security Hardening: Firewall, SSH hardening, Fail2Ban, Auditd
        - Tailscale: Secure tunnel to home server
        - Caddy Layer 4 Proxy: Forward Minecraft traffic over Tailscale
    
    Decisions are documented per component.

    Caddy requires unstable packages for plugin support, hence the use of pkgs-unstable.
*/
{
  imports = [ 
    # Standard Oracle Cloud hardware support
    # (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "vps-proxy";
  networking.networkmanager.enable = true;

  # --- SECURITY HARDENING ---
  
  # 1. Firewall: Deny everything by default
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 
    22    # SSH (We will harden this below)
    80    # Caddy HTTP (For Layer 4 Proxy health checks)
    443   # Caddy HTTPS (For Layer 4 Proxy health checks)
  ];
  networking.firewall.allowedTCPPortRanges = [
    { from = 25565; to = 25600; }
  ];
  networking.firewall.allowedUDPPorts = [
    41641 # TAILSCALE DIRECT CONNECT (Required for low latency)
    # 25565 # Voice Chat (Simple Voice Chat mod) 
  ]; 

  # 2. SSH Hardening
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password"; # Only keys allowed
      PasswordAuthentication = false;        # Disable passwords completely
      KbdInteractiveAuthentication = false;
    };
  };

  # 3. Fail2Ban: Ban IPs that spam SSH or other ports
  services.fail2ban = {
    enable = true;
    maxretry = 8;
    bantime = "24h"; # Ban for 24 hours
    ignoreIP = [
      "100.0.0.0/8"  # Don't ban Tailscale IPs
    ];
  };

  # 4. Auditd: Kernel-level auditing for security monitoring
  security.audit.enable = true;
  security.auditd.enable = true;

  # --- TAILSCALE (The Tunnel) ---
  services.tailscale.enable = true;
  
  # Ensure we trust the tailscale interface for internal routing
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # --- CADDY LAYER 4 PROXY ---
  services.caddy = {
    enable = true;
    # Use unstable pkgs for Caddy with Layer 4 plugin
    package = pkgs-unstable.caddy.withPlugins {
      plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d" ];
      hash = "sha256-g3Ca24Boxb9VkSCrNvy1+n5Dfd2n4qEpi2bIOxyNc6g="; 
    };

    virtualHosts = {
      "tv.tongatime.us".extraConfig = "reverse_proxy 100.73.119.72:8096";
    };
  };
  
  nix.settings.download-buffer-size = 524288000; # 500MiB
  system.stateVersion = "24.11";
}