use color_eyre::Result;
use itertools::Itertools;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::symlink,
    path::{Path, PathBuf},
};

#[derive(Deserialize)]
struct Attrs {
    packages: Vec<Package>,
}

#[derive(Deserialize)]
struct Package {
    dir_name: String,
    path: PathBuf,
    registry: String,
}

#[derive(Serialize)]
#[serde(untagged)]
#[serde(rename_all_fields = "kebab-case")]
enum SourceVal<'s> {
    Dir {
        directory: &'s Path,
    },
    Crates {
        replace_with: &'static str,
    },
    Registry {
        registry: &'s str,
        replace_with: &'static str,
    },
}

#[derive(Serialize)]
struct Source<'s> {
    source: BTreeMap<&'s str, SourceVal<'s>>,
}

pub fn write_vendor(out: &Path, attrs: &Path) -> Result<()> {
    let attrs: Attrs = serde_json::from_slice(&fs::read(attrs)?)?;
    let packages = attrs.packages;
    fs::create_dir(out)?;
    let mut sources: BTreeMap<_, _> = packages
        .iter()
        .map(|p| p.registry.as_str())
        .unique()
        .map(|registry| {
            if registry == "https://github.com/rust-lang/crates.io-index" {
                (
                    "crates-io",
                    SourceVal::Crates {
                        replace_with: "vendored-sources",
                    },
                )
            } else {
                (
                    registry,
                    SourceVal::Registry {
                        registry,
                        replace_with: "vendored-sources",
                    },
                )
            }
        })
        .collect();
    sources.insert("vendored-sources", SourceVal::Dir { directory: out });
    let config = out.join("config.toml");
    fs::write(config, toml::to_string(&Source { source: sources })?)?;
    for package in packages {
        let dest = out.join(package.dir_name);
        symlink(package.path, dest)?;
    }
    Ok(())
}
