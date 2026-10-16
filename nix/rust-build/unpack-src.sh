# shellcheck shell=bash disable=SC2154
rustInstallSrcHashHook() {
	echo "Executing rustInstallSrcHashHook"
	runHook preInstall
	rust-build-helper install-src-hash "$src" . "$out"
	runHook postInstall
	echo "Finished rustInstallSrcHashHook"
}

if [ -z "${dontRustunpackSrcBuild:-}" ] && [ -z "${installPhase:-}" ]; then
	installPhase=rustInstallSrcHashHook
fi
