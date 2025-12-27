{
  pkg-config,
  mpv-unwrapped,
  rustPlatform,
  sqlite,
  rust-build,
  fetchFromGitHub,
  runCommand,
}:
let
  src = fetchFromGitHub {
    owner = "owo-uwu-nyaa";
    repo = "jellyfin-tui-rs";
    rev = "436e75e1ceeef6da2607a9cb3ca34a3ec18d875b";
    hash = "sha256-1fs/6cwO6055Nw2z4mGpjYAYdoQ1P/+h+jycFMmWl/U=";
  };
  jellyfin-tui =
    (rust-build.withCrateOverrides {
      libmpv-sys = {
        buildInputs = [ mpv-unwrapped ];
        nativeBuildInputs = [
          pkg-config
          rustPlatform.bindgenHook
        ];
      };
      libsqlite3-sys = {
        buildInputs = [ sqlite ];
        nativeBuildInputs = [
          pkg-config
          rustPlatform.bindgenHook
        ];
      };
    }).build
      {
        inherit src;
        pname = "jellyfin-tui";
        version = "0.1.0";
      };
in
runCommand "config" { } ''"${jellyfin-tui}/bin/jellyfin-tui-rs" print config > "$out"''
