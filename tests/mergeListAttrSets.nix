lib: let inherit(lib) mergeListAttrSets; in {
  test = {
    expr = mergeListAttrSets [{a=1; b=[1 2];} {a=[2 3]; b=3;}];
    expected = {a=[1 2 3]; b=[1 2 3];};
  };
}
