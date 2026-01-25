{ config, pkgs, pkgs-unstable, lib, ... }:

let
  caddyPackage = pkgs-unstable.caddy.withPlugins {
    plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d" ];
    hash = "sha256-g3Ca24Boxb9VkSCrNvy1+n5Dfd2n4qEpi2bIOxyNc6g="; 
  };

  # --- 1. MINECRAFT CONFIGURATION (Layer 4) ---
  # Generate a Caddyfile block for every port from 25565 to 25600
  portRange = lib.range 25565 25600;
  
  # Function to create one block: ":25565 { route { proxy 100.73.119.72:25565 } }"
  mkMcBlock = port: ''
      :${toString port} {
        route {
          proxy 100.73.119.72:${toString port}
        }
      }
  '';
  
  # Combine them all into one string
  minecraftConfig = lib.concatMapStrings mkMcBlock portRange;

  # --- 2. MAIN CADDYFILE ---
  caddyFileConfig = ''
    {
      # Global Options for Layer 4 (Minecraft)
      layer4 {
        ${minecraftConfig}
      }
    }

    # --- REVERSE PROXIES (HTTP/HTTPS) ---
    
    # Jellyfin
    tv.tongatime.us {
      reverse_proxy 100.73.119.72:8096
    }

    # Sonarr
    sonarr.tongatime.us {
      reverse_proxy 100.73.119.72:8989
    }

    # Radarr
    radarr.tongatime.us {
      reverse_proxy 100.73.119.72:7878
    }

    # Prowlarr
    prowlarr.tongatime.us {
      reverse_proxy 100.73.119.72:9696
    }

    # QBittorrent
    qbit.tongatime.us {
      reverse_proxy 100.73.119.72:8080
    }

    # Audiobookshelf
    audiobooks.tongatime.us {
      reverse_proxy 100.73.119.72:13378
    }

    # Bookshelf
    bookshelf.tongatime.us {
      reverse_proxy 100.73.119.72:8787
    }

    # Jellyseerr
    seerr.tongatime.us {
      reverse_proxy 100.73.119.72:5055
    }

    # Foundry VTT (Portal + Games)
    foundry.tongatime.us {
      # Pass ALL traffic to the Homelab Caddy (which handles dynamic routes)
      reverse_proxy https://100.73.119.72 {
        transport http {
          # Trust the Homelab's certificate for the encrypted Tailscale connection
          tls_insecure_skip_verify
        }
      }
    }
  '';

in
{
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "24.11";

  home.packages = [ caddyPackage ];

  # Write the config to ~/.config/caddy/Caddyfile
  xdg.configFile."caddy/Caddyfile".text = caddyFileConfig;

  systemd.user.services.caddy = {
    Unit = {
      Description = "Caddy Proxy Service";
      After = [ "network-online.target" ];
    };
    Service = {
      # Use the Caddyfile adapter
      ExecStart = "${caddyPackage}/bin/caddy run --adapter caddyfile --config %h/.config/caddy/Caddyfile";
      
      # Enable hot reloading of the Caddy configuration
      ExecReload = "${caddyPackage}/bin/caddy reload --adapter caddyfile --config %h/.config/caddy/Caddyfile";
      
      Restart = "always";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.home-manager.enable = true;
}