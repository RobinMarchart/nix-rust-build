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
      ...
    }:
    {
      inherit vendorDir target src;
      name = "${pname}-${version}-cargo-metadata.json";
      nativeBuildInputs = [ cargoMetadataHook ];
      RUST_BACKTRACE="1";
    };
}
