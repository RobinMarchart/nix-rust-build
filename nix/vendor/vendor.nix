lib:
{
  mkDerivation,
  vendorBuildHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [
    "specialArg"
    "collectedCrates"
    "rust-build-bin"
  ];
  extendDrvArgs =
    final:
    {
      collectedCrates,
      passAsFile ? [ ],
      nativeBuildInputs ? [ ],
    }:
    {
      passthru = { inherit collectedCrates; };
      name = "rust-vendored-src";
      preferLocalBuild = true;
      allowSubstitutes = false;
      job = builtins.toJSON collectedCrates;
      passAsFile = passAsFile ++ [ "job" ];
      dontUnpack = true;
      nativeBuildInputs = nativeBuildInputs ++ [ vendorBuildHook ];
    };
}
