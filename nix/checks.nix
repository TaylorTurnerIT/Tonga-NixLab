{ self, system, pkgs }:
let
  homelab = self.nixosConfigurations.homelab.config;
  vps = self.homeConfigurations.ubuntu.config;
  vpsCaddy = pkgs.lib.findFirst (p: (p.pname or "") == "caddy")
    (throw "VPS Caddy package is missing") vps.home.packages;
in {
  repository = pkgs.runCommand "repository-checks" {
    nativeBuildInputs = import ./ci-tools.nix { inherit pkgs; };
  } ''
    cp -R ${self} source
    chmod -R u+w source
    cd source
    bash scripts/ci/check.sh
    touch "$out"
  '';
} // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
  caddy-homelab = pkgs.runCommand "homelab-caddy-check" {
    nativeBuildInputs = [ homelab.services.caddy.package pkgs.openssl ];
  } ''
    # Runtime certificates and Foundry-generated routes are unavailable in CI.
    # Replace only these inputs; validate the remaining generated configuration.
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
      -subj /CN=tongatime.us -keyout key.pem -out cert.pem >/dev/null 2>&1
    sed \
      -e 's|import /var/lib/foundry-portal/routes.caddy|# Runtime Foundry routes are checked separately on the host.|' \
      -e "s|tls /var/lib/acme/tongatime.us/cert.pem /var/lib/acme/tongatime.us/key.pem|tls $PWD/cert.pem $PWD/key.pem|" \
      ${homelab.services.caddy.configFile} > Caddyfile
    caddy validate --adapter caddyfile --config Caddyfile
    touch "$out"
  '';

  caddy-vps = pkgs.runCommand "vps-caddy-check" {
    nativeBuildInputs = [ vpsCaddy ];
  } ''
    caddy validate --adapter caddyfile \
      --config ${vps.xdg.configFile."caddy/Caddyfile".source}
    touch "$out"
  '';
}
