{ lib, rust-build }:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.lock
      ./Cargo.toml
      ./src
    ];
  };

in
rust-build {
  inherit src;
  pname = "rust-build-helper";
  version = "0.1.0";
}
