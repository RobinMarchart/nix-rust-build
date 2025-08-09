# shellcheck shell=bash disable=SC2154
rustBuildCrateHook() {
    echo "Executing rustBuildCrateHook"
    runHook preBuild
    cargo="$(command -v cargo)"
    rustc="$(command -v rustc)"
    echo "src: $src"
    echo "cargo: $cargo"
    echo "rustc: $rustc"
    echo "jobPath: $rustBuildCrateJobPath"
    echo "out: $out"
    nix-rust-build compile "$src" "$cargo" "$rustc" "$rustBuildCrateJobPath" "$out"
    runHook postBuild
    echo "Finished rustBuildCrateHook"
}

if [ -z "${dontRustBuildCrate:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustBuildCrateHook
fi
