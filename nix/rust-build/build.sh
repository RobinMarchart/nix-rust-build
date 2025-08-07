# shellcheck shell=bash disable=SC2154
rustBuildCrateHook() {
    echo "Executing rustBuildCrateHook"
    runHook preBuild
    if [ "$crateType" == "bin" ]; then
        echo "compiling bin crate"
        nix-rust-build compile-bin "$src" "$rustBuildCrateJobPath" "$out"
    elif [ "$crateType" == "lib" ]; then
        echo "compiling lib crate"
        nix-rust-build compile-lib "$src" "$rustBuildCrateJobPath" "$out"
    elif [ "$crateType" == "proc_macro" ]; then
        echo "compiling proc_macro crate"
        nix-rust-build compile-proc-macro "$src" "$rustBuildCrateJobPath" "$out"
    else
        echo "unknown crate type $crateType"
        exit 1
    fi
    runHook postBuild
    echo "Finished rustBuildCrateHook"
}

if [ -z "${dontRustBuildCrate:-}" ] && [ -z "${buildPhase:-}" ]; then
    buildPhase=rustBuildCrateHook
fi
