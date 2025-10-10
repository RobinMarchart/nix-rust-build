# shellcheck shell=bash disable=SC2154
rustPrepareLockfileBuildHook() {
    echo "Executing rustPrepareLockfileBuildHook"
    runHook preBuild
    nu @prepare_lockfile@ "${src}/${lockFilePath}" "$out"
    runHook postBuild
    echo "Finished rustPrepareLockfileBuildHook"
}

if [ -z "${dontRustPrepareLockfileBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustPrepareLockfileBuildHook
fi
