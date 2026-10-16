# shellcheck shell=bash disable=SC2154
rustCargoMetadataBuildHook() {
	echo "Executing rustCargoMetadataBuildHook"
	runHook preBuild
	rust-build-helper metadata "$out" "$NIX_ATTRS_JSON_FILE"
	runHook postBuild
	echo "Finished rustCargoMetadataBuildHook"
}

if [ -z "${dontRustCargoMetadataBuild:-}" ] && [ -z "${buildPhase:-}" ]; then
	buildPhase=rustCargoMetadataBuildHook
fi
