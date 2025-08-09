lib:
{
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
  features ? [ ],
  noDefaultFeatures ? false,
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
      features
      noDefaultFeatures
      ;
  };
in
mkBuildPlan {
  inherit metadata_out;
  sources = collectedCrates;
  workspaceSrc = src;
}
