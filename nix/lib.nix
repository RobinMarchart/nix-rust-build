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

  patchSrc =
    { workspaceSrc, sources }:
    common@{
      mainWorkspace,
      pname,
      version,
      ...
    }:
    (removeAttrs common [ "mainWorkspace" ])
    // {
      src = if mainWorkspace then workspaceSrc else sources.${"${pname}-${version}"}.path;
    };

  patchOverrides =
    crateOverrides:
    let
      get = val: crateOverrides.${val} or [ ];
    in
    common@{ pname, version, ... }:
    let
      overrides = (get "__common") ++ (get pname) ++ (get "${pname}-${version}");
    in
    foldOverrides common overrides;

  patchCommon =
    {
      workspaceSrc,
      sources,
      crateOverrides,
    }:
    let
      patchSrc' = patchSrc { inherit workspaceSrc sources; };
      patchOverrides' = patchOverrides crateOverrides;
    in
    common: patchOverrides' (patchSrc' common);

  patchDeps =
    buildPlan:
    let
      mapper =
        { name, pkg }:
        {
          inherit name;
          path = buildPlan.${pkg}.rustLib;
        };
    in
    builtins.map mapper;
  patchJob =
    patchDeps': common:
    job@{ deps, ... }:
    let
      a =
        common
        // job
        // {
          deps = patchDeps' deps;
        };
      a' = if a ? src then a else break a;
    in
    a';
  mkBuildScriptPkg =
    { mkBuildCrateDerivation, patchJob' }:
    { common, buildScript }:
    let
      buildScript' = removeAttrs buildScript [
        "mainDeps"
        "mainCrateName"
      ];
    in
    mkBuildCrateDerivation (patchJob' common buildScript');
  mkBuildScriptRun =
    { mkRunBuildScriptDerivation, patchDeps' }:
    {
      common,
      buildScript,
      buildScriptBin,
    }:
    mkRunBuildScriptDerivation (
      common
      // {

        deps = patchDeps' buildScript.mainDeps;
        crateName = buildScript.mainCrateName;
        buildScript = buildScriptBin;
      }
    );
  mkBuildScriptCombined =
    {
      mkBuildCrateDerivation,
      patchJob',
      mkRunBuildScriptDerivation,
      patchDeps',
    }:
    let
      mkBuildScriptPkg' = mkBuildScriptPkg { inherit mkBuildCrateDerivation patchJob'; };
      mkBuildScriptRun' = mkBuildScriptRun { inherit mkRunBuildScriptDerivation patchDeps'; };
    in
    args@{ common, buildScript }:
    let
      buildScriptBin = mkBuildScriptPkg' args;
      buildScriptRun = mkBuildScriptRun' { inherit common buildScript buildScriptBin; };
    in
    {
      common'' = common // {
        inherit buildScriptRun;
      };
      out = { inherit buildScriptBin buildScriptRun; };
    };

  mkPackage =
    {
      mkBuildCrateDerivation,
      mkRunBuildScriptDerivation,
      buildPlan,
      workspaceSrc,
      sources,
      crateOverrides,
    }:
    let
      patchCommon' = patchCommon {
        inherit
          workspaceSrc
          sources
          crateOverrides
          ;
      };
      patchDeps' = patchDeps buildPlan;
      patchJob' = patchJob patchDeps';
      mkBuildScriptCombined' = mkBuildScriptCombined {
        inherit

          mkBuildCrateDerivation
          patchJob'
          mkRunBuildScriptDerivation
          patchDeps'
          ;
      };
    in
    id:
    package@{ common, ... }:
    let
      common' = patchCommon' common;
      buildScriptOut =
        if package ? buildScript && !isNull package.buildScript then
          mkBuildScriptCombined' {
            common = common';
            buildScript = package.buildScript;
          }
        else
          {
            common'' = common';
            out = { };
          };
      inherit (buildScriptOut) common'' out;
      patchJob'' =
        let
          patchJob'' = patchJob' common'';
        in
        job: mkBuildCrateDerivation (patchJob'' job);
      mkBin =
        job:
        let
          deriv = patchJob'' job;
        in
        {
          name = deriv.pname;
          value = deriv;
        };
      out' =
        if package ? rustLib && !isNull package.rustLib then
          out // { rustLib = patchJob'' package.rustLib; }
        else
          out;
      out'' =
        if package ? cLib && !isNull package.cLib then
          out' // { cLib = patchJob'' package.cLib; }
        else
          out';
      out''' =
        if package ? bins && !isNull package.bins then
          let
            bins = builtins.listToAttrs (map mkBin package.bins);
          in
          out'' // bins // { inherit bins; }
        else
          out'';
    in
    out''';
}
