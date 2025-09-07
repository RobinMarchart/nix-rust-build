lib:
{
  mkBuildCrateDerivation,
  mkRunBuildScriptDerivation,
  crateOverrides,
}:
{
  workspaceSrc,
  sources,
  metadata_out,
}:
let
  metadata_val = builtins.fromJSON (builtins.readFile metadata_out);
  packages = metadata_val.packages;
  workspace = metadata_val.workspace;
  mainPackage = metadata_val.mainPackage or null;

  buildPlan = (
    let
      mkPackage' = lib.rustBuild.mkPackage {
        inherit
          mkBuildCrateDerivation
          mkRunBuildScriptDerivation
          buildPlan
          workspaceSrc
          sources
          crateOverrides
          ;
      };
    in
    builtins.mapAttrs mkPackage' packages
  );
  workspaceMembers = builtins.mapAttrs (_: package: buildPlan.${package}) workspace;
  other = { inherit workspaceMembers buildPlan; };
  package = if isNull mainPackage then other else buildPlan.${mainPackage} // other;
in
if package ? bins then
  let
    bins = builtins.attrValues package.bins;
  in
  if 1 == builtins.length bins then
    (builtins.elemAt bins 0).overrideAttrs (p: {
      passthru = (p.passthru or { }) // package;
    })
  else
    package
else
  package
