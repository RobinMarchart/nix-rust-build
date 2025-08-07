# shellcheck shell=bash disable=SC2154
rustCargoMetadataBuildHook() {
    echo "Executing rustCargoMetadataBuildHook"
    runHook preBuild
    nix-rust-build metadata "${src}" "${vendorDir}" "$target" "$out"
    runHook postBuild
    echo "Finished rustCargoMetadataBuildHook"
}

if [ -z "${dontRustCargoMetadataBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustCargoMetadataBuildHook
fi
