{ lib, rustPlatform }:
let
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../Cargo.lock
      ../../Cargo.toml
      ../../src
    ];
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  inherit src;
  pname = "rust-build-helper";
  version = "0.1.0";
  cargoLock = {
    lockFile = ../../Cargo.lock;
  };
  RUSTFLAGS = "-C debuginfo=line-tables-only";
  dontStrip = true;
})
