def iter_files [dir out] {
  ls -a $dir | each {|file|
    if "file" == $file.type {
      cp -v $file.name ($out | path join $file.name)
      [$file.name] 
    } else if "dir" == $file.type {
      mkdir -v ($out | path join $file.name)
      iter_files $file.name $out
    }
  } | flatten
}

def with_hashes [] {
  each {|path|
    let hash = open -r $path | hash sha256
    {file: $path, hash: $hash}
  }
}

def main [src out] {
  mkdir -v $out
  let files = iter_files . $out | sort | with_hashes | transpose -ird
  let package = open -r $src | hash sha256
  print "writing .cargo-checksum.json"
  {package: $package, files: $files} | to json | save ($out | path join ".cargo-checksum.json")
}

