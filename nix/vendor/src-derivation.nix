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
    "fetcher"
  ];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      checksum,
      registry_url,
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
      src = fetchurl {
        inherit url;
        hash = checksum;
        name = "source-${pname}-${version}.tar.gz";
      };
    in
    {
      inherit src;
      preferLocalBuild = true;
      dontInstall = true;
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
      dontFixup = true;
    };
}
