{
  lib,
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
  writeShellScript,
  breakpointHook,
}:
let
  src = fetchFromGitHub {
    owner = "owo-uwu-nyaa";
    repo = "jellyfin-tui-rs";
    rev = "d80c41be578a2e6ebbf32a25757a92df56a693a2";
    hash = "sha256-lOy6V8kDZ36rEBb50JohzUlC62N1Get0gOXq/EOo9Pg=";
  };
  mkFiltered =
    path:
    builtins.path {
      path = src;
      filter =
        let
          parents-gen =
            path:
            if path == "." then
              [ ]
            else
              let
                path' = dirOf path;
              in
              (parents-gen path') ++ [ "${src}/${path}" ];
          parents = parents-gen path;
          base = "${src}/${path}";
        in
        path: type: (builtins.any (p: p == path) parents) || (lib.hasPrefix base path);
    };
  sqlx-fake-cargo = writeShellScript "sqlx-fake-cargo" ''echo '{"workspace_root": "${mkFiltered ".sqlx"}"}' '';
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
      xtask = {
        postPatch = "ln -s ${mkFiltered "src/args.rs"}/src ..";
      };
      config = {
        postPatch = "ln -s ${mkFiltered "migrations"}/migrations ..";
        CARGO = sqlx-fake-cargo;
      };
      jellyhaj-event-listener = {
        CARGO = sqlx-fake-cargo;
      };
      jellyhaj-image = {
        CARGO = sqlx-fake-cargo;
      };
      jellyhaj-login-view = {
        CARGO = sqlx-fake-cargo;
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
