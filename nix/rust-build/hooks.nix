{
  lib,
  makeSetupHook,
  rust-build,
  cargo,
  rustc,
  rustdoc,
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
    {makeSetupHook, rust-build, rustc, cargo}:
    makeSetupHook {
      name = "buildCrateHook";
      propagatedBuildInputs = [rust-build rustc cargo];
    } ./build.sh
  ) {inherit makeSetupHook rust-build rustc cargo;};
cargoMetadataHook = lib.makeOverridable (
    {makeSetupHook, rust-build, cargo}:
    makeSetupHook {
      name = "cargoMetadataHook";
      propagatedBuildInputs = [rust-build cargo];
    } ./cargo-metadata.sh
  ) {inherit makeSetupHook rust-build cargo;};
runBuildScriptHook = lib.makeOverridable (
    {makeSetupHook, rust-build, rustc, cargo, rustdoc}:
    makeSetupHook {
      name = "runBuildScriptHook";
      propagatedBuildInputs = [rust-build cargo rustc rustdoc];
    } ./run-build-script.sh
  ) {inherit makeSetupHook rust-build cargo rustc rustdoc;};

  in
simple // {inherit buildCrateHook cargoMetadataHook runBuildScriptHook;}
