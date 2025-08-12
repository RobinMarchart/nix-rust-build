lib:
{
  mkDerivation,
  runBuildScriptHook,
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
    final:
    {
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
      buildScript,
      links? null,
      ...
    }:
    {
      inherit buildScript;
      rustRunBuildScriptJob = builtins.toJSON {
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
          links
          ;
      };
      passAsFile = [ "rustRunBuildScriptJob" ];
      nativeBuildInputs = [ runBuildScriptHook ];
    };
}
