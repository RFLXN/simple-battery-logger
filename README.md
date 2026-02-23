# battery-logger

Simple battery logger for NixOS using a system-level `systemd` timer.

## Features

- Appends to a JSON log only when battery percentage changes
- Uses `flock` to prevent concurrent write corruption
- Keeps log file readable by all users (`0644`)
- Supports explicit battery device name (useful on Asahi: `macsmc-battery`)

## Log format

```json
[
  {
    "date": "2026-02-23T15:30:00+00:00",
    "level": "100"
  }
]
```

## Flake usage (recommended)

```nix
{
  inputs.battery-logger.url = "github:MY_USERNAME/REPONAME";

  outputs = { self, nixpkgs, battery-logger, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        battery-logger.nixosModules.default
        {
          services.batteryLogger = {
            enable = true;
            interval = "1m";
            logFile = "/var/log/battery-log.json";
            lockFile = "/run/battery-log.lock";
            powerSupplyDir = "/sys/class/power_supply";
            batteryDeviceName = null; # or "BAT0", "macsmc-battery", etc.
          };
        }
      ];
    };
  };
}
```

## Local path flake input

```nix
{
  inputs.battery-logger.url = "path:/home/rflxn/development/battery-logger";
}
```

## Options

- `services.batteryLogger.enable` (bool): enable the logger
- `services.batteryLogger.interval` (string, default: `"1m"`): timer interval
- `services.batteryLogger.logFile` (string, default: `"/var/log/battery-log.json"`): JSON log path
- `services.batteryLogger.lockFile` (string, default: `"/run/battery-log.lock"`): file lock path
- `services.batteryLogger.powerSupplyDir` (string, default: `"/sys/class/power_supply"`): power supply directory
- `services.batteryLogger.batteryDeviceName` (null or string, default: `null`): battery device directory name/glob under `powerSupplyDir`; `null` means auto-detect first battery device

## Check status

```bash
systemctl status battery-logger.timer
systemctl list-timers battery-logger.timer
journalctl -u battery-logger.service
```
