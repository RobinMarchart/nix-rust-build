lib: {
   testMerge = {
      expr = lib.mergeAttrsDeep {
        a = 1;
        b = 2;
        c = {
          a = [ 10];
          b = [ "a" ];
          c = {
            a = 1;
          };
        };
        d=[1];
      } {
        a=2;
        c={
          b = ["b"];
          c={b=2;};
        };
        d=[2 3];
      };
      expected = {
        a=2;
        b=2;
        c={
          a=[10];
          b=["a" "b"];
          c={
            a=1;
            b=2;
          };
        };
        d=[1 2 3];
      };
    };

}
