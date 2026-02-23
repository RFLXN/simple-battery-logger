{
  description = "Simple systemd battery logger for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        batteryLogger = pkgs.callPackage ./package.nix { };
      in
      {
        packages.default = batteryLogger;
        packages.battery-logger = batteryLogger;
      }
    ) // {
      nixosModules.default = import ./module.nix;
      nixosModules.battery-logger = import ./module.nix;
    };
}
