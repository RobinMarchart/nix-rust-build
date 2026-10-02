{
  pkg-config,
  mpv-unwrapped,
  rustPlatform,
  sqlite,
  chafa,
  glib,
  aws-lc,
  rust-build,
  fetchFromGitHub,
  versionCheckHook,
  installShellFiles,
}:
let
  src = fetchFromGitHub {
    owner = "owo-uwu-nyaa";
    repo = "jellyfin-tui-rs";
    rev = "d80c41be578a2e6ebbf32a25757a92df56a693a2";
    hash = "sha256-lOy6V8kDZ36rEBb50JohzUlC62N1Get0gOXq/EOo9Pg=";
  };
  jellyhaj =
    (rust-build.withCrateOverrides {
      mpv-sys = {
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
      aws-lc-sys = {
        buildInputs = [
          aws-lc.dev
        ];
        nativeBuildInputs = [ pkg-config ];
      };
      ratatui-image = {
        buildInputs = [
          chafa
          glib
        ];
        nativeBuildInputs = [ pkg-config ];
      };
      jellyhaj-bin = {
        nativeBuildInputs = [ installShellFiles ];
        postInstall = ''
          echo installing desktop file
          install -Dm644 $src/jellyhaj.desktop $out/share/applications/jellyhaj.desktop       
          echo Generating jellyhaj completions
          mkdir completion
          ${jellyhaj.workspaceMembers.xtask}/bin/xtask print-completions completion bash zsh fish nushell
          installShellCompletion completion/*
          echo Finished generating jellyhaj completions
        '';
        nativeInstallCheckInputs = [ versionCheckHook ];
        versionCheckProgramArg = "--version";
        doInstallCheck = true;
      };
    }).build
      {
        inherit src;
        pname = "jellyfin-tui";
        version = "0.2.1";
      };
in
jellyhaj
