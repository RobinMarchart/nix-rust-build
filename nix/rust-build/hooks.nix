{
  lib,
  makeSetupHook,
  rust-build,
  cargo,
  rustc,
}:
let
  simpleMapper =
    name: script:
    lib.makeOverridable (
      { makeSetupHook, rust-build }:
      makeSetupHook {
        inherit name;
        propagatedBuildInputs = [ rust-build ];
      } script
    ) { inherit makeSetupHook rust-build; };
  simple = builtins.mapAttrs simpleMapper {
    vendorBuildHook = ./vendor-build.sh;
    unpackSrcHook = ./unpack-src.sh;
    prepareLockfileHook = ./prepare-lockfile.sh;
  };
  buildCrateHook = lib.makeOverridable (
    {makeSetupHook, rust-build, rustc}:
    makeSetupHook {
      name = "buildCrateHook";
      propagatedBuildInputs = [rust-build rustc];
    } ./build.sh
  ) {inherit makeSetupHook rust-build rustc;};
cargoMetadataHook = lib.makeOverridable (
    {makeSetupHook, rust-build, cargo}:
    makeSetupHook {
      name = "cargoMetadataHook";
      propagatedBuildInputs = [rust-build cargo];
    } ./build.sh
  ) {inherit makeSetupHook rust-build cargo;};
  in
simple // {inherit buildCrateHook cargoMetadataHook;}
