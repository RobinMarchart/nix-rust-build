lib:
let
  inherit (lib) patchSrc;
in
{
  testMain = {
    expr =
      patchSrc
        {
          workspaceSrc = "test";
          sources = abort "should not be evaled";
        }
        {
          mainWorkspace = true;
          pname = "name";
          version = "version";
          add = 1;
        };
    expected = {
      src = "test";
      pname = "name";
      version = "version";
      add = 1;
    };
  };
  testSources = {
    expr =
      patchSrc
        {
          workspaceSrc = abort "main src evaled";
          sources = {
            name-version = {
              path = "src";
            };
          };
        }
        {
          mainWorkspace = false;
          pname = "name";
          version = "version";
          test = "ex";
        };
    expected = {
      src = "src";
      pname = "name";
      version = "version";
      test = "ex";
    };
  };
}
