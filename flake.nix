{
  description = "tool that builds rust crates with import from derivation";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
  };
  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        rust-build = import ./nix/default.nix pkgs;
        bootstrap =
          (rust-build.build {
            src = ./.;
            pname = "nix-rust-build";
            version = "0.0.1";
          }).overrideAttrs
            (p: {
              passthru = (p.passthru or { }) // {
                tests = import ./nix/rust-build/tests.nix { inherit (pkgs) runCommand; } bootstrap;
              };
            });
      in
      {
        inherit rust-build;
        packages = {
          inherit bootstrap;
          default = rust-build.rust-build;
          test = rust-build.mkVendoredDerivation {
            collectedCrates = rust-build.collectDependencies {
              src = ./.;
              pname = "nix-rust-build";
              version = "0.0.1";
            };
          };
        };
        checks = bootstrap.tests;
        devShells.default =
          pkgs.mkShell.override
            {
              stdenv = pkgs.stdenvAdapters.useMoldLinker pkgs.clangStdenv;
            }
            {
              buildInputs = [
                pkgs.rust-analyzer
                pkgs.cargo
                pkgs.rustc
                pkgs.clippy
              ];
            };
      }
    ))
    // {
      overlays.default = final: prev: rec {
        rust-build = import ./nix/default.nix final;
        default = rust-build;
      };
    };
}
