lib:
{ mkLockfileDerivation, mkSourceDerivation ,}:
{
  src,
  pname,
  version,
  lockFilePath ? "/Cargo.lock",
}:
let
  lockfile = mkLockfileDerivation {
    inherit
      src
      pname
      version
      lockFilePath
      ;
  };
  lockfileData = builtins.fromJSON (builtins.readFile lockfile);
  mapper =
    full-name:
    {
      name,
      version,
      registry,
      checksum,
      dir_name,
    }:
    {
      inherit registry dir_name;
      path = mkSourceDerivation {
        inherit version checksum;
        pname = name;
        registry_url = registry;
      };
    };
in
builtins.mapAttrs mapper lockfileData
