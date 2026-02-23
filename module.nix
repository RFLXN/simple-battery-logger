{ config, lib, pkgs, ... }:

let
  cfg = config.services.batteryLogger;
in
{
  options.services.batteryLogger = {
    enable = lib.mkEnableOption "battery logger systemd timer";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "Battery logger package to execute.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1m";
      example = "30s";
      description = "Sample interval for battery log entries.";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/battery-log.json";
      description = "Path to the JSON array log file.";
    };

    lockFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/battery-log.lock";
      description = "Path to the lock file used to serialize writes.";
    };

    powerSupplyDir = lib.mkOption {
      type = lib.types.str;
      default = "/sys/class/power_supply";
      description = "Directory containing BAT*/capacity files.";
    };

    batteryDeviceName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "macsmc-battery";
      description = ''
        Battery device directory name (or glob) under powerSupplyDir.
        If null, the logger auto-detects the first battery device.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.battery-logger = {
      description = "Battery level logger";
      unitConfig.ConditionPathExistsGlob =
        if cfg.batteryDeviceName == null
        then "${cfg.powerSupplyDir}/*/capacity"
        else "${cfg.powerSupplyDir}/${cfg.batteryDeviceName}/capacity";

      environment = {
        BATTERY_LOG_FILE = cfg.logFile;
        BATTERY_LOG_LOCK_FILE = cfg.lockFile;
        BATTERY_POWER_SUPPLY_DIR = cfg.powerSupplyDir;
        BATTERY_DEVICE_NAME =
          if cfg.batteryDeviceName == null
          then ""
          else cfg.batteryDeviceName;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/battery-logger";
        User = "root";
        Group = "root";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
      };
    };

    systemd.timers.battery-logger = {
      description = "Run battery logger every interval";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "15s";
        Persistent = true;
        Unit = "battery-logger.service";
      };
    };
  };
}
