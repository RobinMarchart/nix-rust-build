# shellcheck shell=bash disable=SC2154
rustInstallSrcHashHook() {
    echo "Executing rustInstallSrcHashHook"
    runHook preInstall
    nu @install_src_hash@ "$src" "$out"
    runHook postInstall
    echo "Finished rustInstallSrcHashHook"
}

if [ -z "${dontRustunpackSrcBuild:-}" ] && [ -z "${installPhase:-}" ]; then
    installPhase=rustInstallSrcHashHook
fi
