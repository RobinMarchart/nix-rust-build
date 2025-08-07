lib:
{
  mkDerivation,
  cargoMetadataHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [];
  extendDrvArgs = final: {
    pname,version,vendorDir,target,...
  }:{
    inherit vendorDir target;
    name = "${pname}-${version}-cargo-metadata.json";
    preferLocalBuild = true;
    nativeBuildInputs = [cargoMetadataHook];
  };
}
