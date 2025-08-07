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
  metadata_val = builtins.readJson(builtins.readFile metadata_out);
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
        }:
        let
          get = val: if builtins.hasAttr val crateOverrides then builtins.getAttr val crateOverrides else { };
          general = get "__common";
          byName = get pname;
          full = get "${pname}-${version}";
        in(removeAttrs common ["mainWorkspace"])
        // {
          src = if mainWorkspace then workspaceSrc else builtins.getAttr "${pname}-${version}" sources;
        }
        // general
        // byName
        // full;
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
        job@{ deps }:
        common
        // job
        // {
          deps = patchDeps deps;
        };
      mapPackage =
        id:
        package@{ common }:
        let
          c = patchCommon common;
          buildScript =
            if package ? buildScript then
              mkBuildCrateDerivation (removeAttrs (patchCompileJob c package.buildScript) [ "mainDeps" "mainCrateName" ])
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
                  script = buildScript;
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
          rustLib = if package ? rustLib then makeCompileJob package.rustLib else null;
          cLib = if package ? cLib then makeCompileJob package.cLib else null;
          bins = if package ? bins then map makeCompileJob package.bins else null;
          o1 = if isNull buildScript then { } else { inherit buildScript buildScriptRun; };
          o2 = if isNull rustLib then o1 else o1 // { inherit rustLib; };
          o3 = if isNull cLib then o2 else o2 // { inherit cLib; };
          o4 = if isNull bins then o3 else o3 // { inherit bins; };
        in
        o4;
    in
    builtins.mapAttrs mapPackage packages
  );
  workspaceMembers =  builtins.mapAttrs (_: package: buildPlan.${package}) workspace;
  other = {inherit workspaceMembers buildPlan; };
in
if isNull mainPackage then other else buildPlan.${mainPackage} // other
