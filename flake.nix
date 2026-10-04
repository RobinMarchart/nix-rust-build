{
  description = "tool that builds rust crates with import from derivation";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs =
    {
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
      eachSystem =
        f:
        let
          forSystem = system: builtins.mapAttrs (name: val: { ${system} = val; }) (f system);
          sets = map forSystem lib.systems.flakeExposed;
        in
        builtins.foldl' lib.attrsets.recursiveUpdate { } sets;
    in
    (eachSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        rust-build = import ./nix/default.nix pkgs;
        compile_test = pkgs.callPackage ./compile_test.nix { inherit rust-build; };
      in
      {
        formatter = pkgs.nixfmt-tree;
        checks = {
          inherit compile_test;
          inherit (compile_test) metadata_out;
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
      rust-build-from-pkgs = import ./nix/default.nix;
    };
}
