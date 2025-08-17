lib: rec {

  /**
    # Type
    ```
    assertAttrWith :: String -> AttrSet | Any -> AttrSet | error
    ```
  */
  assertAttrWith = message: val: if builtins.isAttrs val then val else throw message;

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
      assertAttrWith "The override function did not return an attribute set." (current prev)
    else
      mergeAttrsDeep prev (assertAttrWith "Overrides must either be a function or attr set." current)
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

}
