use std::{
    collections::{
        BTreeMap, HashMap,
        hash_map::Entry::{Occupied, Vacant},
    },
    fs::{read, write},
    path::Path,
    sync::LazyLock,
};

use base64::Engine;
use color_eyre::{
    Result,
    eyre::{OptionExt, bail},
};
use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct LockFile {
    version: u8,
    package: Vec<PackageDef>,
}

#[derive(Deserialize)]
struct PackageDef {
    name: String,
    version: String,
    #[serde(default)]
    source: String,
    #[serde(default)]
    checksum: String,
}

#[derive(Serialize)]
struct VendorDef {
    name: String,
    version: String,
    registry: String,
    checksum: String,
    dir_name: String,
}

static REGISTRY_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^registry\+(.*)$").expect("parsing regex failed"));

fn registry_from_src(src: &str) -> Result<String> {
    let (_, [registry]) = REGISTRY_PATTERN
        .captures(src)
        .ok_or_eyre("failed to extract registry from source")?
        .extract();
    Ok(registry.to_owned())
}

fn reencode_checksum(hex: &str) -> Result<String> {
    let mut out = "sha256-".to_owned();
    base64::engine::general_purpose::STANDARD.encode_string(hex::decode(hex)?, &mut out);
    Ok(out)
}

pub fn prepare_lockfile(lockfile: &Path, out: &Path) -> Result<()> {
    let lockfile: LockFile = toml::from_slice(&read(lockfile)?)?;
    if lockfile.version != 4 {
        bail!("unknown lock file version {}", lockfile.version)
    }
    let mut packages_sorted = HashMap::new();
    for package in lockfile
        .package
        .into_iter()
        .filter(|p| !(p.source.is_empty() || p.checksum.is_empty()))
    {
        let by_name = match packages_sorted.entry(package.name.clone()) {
            Occupied(occupied_entry) => occupied_entry.into_mut(),
            Vacant(vacant_entry) => vacant_entry.insert(BTreeMap::new()),
        };
        let version = crate::version::Version::from_str(&package.version)
            .ok_or_eyre("parsing version failed")?;
        match by_name.entry(version) {
            std::collections::btree_map::Entry::Vacant(vacant_entry) => {
                vacant_entry.insert(package)
            }
            std::collections::btree_map::Entry::Occupied(_) => {
                bail!(
                    "version {} of package {} appears more than once",
                    package.version,
                    package.name
                );
            }
        };
    }
    let mut packages = BTreeMap::new();
    for (name, packages_sorted) in packages_sorted {
        let mut packages_sorted = packages_sorted.into_values();
        let first = packages_sorted
            .next()
            .expect("should always have at least one entry");
        packages.insert(
            format!("{}-{}", first.name, first.version),
            VendorDef {
                name: first.name,
                version: first.version,
                registry: registry_from_src(&first.source)?,
                checksum: reencode_checksum(&first.checksum)?,
                dir_name: name,
            },
        );
        for package in packages_sorted {
            let dir_name = format!("{}-{}", package.name, package.version);
            let package = VendorDef {
                name: package.name,
                version: package.version,
                registry: registry_from_src(&package.source)?,
                checksum: reencode_checksum(&package.checksum)?,
                dir_name: dir_name.clone(),
            };
            packages.insert(dir_name, package);
        }
    }
    write(out, serde_json::to_vec(&packages)?)?;
    Ok(())
}
