#!/nix/store/10dxp0qxqxxsyiljrh2kp0xqhz6arhcx-bash-5.3p15/bin/bash
# shellcheck shell=bash disable=SC2154

fixupBuildScriptOutputHook() {
	echo "Executing fixupBuildScriptOutputHook"
	echo "replacing $(pwd) with $src in $out"
	replace-output "$out" "$(pwd)" "$src"
	echo "Finished fixupBuildScriptOutputHook"
}

if [ -z "${dontFixupBuildScriptOutput:-}" ]; then
	preFixupHooks+=(fixupBuildScriptOutputHook)
fi
