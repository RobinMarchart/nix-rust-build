use ./run_common.nu
use ./version.nu

def merge_job [n] {
  merge deep -s append $n
}

def with_build_script [job] {
  if $job.buildScriptRun? != null {
    let run = open ($job.buildScriptRun | path join result.toml)
    let run_envs = $run | get -o envs | default {}
    print ($run_envs | to text) 
    {
      metadata: $run.metadata
      libPath: $run.libPath
      linkLib: $run.linkLib
      rustcFlags: $run.flags
      cfgs: $run.cfgs
      linkArgs: ($run.linkArgs ++ (
        match $job.crateType {
          "cdylib" => $run.linkArgsCdylib
          "bin" => { $run.linkArgsBins ++ ($run.linkArgsBin | get -o $job.pname | default [])}
          _ => { [] }
        }
      ))
      checkCfgs: $run.checkCfgs
      envs: ($run.envs | merge {OUT_DIR: ($job.buildScriptRun | path join output)} | merge $run_envs)
    } | run_common prepared_env
  } else {
    {
      metadata: {}
      libPath: []
      linkLib: []
      rustcFlags: []
      cfgs: []
      linkArgs: []
      checkCfgs: []
      envs: {}
    }
  }
}


def add_dep [dep job] {
  let meta = open ($dep.path | path join "rust-lib.toml")
  {
    rustcFlags: [--extern $"($dep.name)=($meta.lib)"]
    libPath: $meta.libPath
    allDeps: ([$dep.path] ++ $meta.deps)
  }
}

def with_deps [job] {
  $job.deps | each {|dep| add_dep $dep $job} | reduce -f {} {|new, acc| $acc | merge deep -s append $new}
}

def bin [job out] {
  let bin = $out | path join bin
  mkdir -v $bin
  {
    pwd: $bin
    rustcFlags: [-o $job.targetName --crate-type bin]
    envs: {CARGO_BIN_NAME: $job.targetName}
  }
}

def test [job out] {
  let bin = $out | path join bin
  mkdir -v $bin
  {
    pwd: $bin
    rustcFlags: [-o test --test]
  }
}

def lib [job out] {
  let name_hash = ([$job.pname $job.version] ++ $job.features) | str join ":🦀:" | hash sha256 | str substring 0..8
  let lib_path = $out | path join $"lib($job.crateName)-($name_hash).rlib"
  let metadata_path = $out | path join rust-lib.toml
  if ($job.metadata | is-not-empty) and ($job.links? == null) {
    error make {msg: "metadata without links", help: "add links= attribute to Cargo.toml (see cargo docs)"}
  }
  mkdir -v $out
  {
    lib: $lib_path
    deps: ($job.allDeps? | default [])
    metadata: ($job.metadata | default {})
    libPath: ($job.libPath | default [])
    links: $job.links
  } | to toml | save $metadata_path
  {
    pwd: $out
    rustcFlags: [-C $"metadata=($name_hash)" -C $"extra-filename=-($name_hash)" --out-dir $out --crate-type lib]
  }
}

def proc_macro [job out] {
  let name_hash = ([$job.pname $job.version] ++ $job.features) | str join ":🦀:" | hash sha256 | str substring 0..8
  let lib_path = $out | path join $"lib($job.crateName)-($name_hash).so"
  let metadata_path = $out | path join rust-lib.toml
  mkdir -v $out
  {lib: $lib_path, deps: [], metadata: {}, libPath: [], links: null} | to toml | save $metadata_path

  {
    pwd: $out
    rustcFlags: [-C $"metadata=($name_hash)" -C $"extra-filename=-($name_hash)" --out-dir $out --extern proc_macro --crate-type proc-macro]
  }
}

def cdylib [job out] {
  let lib = $out | path join lib
  let version = $job.version | version
  let lib_path = $lib | path join $"lib($job.targetName).so"
  let lib_major_path = $lib | path join $"lib($job.targetName).so.($version.major)"
  let lib_full_path = $lib | path join $"lib($job.targetName).so.($version.major).($version.minor).($version.patch)"
  mkdir -v $lib
  ln -sT $lib_full_path $lib_path
  ln -sT $lib_full_path $lib_major_path
  {
    pwd: $lib
    rustcFlags: [-o $lib_full_path --crate-type cdylib]
  }
}

def target_specific [out] {
  $in | merge_job (match $in.crateType {
    "bin" => (bin $in $out)
    "lib" => (lib $in $out)
    "proc-macro" => (proc_macro $in $out)
    "cdylib" => (cdylib $in $out)
    "test" => (test $in $out)
  })
}

def compile [src] {
  let job = $in
  let cores = if "1" == $env.enableParallelBuilding? {
    $env.NIX_BUILD_CORES | into int
  } else 1
  let args = (
    [
      --crate-name $job.crateName
      $"--edition=($job.edition)"
      ($src| path join $job.entrypoint)
      --check-cfg "cfg(docsrs,test)"
      -C embed-bitcode=no
      --cap-lints allow
      --target $job.target
      --emit link
      -C $"codegen-units=($cores)"
    ]
    ++ $job.rustcFlags
    ++ ($job.cfgs | uniq | each {|cfg|[--cfg $cfg]} | flatten)
    ++ ($job.checkCfgs | uniq | each {|cfg|[--check-cfg $cfg]} | flatten)
    ++ (if ([bin cdylib proc-macro] | any {|t| $t == $job.crateType }) {
      $job.linkArgs | each {|a|[-C $"link-arg=($a)"]} | flatten
    } else [])
    ++ ($job.libPath | uniq | each {|l|[-L $l]} | flatten)
    ++ ($job.linkLib | uniq | each {|l|[-l $l]} | flatten)
    ++ ($job.allDeps | uniq | each {|d|[-L $"dependency=($d)"]} | flatten)
    ++ ($job.features | each {|f|[--cfg $'feature="($f)"']} | flatten)
    ++ [--check-cfg $"cfg\(feature, values\(($job.allFeatures | each {|f|$'"($f)"'} | str join ', ')\)\)"]
    ++ (if $job.debuginfo {[-C debuginfo=2]} else {[-C strip=debuginfo]})
    ++ (if $job.optimize {[-C opt-level=3]} else [])
  )
  cd $job.pwd
  load-env ($job.envs | run_common unfold_env)
  print $"running rustc ($args | str join ' ')"
  exec rustc ...$args
}

def main [job src out] {
  let job = open -r $job | from json
  run_common env_from_context
    | merge_job (with_build_script $job)
    | merge_job ({envs: (run_common common_env $job $src)})
    | merge_job (with_deps $job)
    | merge_job ($job)
    | merge_job {allDeps:[]}
    | target_specific $out
    | compile $src
}


 

