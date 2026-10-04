# shellcheck shell=bash disable=SC2154
rustRunBuildScriptHook() {
	echo "Executing rustRunBuildScriptHook"
	runHook preBuild
	echo "buildScript: $buildScript"
	echo "src: $src"
	echo "out: $out"
	echo "path: $PATH"
	nu @run_build_script@ "${buildScript}/bin/build_script"
	runHook postBuild
	echo "Finished rustRunBuildScriptHook"
}

if [ -z "${dontRustRunBuildScript:-}" ] && [ -z "${buildPhase:-}" ]; then
	buildPhase=rustRunBuildScriptHook
fi
