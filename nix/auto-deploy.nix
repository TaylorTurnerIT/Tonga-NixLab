{ config, lib, pkgs, ... }:

let
  cfg = config.services.tongaAutoDeploy;
  deploy = pkgs.writeShellApplication {
    name = "tonga-auto-deploy";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.git pkgs.jq pkgs.nix pkgs.systemd pkgs.util-linux ];
    text = builtins.readFile ../scripts/deploy/ci-policy.sh + "\n" + builtins.readFile ../scripts/deploy/auto-deploy.sh;
  };
  rollback = pkgs.writeShellApplication {
    name = "tonga-auto-deploy-rollback";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.nix pkgs.systemd pkgs.util-linux ];
    text = builtins.readFile ../scripts/deploy/rollback-watchdog.sh;
  };
in {
  options.services.tongaAutoDeploy.enable = lib.mkEnableOption "Tonga NixOS homelab pull deployment";

  config = {
    systemd.services.tonga-auto-deploy = {
      description = "Pull and activate the CI-qualified Tonga homelab configuration";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${deploy}/bin/tonga-auto-deploy";
        StateDirectory = "tonga-auto-deploy";
        StateDirectoryMode = "0700";
        Environment = [ "TONGA_DEPLOY_STATE=/var/lib/tonga-auto-deploy" ];
      };
    };

    systemd.timers.tonga-auto-deploy = {
      description = "Poll master for CI-qualified homelab configurations";
      wantedBy = lib.optionals cfg.enable [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "10m";
        Unit = "tonga-auto-deploy.service";
      };
    };

    systemd.services.tonga-auto-deploy-rollback = {
      description = "Recover an unhealthy automatic NixOS activation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rollback}/bin/tonga-auto-deploy-rollback";
        StateDirectory = "tonga-auto-deploy";
        StateDirectoryMode = "0700";
        Environment = [ "TONGA_DEPLOY_STATE=/var/lib/tonga-auto-deploy" ];
      };
    };

    systemd.timers.tonga-auto-deploy-rollback = {
      description = "Check deployment health and recover without network access";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "20s";
        OnUnitActiveSec = "30s";
        Unit = "tonga-auto-deploy-rollback.service";
      };
    };
  };
}
