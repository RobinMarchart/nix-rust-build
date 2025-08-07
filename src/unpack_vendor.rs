use std::{
    collections::HashMap, fs,
    io::Read,
    path::{Component, PathBuf},
};

use color_eyre::{
    eyre::{bail, Context, OptionExt},
    Result,
};
use flate2::bufread::MultiGzDecoder;
use serde::Serialize;
use sha2::{Digest, Sha256};

use tar::Archive;

#[derive(Debug, Serialize)]
struct Hashes {
    package: String,
    files: HashMap<String, String>,
}

pub fn run(src: PathBuf, mut out: PathBuf) -> Result<()> {
    let src = fs::read(src).context("reading source archive")?;
    let package = hex::encode(Sha256::digest(&src).as_slice());
    let gz_decoder = MultiGzDecoder::new(src.as_slice());
    let mut tar_decoder = Archive::new(gz_decoder);
    let tar_entries = tar_decoder.entries().context("Start reading tarball")?;
    let mut files = HashMap::new();
    for entry in tar_entries {
        let mut entry = entry.context("Start reading tar entry")?;
        let mut path = out.clone();
        let mut first = true;
        for part in entry
            .path()
            .context("error reading entry path")?
            .components()
        {
            match part {
                Component::Prefix(_) | Component::RootDir | Component::CurDir => {}
                Component::ParentDir => {
                    bail!("parent dir in tarball is not allowed due to security concerns")
                }
                Component::Normal(part) => {
                    if first {
                        first = false;
                    } else {
                        path.push(part)
                    }
                }
            }
        }

        let mut data = vec![];
        entry.read_to_end(&mut data).context("reading entry path")?;
        let hash = Sha256::digest(&data);
        fs::create_dir_all(path.parent().ok_or_eyre("no parent directory")?)
            .context("creating parent directory")?;
        fs::write(&path, &data).context("writing tar entry")?;
        files.insert(
            path.strip_prefix(&out)
                .context("getting relative path")?
                .to_str()
                .ok_or_eyre("converting path to utf-8")?
                .to_string(),
            hex::encode(hash.as_slice()),
        );
    }
    out.push(".cargo-checksum.json");
    fs::write(
        &out,
        serde_json::to_vec(&Hashes { package, files }).context("serializing hashes")?,
    )
    .context("writing hashes")?;
    Ok(())
}
