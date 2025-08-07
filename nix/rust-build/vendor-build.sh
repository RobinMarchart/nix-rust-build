# shellcheck shell=bash disable=SC2154
rustVendorBuildHook() {
    echo "Executing rustVendorBuildHook"
    runHook preBuild
    nix-rust-build write-vendor "$jobPath" "$out"
    runHook postBuild
    echo "Finished rustVendorBuildHook"
}

if [ -z "${dontRustVendorBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustVendorBuildHook
fi
