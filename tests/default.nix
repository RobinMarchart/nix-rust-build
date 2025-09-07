lib: let buildLib = import ../nix/lib.nix lib;
in{
  mergeAttrsDeep = import ./mergeAttrsDeep.nix buildLib;
  foldOverrides = import ./foldOverrides.nix buildLib;
  mergeListAttrSets = import ./mergeListAttrSets.nix buildLib;
  patchSrc = import ./patchSrc.nix buildLib;
}
