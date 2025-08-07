pkgs:
let
  lib = pkgs.lib;
  registry_import = import ./vendor/registries.nix;
  combine =
    final:
    let
      inherit (final)
        rustc
        cargo
        rustPlatform
        mkDerivation
        fetchurl
        makeSetupHook
        mkStandardCrateRegistry
        defaultCrateRegistries
        extraCrateRegistries
        rust-build
        vendorBuildHook
        unpackSrcHook
        prepareLockfileHook
        buildCrateHook
        mkLockfileDerivation
        mkSourceDerivation
        collectDependencies
        mkVendoredDerivation
        mkBuildBinDerivation
        mkBuildLibDerivation
        mkBuildProcMacroDerivation
        ;
      crateRegistries = defaultCrateRegistries // extraCrateRegistries;
      hooks = import ./rust-build/hooks.nix {
        inherit
          lib
          makeSetupHook
          rust-build
          cargo
          rustc
          ;
      };
    in
    {
      inherit (pkgs) cargo rustc;
      inherit crateRegistries;
      rustPlatform = pkgs.rustPlatform;
      mkDerivation = pkgs.stdenv.mkDerivation;
      fetchurl = pkgs.fetchurl;
      makeSetupHook = pkgs.makeSetupHook;
      mkStandardCrateRegistry = registry_import.mkStandardCrateRegistry;
      defaultCrateRegistries = lib.makeOverridable registry_import.defaultCrateRegistries {
        inherit mkStandardCrateRegistry;
      };
      extraCrateRegistries = { };
      rust-build = lib.makeOverridable (import ./rust-build/rust-build.nix lib) { inherit rustPlatform; };
      inherit (hooks)
        vendorBuildHook
        unpackSrcHook
        prepareLockfileHook
        buildCrateHook
        ;
      mkLockfileDerivation = lib.makeOverridable (import ./vendor/parse-lockfile.nix lib) {
        inherit
          mkDerivation
          prepareLockfileHook
          ;
      };
      mkSourceDerivation = lib.makeOverridable (import ./vendor/src-derivation.nix lib) {
        inherit
          mkDerivation
          fetchurl
          unpackSrcHook
          crateRegistries
          ;
      };
      collectDependencies = lib.makeOverridable (import ./vendor/collect-deps.nix lib) {
        inherit mkLockfileDerivation mkSourceDerivation;
      };
      mkVendoredDerivation = lib.makeOverridable (import ./vendor/vendor.nix lib) {
        inherit mkDerivation vendorBuildHook;
      };
      mkBuildCrateDerivation = lib.makeOverridable (import ./build/crate.nix lib) {
        inherit mkDerivation buildCrateHook;
      };

    };
  fix = lib.fixedPoints.makeExtensible combine;
  extract = attr: {
    inherit (attr)
      rust-build
      mkStandardCrateRegistry
      crateRegistries
      vendorBuildHook
      unpackSrcHook
      prepareLockfileHook
      buildCrateHook
      mkLockfileDerivation
      mkSourceDerivation
      collectDependencies
      mkVendoredDerivation
      mkBuildCrateDerivation
      ;
    modify = f: extract (attr.extend f);
  };
in
extract fix
