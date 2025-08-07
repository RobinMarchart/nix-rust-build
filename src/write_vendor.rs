use std::{
    collections::{HashMap, HashSet}, fs,
    os::unix,
    path::PathBuf,
};

use color_eyre::eyre::{Context, OptionExt, Result};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Dependency {
    path: String,
    dir_name: String,
    registry: String,
}

pub fn run(job: PathBuf, mut out: PathBuf) -> Result<()> {
    let job_str = fs::read_to_string(job).context("reading job")?;
    let job: HashMap<String, Dependency> = serde_json::from_str(&job_str).context("parsing job")?;
    fs::create_dir(&out).context("mkdir out")?;
    let mut config = r#"[source.vendored-sources]
directory=""#
        .to_string();
    config += out.to_str().ok_or_eyre("appending output path")?;
    config += r#""
"#;
    let registries: HashSet<&str> = job.values().map(|d| d.registry.as_str()).collect();
    for reg in registries {
        if reg == "https://github.com/rust-lang/crates.io-index" {
            config += r#"[source.crates-io]
replace-with = "vendored-sources"
"#;
        } else {
            config += r#"[source.""#;
            config += reg;
            config += r#""]
registry=""#;
            config += reg;
            config += r#""
replace-with="vendored-sources"
"#;
        }
    }
    out.push("config.toml");
    fs::write(&out, config).context("writing config")?;
    out.pop();
    for dep in job.values() {
        out.push(&dep.dir_name);
        unix::fs::symlink(&dep.path, &out).context("linking dependency source")?;
        out.pop();
    }
    Ok(())
}
