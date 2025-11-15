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
        compile_test = pkgs.callPackage ./compile_test.nix { inherit rust-build; };
      in
      {
        packages = {
          inherit rust-build compile_test;
          default = rust-build;
        };
        checks = {
          config = compile_test;
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
                pkgs.nix-unit
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
