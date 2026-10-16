# shellcheck shell=bash disable=SC2154
rustVendorBuildHook() {
	echo "Executing rustVendorBuildHook"
	runHook preBuild
	rust-build-helper write-vendor "$out" "$NIX_ATTRS_JSON_FILE"
	runHook postBuild
	echo "Finished rustVendorBuildHook"
}

if [ -z "${dontRustVendorBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
	buildPhase=rustVendorBuildHook
fi
