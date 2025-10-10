
def to_registry [reg] {
  if $reg == "https://github.com/rust-lang/crates.io-index" {
    {name: "crates-io", val: {replace-with: "vendored-sources"}}
  } else {
    {name: $reg, val: {registry: $reg, replace-with: "vendored-sources"}}
  }
}

def vendor_config [out] {
  let config = [{name: "vendored-sources", val: {directory: $out}}] ++ (
    $in | get registry | uniq | each {|r| to_registry $r}
  )
  {source: ($config | transpose -ird) } | to toml
}

def main [packages_file out] {
  let packages = open -r $packages_file | from json | transpose n p | get p
  mkdir -v $out
  $packages | vendor_config $out | save ($out | path join "config.toml")
  for dep in $packages {
    print $"linking ($dep.path)"
    ln -sT $dep.path ($out | path join $dep.dir_name)
  }
}
