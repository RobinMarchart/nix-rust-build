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
      rb = lib.rustBuild;
      addSrc = rb.addSrcRaw {
        inherit workspaceSrc sources;
      };
      getOverride = rb.getOverrideRaw crateOverrides;
      prepareCommon = rb.prepareCommonRaw {
        inherit addSrc getOverride;
      };
      findDeps = rb.findDepsRaw buildPlan;

      prepareJob = rb.prepareJobRaw {
        inherit findDeps getOverride;
      };
      mkBuildScriptPkg = rb.mkBuildScriptPkgRaw {
        inherit mkBuildCrateDerivation prepareJob;
      };
      mkBuildScriptRun = rb.mkBuildScriptRunRaw {
        inherit mkRunBuildScriptDerivation prepareJob;
      };
      mkLibPkg = rb.mkLibPkgRaw {
        inherit mkBuildCrateDerivation prepareJob;
      };
      mkBinPkg = rb.mkBinPkgRaw {
        inherit mkBuildCrateDerivation prepareJob;
      };
      addBins = rb.addBinsRaw {
        inherit mkBinPkg;
      };
      addLib = rb.addLibRaw {
        inherit mkLibPkg addBins;
      };
      addBuildScript = rb.addBuildScriptRaw {
        inherit
          mkBuildScriptPkg
          mkBuildScriptRun
          addLib
          ;
      };
      mkPackage = rb.mkPackageRaw {
        inherit addBuildScript prepareCommon;
      };
    in
    builtins.mapAttrs (id: mkPackage) packages
  );
  workspaceMembers = builtins.mapAttrs (_: package: buildPlan.${package}) workspace;
  other = { inherit workspaceMembers buildPlan metadata_out; };
in
if isNull mainPackage then
  other
else
  (
    let
      main = buildPlan.${mainPackage};
    in
    if lib.isDerivation main then
      main.overrideAttrs (p: {
        passthru = (p.passthru or { }) // other;
      })
    else
      main // other
  )
