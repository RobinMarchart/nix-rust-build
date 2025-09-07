lib:
{
  mkDerivation,
  buildCrateHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [
    "specialArg"
    "rustcFlags"
    "cfgs"
    "linkArgs"
    "manifestPath"
    "authors"
    "description"
    "homepage"
    "repository"
    "license"
    "licenseFile"
    "rustVersion"
    "readme"
    "target"
    "features"
    "allFeatures"
    "crateName"
    "edition"
    "deps"
    "optimize"
    "debuginfo"
    "crateType"
    "entrypoint"
    "targetName"
    "buildScriptRun"
    "links"
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
      authors ? null,
      pname,
      description ? null,
      homepage ? null,
      repository ? null,
      license ? null,
      licenseFile ? null,
      rustVersion ? null,
      readme ? null,
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
      buildScriptRun ? null,
      links? null,
      nativeBuildInputs ? [ ],
      passAsFile ? [ ],
      ...
    }:
    let
      separateDebugInfo = debuginfo && (crateType == "bin" || crateType == "cdylib");
      dontStrip = crateType!="bin" && crateType != "cdylib";
        in
    {
      inherit separateDebugInfo dontStrip src;
      rustBuildCrateJob = builtins.toJSON {
        inherit
          rustcFlags
          cfgs
          linkArgs
          manifestPath
          version
          authors
          pname
          description
          homepage
          repository
          license
          licenseFile
          rustVersion
          readme
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
          buildScriptRun
          links
          ;
      };
      passAsFile = passAsFile ++ [ "rustBuildCrateJob" ];
      nativeBuildInputs = nativeBuildInputs ++ [ buildCrateHook ];
    };
}
