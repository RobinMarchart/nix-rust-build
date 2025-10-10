# shellcheck shell=bash disable=SC2154
rustBuildCrateHook() {
    echo "Executing rustBuildCrateHook"
    runHook preBuild
    echo "job:"
    cat "$rustBuildCrateJobPath"
    echo "src: $src"
    echo "out: $out"
    nu @run_build@ "$rustBuildCrateJobPath" "$src" "$out"
    runHook postBuild
    echo "Finished rustBuildCrateHook"
}

if [ -z "${dontRustBuildCrate:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustBuildCrateHook
fi
