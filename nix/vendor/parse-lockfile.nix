lib:
{
  mkDerivation,
  prepareLockfileHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [ ];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      lockFilePath ? "Cargo.lock",
      ...
    }:
    {
      __structuredAttrs = true;
      inherit lockFilePath;
      name = "${pname}-${version}-lockfile.json";
      nativeBuildInputs = [ prepareLockfileHook ];
    };
}
