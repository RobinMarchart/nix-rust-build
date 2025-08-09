lib:
{
  mkDerivation,
  prepareLockfileHook,
}:
lib.extendMkDerivation {
  constructDrv = mkDerivation;
  excludeDrvArgNames = [];
  extendDrvArgs =
    final:
    {
      pname,
      version,
      lockFilePath ? "Cargo.lock",
      ...
    }:
    {
      inherit lockFilePath;
      name = "${pname}-${version}-lockfile.json";
      nativeBuildInputs = [ prepareLockfileHook ];
    };
}
