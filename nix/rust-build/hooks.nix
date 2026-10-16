{
  lib,
  makeSetupHook,
  cargo,
  rustc,
  rustdoc,
  helper,
  replace-output,
}:
let
  file =
    path:
    builtins.path {
      inherit path;
      recursive = false;
    };
in
{
  prepareLockfileHook = lib.makeOverridable (
    { makeSetupHook, helper }:
    makeSetupHook {
      name = "prepareLockfileHook";
      propagatedBuildInputs = [ helper ];
    } (file ./prepare-lockfile.sh)
  ) { inherit makeSetupHook helper; };
  unpackSrcHook = lib.makeOverridable (
    { makeSetupHook, helper }:
    makeSetupHook {
      name = "unpackSrcHook";
      propagatedBuildInputs = [ helper ];
    } (file ./unpack-src.sh)
  ) { inherit makeSetupHook helper; };
  vendorBuildHook = lib.makeOverridable (
    { makeSetupHook, helper }:
    makeSetupHook {
      name = "vendorBuildHook";
      propagatedBuildInputs = [ helper ];
    } (file ./vendor-build.sh)
  ) { inherit makeSetupHook helper; };
  cargoMetadataHook = lib.makeOverridable (
    {
      makeSetupHook,
      helper,
      cargo,
    }:
    makeSetupHook {
      name = "cargoMetadataHook";
      propagatedBuildInputs = [
        helper
        cargo
      ];
    } (file ./cargo-metadata.sh)
  ) { inherit makeSetupHook helper cargo; };
  buildCrateHook =
    lib.makeOverridable
      (
        {
          makeSetupHook,
          helper,
          rustc,
          cargo,
        }:
        makeSetupHook {
          name = "buildCrateHook";
          propagatedBuildInputs = [
            helper
            rustc
            cargo
          ];
        } ./build.sh
      )
      {
        inherit
          makeSetupHook
          helper
          rustc
          cargo
          ;
      };
  runBuildScriptHook =
    lib.makeOverridable
      (
        {
          makeSetupHook,
          helper,
          rustc,
          cargo,
          rustdoc,
        }:
        makeSetupHook {
          name = "runBuildScriptHook";
          propagatedBuildInputs = [
            helper
            cargo
            rustc
            rustdoc
          ];
        } ./run-build-script.sh
      )
      {
        inherit
          makeSetupHook
          helper
          cargo
          rustc
          rustdoc
          ;
      };
  fixupBuildScriptOutHook = lib.makeOverridable (
    { makeSetupHook, replace-output }:
    makeSetupHook {
      name = "fixupBuildScriptOutHook";
      propagatedBuildInputs = [ replace-output ];
    } (file ./fixup-build-script-out.sh)
  ) { inherit makeSetupHook replace-output; };
}
