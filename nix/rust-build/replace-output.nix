{
  mkDerivation,
  cargo,
  rustc,
}:
mkDerivation {
  __structuredAttrs = true;
  nativeBuildInputs = [
    cargo
    rustc
  ];
  name = "replace-output-helper";
  src = builtins.path { path = ../../replace-output; };
  buildPhase = ''
    cargo build --release --frozen
  '';
  installPhase = ''
    install -Dm755 target/release/replace-output "$out/bin/replace-output"
  '';
}
