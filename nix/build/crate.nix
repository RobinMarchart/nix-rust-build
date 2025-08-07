lib:
{
  mkDerivation,
  buildCrateHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [
    "specialArg"
    "path"
    "edition"
    "features"
    "allFeatures"
    "crateDeps"
    "optimize"
    "debuginfo"
    "target"
  ];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      path,
      edition,
      crateType,
      target,
      features ? [ ],
      allFeatures ? [ ],
      crateDeps ? { },
      optimize ? true,
      debuginfo ? true,
      ...
    }:
    {
      crateType = crateType;
      rustBuildCrateJob = builtins.toJSON {
        inherit
          pname
          version
          path
          edition
          features
          allFeatures
          crateDeps
          optimize
          debuginfo
          target
          ;
      };
      passAsFile = [ "rustBuildCrateJob" ];
      nativeBuildInputs = [ buildCrateHook ];
    };
}
