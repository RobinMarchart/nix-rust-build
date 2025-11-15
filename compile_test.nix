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
    rev = "d1376cb2b00dd4b25dc489f358da6339dd751958";
    hash = "sha256-fWdqVTBE+scYqg51+3eFWRDoF1OMMpg7Tp0+6yyn/Pk=";
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
runCommand "config" { } ''"${jellyfin-tui}/bin/jellyfin-tui" print config > "$out"''
