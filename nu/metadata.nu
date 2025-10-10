use std assert

let vendor_dir = $env.vendorDir?
let project_dir = $env.src? | default . | path expand
let platform = $env.target? |default "x86_64-unknown-linux-gnu"

def get_metadata [] {
  print $"target: ($platform)"
  let no_default_features = $env.no_default_features? == "1" 
  print $"with default features: (not $no_default_features)"
  let features = $env.features? | default "" | split row " "
  print $"features: ($features)"
  let config = if $vendor_dir != null { $vendor_dir | path join config.toml }
  print $"cargo config: ($config)"
  cd $project_dir
  print "running cargo metadata"
  let args = (
    [--format-version 1 --frozen --filter-platform $platform]
    ++ (if $config == null { [] } else [--config $config])
    ++ (if $no_default_features {[--no-default-features]} else [])
    ++ ($features | each {|f| [-F $f]} | flatten)
  )
  run-external cargo metadata ...$args | from json
}

let metadata = get_metadata

print "processing metadata"

def mk_pkg_id [] {
  if $project_dir in $in {
    $in | str replace $project_dir source
  } else { $in }
}

let pkg_map = $metadata.packages | each {|p|{id:($p.id | mk_pkg_id), p:$p}} | transpose -rd

let workspace_members = $metadata.workspace_members | each {|i|
    let id = $i | mk_pkg_id
    {name: ($pkg_map | get $id | get name), id: $id}
  } | transpose -rd

let root = $metadata.resolve.root | mk_pkg_id

def any_eq [a] {
  any {|b|$a == $b}
}

def collect_deps [kind] {
  each {|d| if ($d.dep_kinds | get kind | any_eq $kind) {{name: $d.name, pkg: ($d.pkg | mk_pkg_id)}}}
}

def make_relative [] {
  if $project_dir in $in {
    $in | path relative-to $project_dir
  } else if ($vendor_dir != null) and ($vendor_dir in $in) {
    let p = $in | path relative-to $vendor_dir
    #remove package prefix
    let prefix = $p | path split | get 0
    $p | path relative-to $prefix
  } else $in
}

def readFile [file] {
  if ($file | path exists) {
    open $file
  } 
}

def common [package node id] {
  {
    manifestPath: ($package.manifest_path | make_relative)
    version: $package.version
    pname: $package.name
    description: $package.description
    readme: $package.readme
    authors: $package.authors
    longDescription: (if $package.readme != null { readFile ($package.manifest_path | path dirname | path join $package.readme) })
    homepage: $package.homepage
    repository: $package.repository
    license: $package.license
    licenseFile: $package.license_file
    rustVersion: $package.rust_version
    target: $platform
    features: $node.features
    allFeatures: ($package.features | transpose n | get n)
    mainWorkspace: ($package.source == null)
    links: $package.links
    crateName: ($package.name | str replace -a "-" "_")
  }
}

def resolved [node] {
  let id = $node.id | mk_pkg_id
  let deps = $node.deps | collect_deps null
  let deps_build = $node.deps | collect_deps build
  let package = $pkg_map | get $id
  mut res = {common: (common $package $node $id)}
  for target in $package.targets {
    for kind in $target.kind {
      if $kind == custom-build {
        assert ($target.crate_types | any_eq bin)
        $res = $res | insert buildScript {
          mainDeps: $deps
          deps: $deps_build
          crateType: "bin"
          targetName: "build_script"
          entrypoint: ($target.src_path | make_relative)
          edition: $target.edition
        }
      } else if $kind == lib {
        assert ($target.crate_types | any_eq lib)
        $res = $res | insert rustLib {
          deps: $deps
          crateType: "lib"
          targetName: $target.name
          entrypoint: ($target.src_path | make_relative)
          edition: $target.edition
        }
      } else if $kind == proc-macro {
        assert ($target.crate_types | any_eq proc-macro)
        $res = $res | insert rustLib {
          deps: $deps
          crateType: "proc-macro"
          targetName: $target.name
          entrypoint: ($target.src_path | make_relative)
          edition: $target.edition
        }
      } else if $kind == bin {
        assert ($target.crate_types | any_eq bin)
        $res = $res | upsert bins ($res.bins? | default [] | append {
          deps: $deps
          crateType: "bin"
          targetName: $target.name
          entrypoint: ($target.src_path | make_relative)
          edition: $target.edition
        })
      }
    }
  }
  if ($res.rustLib? != null) and ($res.bins? != null) {
    let name = $res.common.crateName
    $res = $res | update bins ($res.bins | each {|bin|
      $bin | update deps ($bin.deps | append {
        name: $name
        pkg: $id
      })
    })
  }
  {id: $id, v:$res}
}

let packages = $metadata.resolve.nodes | each {|v|resolved $v} | transpose -rd

{
  packages: $packages
  workspace: $workspace_members,
  mainPackage: $root
} | to json | save $env.out

