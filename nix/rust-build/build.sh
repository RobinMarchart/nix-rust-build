# shellcheck shell=bash disable=SC2154
rustBuildCrateHook() {
	echo "Executing rustBuildCrateHook"
	runHook preBuild
	echo "src: $src"
	echo "out: $out"
	rust-build-helper run-build "$(pwd)" "$out" "$NIX_ATTRS_JSON_FILE"
	runHook postBuild
	echo "Finished rustBuildCrateHook"
}

if [ -z "${dontRustBuildCrate:-}" ] && [ -z "${buildPhase:-}" ]; then
	buildPhase=rustBuildCrateHook
fi
