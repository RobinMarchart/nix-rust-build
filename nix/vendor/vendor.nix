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
      nativeBuildInputs ? [ ],
    }:
    {
      __structuredAttrs = true;
      passthru = { inherit collectedCrates; };
      name = "rust-vendored-src";
      preferLocalBuild = true;
      job = collectedCrates;
      dontUnpack = true;
      nativeBuildInputs = nativeBuildInputs ++ [ vendorBuildHook ];
    };
}
