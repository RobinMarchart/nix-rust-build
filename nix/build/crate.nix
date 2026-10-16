lib:
{
  mkDerivation,
  buildCrateHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [
    "specialArg"
  ];
  extendDrvArgs =
    _final:
    {
      src,
      rustcFlags ? [ ],
      cfgs ? [ ],
      linkArgs ? [ ],
      manifestPath,
      version,
      pname,
      description ? "",
      longDescription ? "",
      repository ? null,
      homepage ? repository,
      rustVersion ? null,
      target,
      features ? [ ],
      allFeatures ? [ ],
      crateName,
      edition,
      deps ? [ ],
      optimize ? true,
      debuginfo ? true,
      crateType,
      entrypoint,
      targetName,
      nativeBuildInputs ? [ ],
      doCheck ? false,
      enableParallelBuilding ? true,
      meta ? { },
      ...
    }:
    let
      separateDebugInfo = debuginfo && (crateType == "bin" || crateType == "cdylib");
      dontStrip = crateType != "bin" && crateType != "cdylib";
    in
    {
      __structuredAttrs = true;
      inherit
        separateDebugInfo
        dontStrip
        src
        doCheck
        enableParallelBuilding
        ;
      dontConfigure = true;
      dontInstall = true;
      inherit
        rustcFlags
        cfgs
        linkArgs
        manifestPath
        version
        pname
        rustVersion
        target
        features
        allFeatures
        crateName
        edition
        deps
        optimize
        debuginfo
        crateType
        entrypoint
        targetName
        ;
      nativeBuildInputs = nativeBuildInputs ++ [
        buildCrateHook
      ];
      meta = {
        inherit
          description
          longDescription
          homepage
          ;
        sourceProvenance = [ lib.sourceTypes.fromSource ];
      }
      // meta;
    };
}
