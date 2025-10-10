use ./version.nu

export def common_env [job src] {
  let manifestPath = $src | path join $job.manifestPath
  let manifestDir = $manifestPath | path dirname
  let version = $job.version | version
  {
    CARGO: (which cargo | get 0.path)
    CARGO_MANIFEST_DIR: $manifestDir
    CARGO_MANIFEST_PATH: $job.manifestPath
    CARGO_PKG_VERSION: $job.version
    CARGO_PKG_VERSION_MAJOR: ($version.major | default "")
    CARGO_PKG_VERSION_MINOR: ($version.minor | default "")
    CARGO_PKG_VERSION_PATCH: ($version.patch | default "")
    CARGO_PKG_VERSION_PRE: ($version.pre | default "")
    CARGO_PKG_AUTHORS: ($job.authors | str join " ")
    CARGO_PKG_NAME: $job.pname
    CARGO_PKG_DESCRIPTION: ($job.description | default "")
    CARGO_PKG_HOMEPAGE: ($job.homepage | default "")
    CARGO_PKG_REPOSITORY: ($job.repository | default "")
    CARGO_PKG_LICENSE: ($job.license | default "")
    CARGO_PKG_LICENSE_FILE: ($job.licenseFile | default "")
    CARGO_PKG_RUST_VERSION: ($job.rustVersion | default "")
    CARGO_PKG_README: ($job.readme | default "")
    CARGO_CRATE_NAME: $job.crateName
    PATH: [$manifestDir]
  }
}

export def split_env_path [] {
  default "" | split row : | where {|x| $x != "" }
}

export def prepared_env [] {
  $in | upsert envs (
    $in.envs?
    | default {}
    | merge {
      LD_LIBRARY_PATH: ($in.envs?.LD_LIBRARY_PATH? | split_env_path)
      PATH: ($in.envs?.PATH? | split_env_path)
    }
  )
}

export def env_from_context [] {
  {envs: {
    LD_LIBRARY_PATH: ($env.LD_LIBRARY_PATH? | split_env_path)
    PATH: $env.PATH
  }}
}

export def unfold_env [] {
  $in | merge {
    LD_LIBRARY_PATH: ($in.LD_LIBRARY_PATH? | uniq | default [] | str join :)
  }
}

export def to_record [] {
  let l = $in
  if ($l | is-empty) {
    {}
  } else {
    $l | transpose -rd
  }
}

