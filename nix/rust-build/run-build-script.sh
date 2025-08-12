# shellcheck shell=bash disable=SC2154
rustRunBuildScriptHook() {
    echo "Executing rustRunBuildScriptHook"
    runHook preBuild
    cargo="$(command -v cargo)"
    rustc="$(command -v rustc)"
    rustdoc="$(command -v rustdoc)"
    echo "buildScript: $buildScript"
    echo "cargo: $cargo"
    echo "rustc: $rustc"
    echo "rustdoc: $rustdoc"
    echo "src: $src"
    echo "jobPath: $rustRunBuildScriptJobPath"
    echo "out: $out"
    nix-rust-build run-build-script "${buildScript}/bin/build_script" "$cargo" "$rustc" "$rustdoc" "$src" "$rustRunBuildScriptJobPath" "$out"
    runHook postBuild
    echo "Finished rustRunBuildScriptHook"
}

if [ -z "${dontRustRunBuildScript:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustRunBuildScriptHook
fi
