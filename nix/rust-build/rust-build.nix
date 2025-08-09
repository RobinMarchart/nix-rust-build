lib:
{
  rustPlatform,
  runCommand,
}:
let
  src = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../src
      ../../Cargo.toml
      ../../Cargo.lock
    ];
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  inherit src;
  version = "0.1.0";
  pname = "nix-rust-build";
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  passthru.tests = import ./tests.nix {inherit runCommand;} finalAttrs.finalPackage;
})
