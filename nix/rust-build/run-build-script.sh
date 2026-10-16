# shellcheck shell=bash disable=SC2154
rustRunBuildScriptHook() {
	echo "Executing rustRunBuildScriptHook"
	runHook preBuild
	echo "buildScript: $buildScript"
	echo "src: $src"
	echo "out: $out"
	echo "path: $PATH"
	rust-build-helper run-build-script "$(pwd)" "$out" "$NIX_ATTRS_JSON_FILE" "${buildScript}/bin/build_script"
	runHook postBuild
	echo "Finished rustRunBuildScriptHook"
}

if [ -z "${dontRustRunBuildScript:-}" ] && [ -z "${buildPhase:-}" ]; then
	buildPhase=rustRunBuildScriptHook
fi
