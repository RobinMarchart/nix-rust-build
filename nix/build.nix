lib: {
  collectDependencies,
  mkVendoredDerivation,
  mkMetadataDerivation,
  mkBuildPlan,
  target,
}:
{
  src,
  pname,
  version,
  lockFilePath ? "/Cargo.lock",
}:
let
  collectedCrates = collectDependencies {
    inherit
      src
      pname
      version
      lockFilePath
      ;
  };
  vendorDir = mkVendoredDerivation { inherit collectedCrates; };
  metadata_out = mkMetadataDerivation {
    inherit
      target
      vendorDir
      pname
      version
      src
      ;
  };
in
mkBuildPlan {
  inherit metadata_out;
  sources = collectedCrates;
  workspaceSrc = src;
}
