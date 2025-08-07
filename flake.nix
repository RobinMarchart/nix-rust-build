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
      in
      {
        packages = rec {
          rust-build = import ./nix/default.nix pkgs;
          default = rust-build.rust-build;
          test = rust-build.mkVendoredDerivation {
            collectedCrates = rust-build.collectDependencies {
              src = ./example;
              pname="example";
              version = "0.0.1";
            };
          };
          script = rust-build.mkBuildCrateDerivation {
            pname = "build_script_build";
            version = "0.0.1";
            path = "example/build.rs";
            src = ./.;
            edition = "2024";
            crateType = "bin";
            target = "x86_64-unknown-linux-gnu";
          };
        };
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
    ));
}
