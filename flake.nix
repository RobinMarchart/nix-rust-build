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
        inherit (pkgs) lib;
        rust-build = import ./nix/default.nix pkgs;
        bootstrap =
          (rust-build.build {
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./src
                ./Cargo.toml
                ./Cargo.lock
              ];
            };
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
        packages = {
          inherit bootstrap rust-build;
          default = rust-build;
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
      overlays.default = final: prev: {
        rust-build = import ./nix/default.nix final;
      };
    };
}
