use color_eyre::{Result, eyre::eyre};
use serde::Serialize;
use sha2::Digest;
use std::{
    collections::BTreeMap,
    fs::{self, create_dir},
    path::{Path, PathBuf},
};

fn hash(file: &[u8]) -> String {
    hex::encode(sha2::Sha256::digest(file))
}

#[derive(Serialize)]
struct Checksums {
    package: String,
    files: BTreeMap<String, String>,
}

pub fn install_src_hash(archive: &Path, src: &Path, mut out: PathBuf) -> Result<()> {
    let package = hash(&fs::read(archive)?);
    let mut files = BTreeMap::new();
    create_dir(&out)?;
    iter_files(src, "", &out, &mut files)?;
    out.push(".cargo-checksum.json");
    fs::write(&out, serde_json::to_vec(&Checksums { package, files })?)?;
    Ok(())
}

pub fn iter_files(
    dir: &Path,
    dir_name: &str,
    out_dir: &Path,
    collect: &mut BTreeMap<String, String>,
) -> Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let mut name = dir_name.to_owned();
        name.push_str(
            &entry
                .file_name()
                .into_string()
                .map_err(|v| eyre!("file name is not utf-8: {}", v.display()))?,
        );
        let mut out = out_dir.to_owned();
        out.push(entry.file_name());
        if file_type.is_file() {
            let path = entry.path();
            let content = fs::read(path)?;
            collect.insert(name, hash(&content));
            fs::write(out, content)?;
        } else if file_type.is_dir() {
            name.push('/');
            fs::create_dir(&out)?;
            iter_files(&entry.path(), &name, &out, collect)?;
        }
    }
    Ok(())
}
