pkgs:
let
  lib = pkgs.lib // {
    rustBuild = import ./lib.nix pkgs.lib;
  };
  registry_import = import ./vendor/registries.nix;
  combine =
    final:
    let
      inherit (final)
        crateOverrides
        targets
        target
        rustc
        cargo
        rustdoc
        nushell
        rustPlatform
        mkDerivation
        fetchurl
        makeSetupHook
        runCommand
        mkStandardCrateRegistry
        defaultCrateRegistries
        extraCrateRegistries
        rust-build
        vendorBuildHook
        unpackSrcHook
        prepareLockfileHook
        buildCrateHook
        cargoMetadataHook
        runBuildScriptHook
        mkLockfileDerivation
        mkSourceDerivation
        collectDependencies
        mkVendoredDerivation
        mkMetadataDerivation
        mkBuildCrateDerivation
        mkRunBuildScriptDerivation
        mkBuildPlan
        ;
      crateRegistries = defaultCrateRegistries // extraCrateRegistries;
      hooks = import ./rust-build/hooks.nix {
        inherit
          lib
          makeSetupHook
          rust-build
          cargo
          rustc
          rustdoc
          nushell
          ;
      };
    in
    {
      crateOverrides = { };
      targets = import ./targets.nix;
      target = targets.${pkgs.system};
      inherit (pkgs)
        cargo
        rustc
        nushell
        rustPlatform
        fetchurl
        makeSetupHook
        runCommand
        ;
      rustdoc = pkgs.rustc;
      inherit crateRegistries;
      mkDerivation = pkgs.stdenv.mkDerivation;
      mkStandardCrateRegistry = registry_import.mkStandardCrateRegistry;
      defaultCrateRegistries = lib.makeOverridable registry_import.defaultCrateRegistries {
        inherit mkStandardCrateRegistry;
      };
      extraCrateRegistries = { };
      rust-build = lib.makeOverridable (import ./rust-build/rust-build.nix lib) {
        inherit rustPlatform runCommand;
      };
      inherit (hooks)
        vendorBuildHook
        unpackSrcHook
        prepareLockfileHook
        buildCrateHook
        cargoMetadataHook
        runBuildScriptHook
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
      mkMetadataDerivation = lib.makeOverridable (import ./build/metadata.nix lib) {
        inherit mkDerivation cargoMetadataHook;
      };
      mkBuildCrateDerivation = lib.makeOverridable (import ./build/crate.nix lib) {
        inherit mkDerivation buildCrateHook;
      };
      mkRunBuildScriptDerivation = lib.makeOverridable (import ./build/run-script.nix lib) {
        inherit mkDerivation runBuildScriptHook;
      };
      mkBuildPlan = lib.makeOverridable (import ./build/build-plan.nix lib) {
        inherit mkBuildCrateDerivation mkRunBuildScriptDerivation crateOverrides;
      };
      build = lib.makeOverridable (import ./build.nix lib) {
        inherit
          collectDependencies
          mkVendoredDerivation
          mkMetadataDerivation
          mkBuildPlan
          target
          ;
      };
    };
  fix = lib.fixedPoints.makeExtensible combine;
  extract =
    attr:
    let
      out = {
        inherit (attr)
          targets
          target
          crateOverrides
          rust-build
          mkStandardCrateRegistry
          crateRegistries
          vendorBuildHook
          unpackSrcHook
          prepareLockfileHook
          buildCrateHook
          cargoMetadataHook
          runBuildScriptHook
          mkLockfileDerivation
          mkSourceDerivation
          collectDependencies
          mkVendoredDerivation
          mkMetadataDerivation
          mkBuildCrateDerivation
          mkRunBuildScriptDerivation
          mkBuildPlan
          build
          ;
        modify = f: extract (attr.extend f);
        withCrateOverrides =
          override:
          extract (
            attr.extend (
              _: prev: {
                crateOverrides = lib.rustBuild.mergeListAttrSets [
                  prev.crateOverrides
                  override
                ];
              }
            )
          );
        withToolchain =
          toolchain:
          extract (
            attr.extend (
              _: _: {
                rustc = toolchain;
                cargo = toolchain;
                rustdoc = toolchain;
              }
            )
          );
      };
    in
    out.rust-build.overrideAttrs { passthru = out; };
in
extract fix
