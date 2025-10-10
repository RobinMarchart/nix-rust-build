use ./run_common.nu
use ./version.nu
use std log

def parse_command [] {
  let line = $in
  let res = $line | parse -r r#'^\s*cargo(?<cargo>::?)(?<cmd>[a-z\-_]+)=(?<full>(?:(?<name>[^=\s]+)=)?(?<val>.+))$'#
  if $res == [] {
    print $line
  } else {
    let res = $res.0
    match $res.cmd {
      rerun-if-changed => {}
      rerun-if-env-changed => {}
      rustc-link-arg => {
        let full = $res.full | str trim
        log info $'added link arg: "($full)"'
        {linkArgs: [$full]}
      }
      rustc-link-arg-cdylib => {
        let full = $res.full | str trim
        log info $'added cdylib link arg: "($full)"'
        {linkArgsCdylib: [$full]}
      }
      rustc-link-arg-bins => {
        let full = $res.full | str trim
        log info $'added bins link arg: "($full)"'
        {linkArgsBins: [$full]}
      }
      rustc-link-arg-tests => {}
      rustc-link-arg-examples => {}
      rustc-link-arg-benches => {}
      rustc-link-arg-bin => {
        if $res.name == null {
          error make {msg: "rustc-link-arg-bin cargo command has invalid arguments"}
        }
        let name = $res.name | str trim
        let val = $res.val | str trim
        log info $'added link arg for bin ($name): "($val)"'
        {linkArgsBin: ({} | insert $name [$val])}
      }
      rustc-link-lib => {
        let full = $res.full | str trim
        log info $'link to ($full)'
        {linkLib: [$full]}
      }
      rustc-link-search => {
        let full = $res.full | str trim
        log info $'added link path: ($full)'
        {libPath: [$full]}
      }
      rustc-flags => {
        let full = $res.full | str trim
        log info $'added rustc flag: "($full)"'
        {flags: [$full]}
      }
      rustc-cfg => {
        let full = $res.full | str trim
        log info $'added cfg: ($full)'
        {cfgs: [$full]}
      }
      rustc-check-cfg => {
        let full = $res.full | str trim
        log info $'added check-cfg: ($full)'
        {checkCfgs: [$full]}
      }
      rustc-env => {
        if $res.name == null {
          error make {msg: "rustc-env cargo command has invalid arguments"}
        }
        let name = $res.name | str trim
        let val = $res.val | str trim
        log info $'added env: ($name)=\"($val)\"'
        {envs: ({} | insert $name [$val])}
      }
      metadata => {
        if $res.cargo == "::" {
          if $res.name == null {
            error make {msg: "rustc-env cargo command has invalid arguments"}
          }
          let name = $res.name | str trim
          let val = $res.val | str trim
          log info $'added metadata "($name)" = "($val)"'
          {metadata: ({} | insert $name $val)}
        } else {
          let full = $res.full | str trim
          log info $'added metadata "metadata" = "($full)"'
          {metadata: {metadata: $full}}
        }
      }
      warning => {
        log warning $res.full
      }
      error => {
        log error $res.full
        {error: true}
      }
      _ => {
        if $res.cargo == ":" {
          let name = $res.cmd | str trim
          let val = $res.full | str trim
          log info $'added metadata "($name)" = "($val)"'
          {metadata: ({} | insert $name $val)}
        } else {
          print $line
        }
      }
    }
  }
}

def main [script job src out] {
  let job = open -r $job | from json
  let out_dir = $out | path join output
  mkdir -v $out_dir
  let cores = if "1" == $env.enableParallelBuilding? {
    $env.NIX_BUILD_CORES | into int
  } else 1
  load-env (run_common common_env $job $src | merge deep -s append {PATH: $env.PATH})
  $env.CARGO_MAKEFLAGS = $"-j ($cores)"
  $env.OUT_DIR = $out_dir
  $env.TARGET = $job.target
  $env.HOST = run-external rustc "--print=host-tuple" | str trim
  $env.NUM_JOBS = $cores
  $env.RUSTC = which rustc | get 0.path
  $env.RUSTDOC = which rustdoc | get 0.path
  $env.CARGO_ENCODED_RUSTFLAGS = $job.rustcFlags | str join "\u{1f}"
  if $job.links != null {
    $env.CARGO_MANIFEST_LINKS = $job.links
  }
  if $job.optimize {
    $env.OPT_LEVEL = "3"
    $env.PROFILE = "release"
  } else {
    $env.OPT_LEVEL = "1"
    $env.PROFILE = "debug"
  }
  if $job.debuginfo {
    $env.DEBUG = "true"
  } else {
    $env.DEBUG = "false"
  }
  let features = $job.features | str replace "-" "_"
  load-env (
    run-external rustc "-O" "--print=cfg"
    | split row "\n"
    | each { parse -r r#'^(?<name>[^=\n]*)(?:="(?<val>[^"\n]*)")?$'# }
    | flatten
    | group-by name
    | transpose name val
    | each {|v| $v | update val ($v.val.val | str join "," )}
    | append {name: feature val: ($features | str join ",") }
    | each {|v|$v | update name $"CARGO_CFG_($v.name | str upcase)"}
    | run_common to_record 
  )
  load-env ($job.features | each {|f| {name: $"CARGO_FEATURE_($f |  | str upcase)", val: "1"}} | run_common to_record)
  load-env (
    $job.deps.path
    | each {|p| open ($p | path join rust-lib.toml)}
    | each {|p|
      $p.metadata
      | transpose name val
      | each {|meta| {name: $"DEP_($p.links | str upcase)_($meta.name | str upcase)", val: $meta.val}}
    }
    | flatten
    | run_common to_record
  )
  cd ($src | path join $job.manifestPath | path dirname)
  let seed = {
    metadata: {}
    linkArgs: []
    linkArgsCdylib: []
    linkArgsBins: []
    linkArgsBin: {}
    linkLib: []
    libPath: []
    flags: []
    cfgs: []
    checkCfgs: []
    envs: {}
  }
  let output = (
    run-external $script
    | split row "\n"
    | each {parse_command}
    | reduce -f $seed {|i,acc|$acc | merge deep -s append $i}
  )
  if $output.error? == true {
    exit 1
  } else {
    $output | to toml | save ($out | path join result.toml)
  }
  
}


