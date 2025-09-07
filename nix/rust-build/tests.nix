{ runCommand }:
rust-build: {
  help = runCommand "rust-build-help" { } ''"${rust-build}/bin/nix-rust-build" --help > "$out"'';
}
