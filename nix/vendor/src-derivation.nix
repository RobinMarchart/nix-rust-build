lib:
{
  mkDerivation,
  fetchurl,
  unpackSrcHook,
  crateRegistries,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [
    "specialArg"
    "registries"
    "checksum"
    "fetcher"
  ];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      checksum,
      registry_url,
      fetcher ? fetchurl,
      registries ? crateRegistries,
      nativeBuildInputs ? [ ],
      ...
    }:
    let
      registry = builtins.getAttr registry_url registries;
      url = registry {
        inherit checksum;
        name = pname;
        inherit version;
      };
      src = fetcher {
        inherit url;
        hash = checksum;
        name = "source-${pname}-${version}.tar.gz";
      };
    in
    {
      inherit src;
      preferLocalBuild = true;
      allowSubstitutes = false;
      name = "source-${pname}-${version}";
      passthru.pkg-info = {
        inherit
          url
          registry_url
          ;
        inherit version;
        name = pname;
      };
      nativeBuildInputs = nativeBuildInputs ++ [ unpackSrcHook ];
    };
}
