use std::{
    borrow::Cow,
    collections::{BTreeMap, HashMap},
    fs,
    path::Path,
    sync::LazyLock,
};

use base64::Engine;
use color_eyre::eyre::{Context, OptionExt, Result};
use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
struct Lockfile {
    package: Vec<Package>,
}

#[derive(Debug, Deserialize)]
struct Package {
    name: String,
    version: String,
    source: Option<String>,
    checksum: Option<String>,
}

#[derive(Debug, Serialize)]
struct Vendor<'s> {
    name: &'s str,
    version: &'s str,
    registry: &'s str,
    checksum: String,
    dir_name: Cow<'s, str>,
}

static REGISTRY_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^registry\+(.*)$").unwrap());

impl<'s> Vendor<'s> {
    fn from_package(p: &'s Package, dir_name: Cow<'s, str>) -> Result<Self> {
        let mut checksum = "sha256-".to_string();
        base64::engine::general_purpose::STANDARD.encode_string(
            hex::decode(p.checksum.as_ref().ok_or_eyre("already filtered")?)
                .context("decoding schecksum")?,
            &mut checksum,
        );
        let registry = REGISTRY_REGEX
            .captures(p.source.as_deref().ok_or_eyre("already filtered")?)
            .ok_or_eyre("registry regex didn't match")?
            .get(1)
            .ok_or_eyre("regex did not match")?
            .as_str();
        Ok(Self {
            name: &p.name,
            version: &p.version,
            registry,
            checksum,
            dir_name,
        })
    }
}

pub fn run(lock_file: &Path, out: &Path) -> Result<()> {
    let lock = fs::read_to_string(lock_file)?;
    let lockfile: Lockfile = toml::from_str(&lock)?;
    let mut by_name: HashMap<&'_ str, BTreeMap<&'_ str, &'_ Package>> = HashMap::new();

    for package in &lockfile.package {
        if package.source.is_some() && package.checksum.is_some() {
            match by_name.entry(&package.name) {
                std::collections::hash_map::Entry::Vacant(e) => {
                    let mut map = BTreeMap::new();
                    map.insert(package.version.as_str(), package);
                    e.insert(map);
                }
                std::collections::hash_map::Entry::Occupied(mut e) => {
                    e.get_mut().insert(&package.version, package);
                }
            }
        }
    }
    let mut packages: HashMap<String, Vendor<'_>> = HashMap::new();
    for package in by_name.into_values() {
        let mut iter = package.into_values().rev();
        let package = iter.next().ok_or_eyre("always at least one entry")?;
        let vendor = Vendor::from_package(package, Cow::Borrowed(&package.name))?;
        packages.insert(format!("{}-{}", package.name, package.version), vendor);
        for package in iter {
            let name = format!("{}-{}", package.name, package.version);
            let vendor = Vendor::from_package(package, Cow::Owned(name.clone()))?;
            packages.insert(name, vendor);
        }
    }
    fs::write(out, serde_json::to_string(&packages)?)?;
    Ok(())
}
