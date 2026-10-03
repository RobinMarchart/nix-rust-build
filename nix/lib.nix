lib: rec {

  /**
    # Type
    ```
    assertIsAttrWith :: String -> AttrSet | Any -> AttrSet | error
    ```
  */
  assertIsAttrWith = message: val: if builtins.isAttrs val then val else throw message;

  /**
    Merge two attr sets together recursively.
    The result is a union of both sets.
    For every attribute in both sets they are recursively merged if both are sets.
    If both are lists the result is both of then appended together in the same order as supplied to this function.
    In any other case, the result is the value in the second set.

    # Type
    ```
    mergeAttrsDeep :: AttrSet -> AttrSet -> AttrSet
    ```
  */
  mergeAttrsDeep =
    let
      mapper =
        prev: current:
        if (builtins.isAttrs prev) && (builtins.isAttrs current) then
          mergeAttrsDeep prev current
        else if (builtins.isList prev) && (builtins.isList current) then
          prev ++ current
        else
          current;
      mapList =
        _: list:
        if builtins.length list == 1 then
          builtins.elemAt list 0
        else if builtins.length list == 2 then
          mapper (builtins.elemAt list 0) (builtins.elemAt list 1)
        else
          abort "should only be called with two values";

    in
    prev: current:
    builtins.zipAttrsWith mapList [
      prev
      current
    ];

  /**
    Apply overrides from a list sequentially.
    If an override is an function, it is called with the previous value and must return another attr set.
    If it is an attr set, it is merged with the previous value with mergeAttrsDeep

    #Type
    ```
    foldOverrides :: AttrSet -> [ (AttrSet -> AttrSet) | AttrSet ] -> AttrSet
    ```
  */
  foldOverrides = builtins.foldl' (
    prev: current:
    if lib.isFunction current then
      assertIsAttrWith "The override function did not return an attribute set." (current prev)
    else
      mergeAttrsDeep prev (assertIsAttrWith "Overrides must either be a function or attr set." current)
  );

  /**
    #Type
    ```
    toList :: [Any] | Any -> [Any]
    ```
  */
  toList = val: if builtins.isList val then val else [ val ];

  /**
    #Type
    ```
    mergeListAttrSets :: [ { [ Any ] | Any } ] -> { [ Any ] }
    ````
  */
  mergeListAttrSets =
    let
      mapper = _: list: builtins.concatMap toList list;
    in
    builtins.zipAttrsWith mapper;

  /**
    set the correct src depending on the value of mainWorkspace
    filter: should filter to the path of the workspace member
  */
  addSrcRaw =
    { workspaceSrc, sources }:
    common@{
      mainWorkspace,
      pname,
      version,
      ...
    }:
    (removeAttrs common [ "mainWorkspace" ])
    // (
      if mainWorkspace then
        (
          let

            inherit (common) manifestPath;
            filteredDir = dirOf manifestPath;
            src = builtins.path { path = "${workspaceSrc}/${filteredDir}"; };
          in
          {
            inherit src filteredDir;
          }
        )
      else
        {
          src = sources.${"${pname}-${version}"}.path;
          filteredDir = "";
        }
    );

  getOverrideRaw = crateOverrides: name: crateOverrides.${name} or [ ];

  prepareCommonRaw =
    {
      addSrc,
      getOverride,
    }:

    common@{ pname, version, ... }:
    let
      with-src = addSrc common;
      __common = getOverride "__common";
      name = getOverride pname;
      name-version = getOverride "${pname}-${version}";
      overrides = __common ++ name ++ name-version;
    in
    foldOverrides with-src overrides;

  findDepsRaw =
    buildPlan:
    let
      mapper =
        { name, pkg }:
        {
          inherit name;
          path = buildPlan.${pkg}.rustLib;
        };
      op = map mapper;
    in
    job@{ deps, ... }:
    job
    // {
      deps = op deps;
    };

  prepareJobRaw =
    { findDeps, getOverride }:
    run_type:
    { common, job }:
    let
      name-type = getOverride "${common.pname}-${run_type}";
      name-type-version = getOverride "${common.pname}-${run_type}-${common.version}";
      applied = foldOverrides (common // job) (name-type ++ name-type-version);
    in
    findDeps applied;

  mkBuildScriptPkgRaw =
    { mkBuildCrateDerivation, prepareJob }:
    let
      prepareJob' = prepareJob "script-build";
    in
    { common, buildScript }:
    let
      buildScript' = removeAttrs buildScript [
        "mainDeps"
      ];
    in
    mkBuildCrateDerivation (prepareJob' {
      inherit common;
      job = buildScript';
    });

  mkBuildScriptRunRaw =
    { mkRunBuildScriptDerivation, prepareJob }:
    let
      prepareJob' = prepareJob "script-run";
    in
    {
      common,
      buildScript,
      buildScriptBin,
    }:
    let
      job = {
        deps = buildScript.mainDeps;
        edition = buildScript.edition;
        buildScript = buildScriptBin;
      };
    in
    mkRunBuildScriptDerivation (prepareJob' {
      inherit common job;
    });

  mkLibPkgRaw =
    { mkBuildCrateDerivation, prepareJob }:
    let
      prepareJob' = prepareJob "lib";
    in
    { common, rustLib }:
    mkBuildCrateDerivation (prepareJob' {
      inherit common;
      job = rustLib;
    });

  mkBinPkgRaw =
    { mkBuildCrateDerivation, prepareJob }:
    let
      prepareJob' = prepareJob "bin";
    in
    { common, bin }:
    mkBuildCrateDerivation (prepareJob' {
      inherit common;
      job = bin;
    });

  addBinsRaw =
    {
      mkBinPkg,
    }:
    {
      package,
      common,
      res,
    }:
    if package ? bins && !isNull package.bins then
      let
        bins = package.bins;
        len = builtins.length bins;
      in
      (
        if len == 0 then
          res
        else
          (
            if len == 1 then
              let
                passthru = if common ? passthru then res // common.passthru else res;
              in
              mkBinPkg {
                common = common // {
                  inherit passthru;
                };
                bin = builtins.elemAt bins 0;
              }
            else
              let
                mapper =
                  bin:
                  let
                    drv = mkBinPkg { inherit common bin; };
                  in
                  {
                    name = drv.pname;
                    value = drv;
                  };
              in
              res // builtins.listToAttrs (map mapper bins)
          )

      )
    else
      res;

  addLibRaw =
    {
      mkLibPkg,
      addBins,
    }:
    args@{
      package,
      common,
      res,
    }:
    if package ? rustLib && !isNull package.rustLib then
      let
        rustLib = mkLibPkg {
          inherit common;
          inherit (package) rustLib;
        };
        res' = res // {
          inherit rustLib;
        };
      in
      addBins {
        inherit package common;
        res = res';
      }
    else
      addBins args;

  addBuildScriptRaw =
    {
      mkBuildScriptPkg,
      mkBuildScriptRun,
      addLib,
    }:
    args@{
      package,
      common,
      res,
    }:
    if package ? buildScript && !isNull package.buildScript then
      let
        inherit (package) buildScript;
        buildScriptBin = mkBuildScriptPkg { inherit common buildScript; };
        buildScriptRun = mkBuildScriptRun { inherit common buildScript buildScriptBin; };
        common' = common // {
          inherit buildScriptRun;
        };
        res' = res // {
          inherit buildScriptRun;
        };
      in
      addLib {
        inherit package;
        common = common';
        res = res';
      }
    else
      addLib args;

  mkPackageRaw =
    {
      addBuildScript,
      prepareCommon,
    }:
    package@{ common, ... }:
    addBuildScript {
      inherit package;
      res = { };
      common = prepareCommon common;
    };
}
