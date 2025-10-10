{
  lib,
  makeSetupHook,
  rust-build,
  cargo,
  rustc,
  rustdoc,
  nushell,
}:
let
  file =
    path:
    builtins.path {
      inherit path;
      recursive = false;
    };
  nu_files =
    paths:
    lib.fileset.toSource {
      root = ../../nu;
      fileset = lib.fileset.unions paths;
    };
in
{
  prepareLockfileHook = lib.makeOverridable (
    { makeSetupHook, nushell }:
    makeSetupHook {
      name = "prepareLockfileHook";
      propagatedBuildInputs = [ nushell ];
      substitutions = {
        prepare_lockfile = "${
          nu_files [
            ../../nu/version.nu
            ../../nu/prepare_lockfile.nu
          ]
        }/prepare_lockfile.nu";
      };
    } (file ./prepare-lockfile.sh)
  ) { inherit makeSetupHook nushell; };
  unpackSrcHook = lib.makeOverridable (
    { makeSetupHook, nushell }:
    makeSetupHook {
      name = "unpackSrcHook";
      propagatedBuildInputs = [ nushell ];
      substitutions = {
        install_src_hash = file ../../nu/install_src_hash.nu;
      };
    } (file ./unpack-src.sh)
  ) { inherit makeSetupHook nushell; };
  vendorBuildHook = lib.makeOverridable (
    { makeSetupHook, nushell }:
    makeSetupHook {
      name = "vendorBuildHook";
      propagatedBuildInputs = [ nushell ];
      substitutions = {
        write_vendor = file ../../nu/write_vendor.nu;
      };
    } (file ./vendor-build.sh)
  ) { inherit makeSetupHook nushell; };
  cargoMetadataHook = lib.makeOverridable (
    {
      makeSetupHook,
      nushell,
      cargo,
    }:
    makeSetupHook {
      name = "cargoMetadataHook";
      propagatedBuildInputs = [
        nushell
        cargo
      ];
      substitutions = {
        metadata = file ../../nu/metadata.nu;
      };
    } (file ./cargo-metadata.sh)
  ) { inherit makeSetupHook nushell cargo; };
  buildCrateHook =
    lib.makeOverridable
      (
        {
          makeSetupHook,
          nushell,
          rustc,
          cargo,
        }:
        makeSetupHook {
          name = "buildCrateHook";
          propagatedBuildInputs = [
            nushell
            rustc
            cargo
          ];
          substitutions = {
            run_build = "${
              nu_files [
                ../../nu/run_build.nu
                ../../nu/run_common.nu
                ../../nu/version.nu
              ]
            }/run_build.nu";
          };
        } ./build.sh
      )
      {
        inherit
          makeSetupHook
          nushell
          rustc
          cargo
          ;
      };
  runBuildScriptHook =
    lib.makeOverridable
      (
        {
          makeSetupHook,
          nushell,
          rustc,
          cargo,
          rustdoc,
        }:
        makeSetupHook {
          name = "runBuildScriptHook";
          propagatedBuildInputs = [
            nushell
            cargo
            rustc
            rustdoc
          ];
          substitutions = {
            run_build_script = "${
              nu_files [
                ../../nu/run_build_script.nu
                ../../nu/run_common.nu
                ../../nu/version.nu
              ]
            }/run_build_script.nu";
          };
        } ./run-build-script.sh
      )
      {
        inherit
          makeSetupHook
          nushell
          cargo
          rustc
          rustdoc
          ;
      };
}
