{ config, pkgs, pkgs-unstable, lib, ... }:

{
  # Basic Info
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "24.11";

  # --- CADDY PROXY (User Service) ---
  services.caddy = {
    enable = true;
    
    # Use Unstable + Layer 4 Plugin
    package = pkgs-unstable.caddy.withPlugins {
      plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d" ];
      # Update this hash if it changes, or use lib.fakeSha256 first
      hash = "sha256-g3Ca24Boxb9VkSCrNvy1+n5Dfd2n4qEpi2bIOxyNc6g="; 
    };

    # Layer 4 Configuration
    # Note: On Ubuntu, user services cannot bind to ports < 1024.
    # Luckily, Minecraft is 25565, so this works perfectly!
    extraConfig = ''
      layer4 {
        :25565 {
          route {
            proxy {
              # Homelab's Tailscale IP
              upstream 100.73.119.72:25565 
            }
          }
        }
      }
    '';
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}