use ./version.nu

def add_package_by_name [by_name, package] {
  let checksum = $package.checksum?
  let source = $package.source?
  if ($checksum != null) and ($source != null) {
    let $name = $package.name
    let new_by_name = $by_name | default [] $name
    let val = $new_by_name | get $name
    let version = $package.version
    if $version in ($val | get version) {
      error make {msg: $"version ($version) of package ($name) appears more than once"}
    }
    let parsed_version = $version | version | transpose -i v| get v
    let modified = $val | append {version: $version , package: $package, parsed_version: $parsed_version}
    $new_by_name | update $name $modified
  } else {
    $by_name
  }
}

def collect_packages_by_name [] {
  reduce --fold {} {|p, acc| add_package_by_name $acc $p}
}

def mk_vendor [package, dir_name] {
    let registry = $package.source | parse -r r#'^registry\+(.*)$'# | get capture0 | first
    let checksum = $"sha256-($package.checksum | decode hex | encode base64)"
    {name: $package.name, version: $package.version, registry: $registry, checksum: $checksum, dir_name: $dir_name}
}

def vendor_versions [package_name: string] {
  let versions = $in| sort-by parsed_version
  let first_p = $versions.0.package
  let first_name = $"($first_p.name)-($first_p.version)"
  let first = [{dir:$first_name, val: (mk_vendor $first_p $package_name)}]
  let next = $versions | skip 1 | get package | each {
    |p|
    let name = $"($p.name)-($p.version)"
    {dir: $name, val: (mk_vendor $p $name)}
  }
  $first ++ $next
}

def main [lock_file out] {
  let file = open $lock_file -r |from toml
  if $file.version != 4 {
    error make {msg: $"unknown lock file version ($file.version)"}
  }
  let packages = $file.package | collect_packages_by_name | transpose name versions
  let vendor = $packages | sort-by name | each {|p| $p.versions | vendor_versions $p.name } | flatten | transpose -ird
  $vendor | to json |save -r $out
}
