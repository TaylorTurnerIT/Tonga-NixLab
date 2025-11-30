{
  description = "Proxmox Homelab & VPS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Add Home Manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, disko, ... }: {
    # --- YOUR HOME SERVER (Keep this!) ---
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./disko-config.nix
        ./configuration.nix
      ];
    };

    # --- NEW: UBUNTU VPS CONFIGURATION ---
    homeConfigurations."ubuntu" = home-manager.lib.homeManagerConfiguration {
      # The VPS is x86_64 (AMD/Intel)
      pkgs = import nixpkgs { 
        system = "x86_64-linux"; 
        config.allowUnfree = true; 
      };
      
      # Pass unstable for the Caddy build
      extraSpecialArgs = {
        pkgs-unstable = import nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };

      modules = [ ./vps/home.nix ];
    };
  };
}