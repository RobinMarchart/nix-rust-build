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
  ];
  extendDrvArgs =
    final:
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
      separateDebugInfo ? true,
      ...
    }:
    {
      inherit separateDebugInfo src;
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
          ;
      };
      passAsFile = [ "rustBuildCrateJob" ];
      nativeBuildInputs = [ buildCrateHook ];
    };
}
