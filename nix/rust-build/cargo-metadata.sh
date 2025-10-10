# shellcheck shell=bash disable=SC2154
rustCargoMetadataBuildHook() {
    echo "Executing rustCargoMetadataBuildHook"
    runHook preBuild
    nu @metadata@
    runHook postBuild
    echo "Finished rustCargoMetadataBuildHook"
}

if [ -z "${dontRustCargoMetadataBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustCargoMetadataBuildHook
fi
