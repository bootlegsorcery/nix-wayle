{ config, pkgs, lib, ... }:

let
  cfg = config.programs.wayle;
in
{
  options.programs.wayle = {
    enable = lib.mkEnableOption "Wayle - A Wayland desktop shell";

    package = lib.mkPackageOption pkgs "wayle" {
      default = null;
    };

    systemd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the systemd user service for Wayle";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to add to the Wayle environment";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.package != null;
      message = "programs.wayle.package must be set. Use overlays to add wayle to nixpkgs, or set the package manually.";
    }];

    environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;

    systemd.user.services.wayle = lib.mkIf cfg.systemd.enable {
      description = "Wayle Wayland Desktop Shell";

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package}";
        Restart = "on-failure";
        RestartSec = "5";
        Environment = [
          "PATH=${lib.makeBinPath [ cfg.package ]}"
        ];
      };

      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
    };

    systemd.packages = [ cfg.package ];
    services.dbus.packages = [ cfg.package ];
  };
}
