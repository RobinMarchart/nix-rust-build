lib:
{
  mkDerivation,
  cargoMetadataHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [ ];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      vendorDir,
      target,
      src,
      features ? [ ],
      noDefaultFeatures ? false,
      ...
    }:
    {
      inherit
        vendorDir
        target
        src
        features
        noDefaultFeatures
        ;
      name = "${pname}-${version}-cargo-metadata.json";
      nativeBuildInputs = [ cargoMetadataHook ];
    };
}
