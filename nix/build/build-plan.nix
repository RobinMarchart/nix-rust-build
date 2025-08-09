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
      patchCommon =
        common@{
          pname,
          version,
          mainWorkspace,
          ...
        }:
        let
          fix_type = val: if builtins.isList val then val else [ val ];
          get =
            val:
            if builtins.hasAttr val crateOverrides then fix_type (builtins.getAttr val crateOverrides) else [ ];
          overrides = (get "__common") ++ (get pname) ++ (get "${pname}-${version}");
          f =
            prev: f:
            let
              val = f prev;
            in
            if builtins.isAttrs val then prev // val else throw "non attrset returned from overwrite";
          val = (removeAttrs common [ "mainWorkspace" ]) // {
            src = if mainWorkspace then workspaceSrc else sources.${"${pname}-${version}"}.path;
          };
        in
        builtins.foldl' f val overrides;
      patchDeps =
        deps:
        let
          depMapper =
            { name, pkg }:
            {
              inherit name;
              path = buildPlan.${pkg}.rustLib;
            };
        in
        builtins.map depMapper deps;
      patchCompileJob =
        common:
        job@{ deps, ... }:
        common
        // job
        // {
          deps = patchDeps deps;
        };
      mapPackage =
        id:
        package@{ common, ... }:
        let
          c = patchCommon common;
          buildScript =
            if package ? buildScript && !isNull package.buildScript then
              mkBuildCrateDerivation (
                removeAttrs (patchCompileJob c package.buildScript) [
                  "mainDeps"
                  "mainCrateName"
                ]
              )
            else
              null;
          buildScriptRun =
            if isNull buildScript then
              null
            else
              mkRunBuildScriptDerivation (
                c
                // {
                  deps = patchDeps package.buildScript.mainDeps;
                  crateName = package.buildScript.mainCrateName;
                  inherit buildScript;
                }
              );
          makeCompileJob =
            job:
            (
              let
                j1 = patchCompileJob c job;
                j2 = if isNull buildScriptRun then j1 else j1 // { inherit buildScriptRun; };
              in
              mkBuildCrateDerivation j2
            );
          makeBinJob =
            job:
            (
              let
                deriv = makeCompileJob job;
              in
              {
                name = deriv.pname;
                value = deriv;
              }
            );
          rustLib =
            if package ? rustLib && !isNull package.rustLib then makeCompileJob package.rustLib else null;
          cLib = if package ? cLib && !isNull package.cLib then makeCompileJob package.cLib else null;
          bins =
            if package ? bins && !isNull package.bins then
              builtins.listToAttrs (map makeBinJob package.bins)
            else
              null;
          o1 = if isNull buildScript then { } else { inherit buildScript buildScriptRun; };
          o2 = if isNull rustLib then o1 else o1 // { inherit rustLib; };
          o3 = if isNull cLib then o2 else o2 // { inherit cLib; };
          o4 = if isNull bins then o3 else o3 // { inherit bins; };
        in
        o4;
    in
    builtins.mapAttrs mapPackage packages
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
