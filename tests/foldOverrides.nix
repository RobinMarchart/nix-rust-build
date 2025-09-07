lib:
let
  inherit (lib) foldOverrides;
in
{
  testFunction = {
    expr = foldOverrides { a = 1; } [
      ({ a }: if a == 1 then { b = 2; } else abort "incorrect v1")
      ({ b }: if b == 2 then { c = b; } else abort "incorrect v2")
    ];
    expected = {
      c = 2;
    };
  };
  testFunctionInvalidReturn = {
    expr = foldOverrides { } [ (_: 1) ];
    expectedError = {
      type = "ThrownError";
      msg = "The override function did not return an attribute set.";
    };
  };
  testInvalidArg = {
    expr = foldOverrides { } [ 1 ];
    expectedError = {
      type = "ThrownError";
      msg = "Overrides must either be a function or attr set.";
    };
  };
  testMerge = {
    expr = foldOverrides { a = 1; } [
      { b = [ 2 ]; }
      {
        a = 10;
        b = [ 3 ];
      }
    ];
    expected = {
      a = 10;
      b = [
        2
        3
      ];
    };
  };
  testCombined = {
    expr = foldOverrides { a = 1; } [
      { b = 2; }
      ({ a, b }: if a == 1 && b == 2 then { c = 3; } else abort "val")
      { a = 5; }
    ];
    expected = {
      a = 5;
      c = 3;
    };
  };
}
