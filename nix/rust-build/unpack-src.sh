# shellcheck shell=bash disable=SC2154
rustUnpackSrcBuildHook() {
    echo "Executing rustUnpackSrcBuildHook"
    runHook preBuild
    nix-rust-build unpack-vendor "$src" "$out"
    runHook postBuild
    echo "Finished rustUnpackSrcBuildHook"
}

if [ -z "${dontRustunpackSrcBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustUnpackSrcBuildHook
fi
