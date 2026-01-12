{ config, pkgs, pkgs-unstable, lib, ... }:

let
  caddyPackage = pkgs-unstable.caddy.withPlugins {
    plugins = [ "github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d" ];
    hash = "sha256-g3Ca24Boxb9VkSCrNvy1+n5Dfd2n4qEpi2bIOxyNc6g="; 
  };

  # --- DYNAMIC CONFIGURATION ---
  # Define the range of ports
  portRange = lib.range 25565 25600;

  # Function: Creates a server block for ONE specific port
  # Returns: { name = "minecraft_25565"; value = { ... }; }
  mkServer = port: {
    name = "minecraft_${toString port}";
    value = {
      listen = [ ":${toString port}" ];
      routes = [
        {
          handle = [
            {
              handler = "proxy";
              upstreams = [ { dial = [ "100.73.119.72:${toString port}" ]; } ];
            }
          ];
        }
      ];
    };
  };

  # Generate the map of all servers
  serverMap = builtins.listToAttrs (map mkServer portRange);

  # Assemble the final JSON
  caddyConfig = builtins.toJSON {
    apps = {
      layer4 = {
        servers = serverMap;
      };
    };
  };

  
in
{
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "24.11";

  home.packages = [ caddyPackage ];

  # Write config to ~/.config/caddy/config.json
  xdg.configFile."caddy/config.json".text = caddyConfig;

  systemd.user.services.caddy = {
    Unit = {
      Description = "Caddy Layer 4 Proxy";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${caddyPackage}/bin/caddy run --config %h/.config/caddy/config.json";
      Restart = "always";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.home-manager.enable = true;
}