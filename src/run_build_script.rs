use std::{
    collections::{
        hash_map::Entry::{Occupied, Vacant},
        HashMap, HashSet,
    },
    fs,
    io::{BufRead, BufReader},
    path::{Path, PathBuf},
    process::{self, Command},
    sync::LazyLock,
};

use color_eyre::eyre::{eyre, Context, ContextCompat, OptionExt, Result};
use owo_colors::OwoColorize;
use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::compile::{CrateJobCommon, RustLibMetadata};

#[derive(Debug, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct BuildScriptResult {
    pub metadata: HashMap<String, String>,
    pub link_args: Vec<String>,
    pub link_args_cdylib: Vec<String>,
    pub link_args_bins: Vec<String>,
    pub link_args_bin: HashMap<String, Vec<String>>,
    pub link_lib: Vec<String>,
    pub lib_path: HashSet<PathBuf>,
    pub flags: Vec<String>,
    pub cfgs: Vec<String>,
    pub check_cfgs: Vec<String>,
    pub envs: HashMap<String, String>,
}

pub fn run(
    script: PathBuf,
    cargo: PathBuf,
    rustc: PathBuf,
    rustdoc: PathBuf,
    src: PathBuf,
    info_path: PathBuf,
    mut out: PathBuf,
) -> Result<()> {
    out.push("output");
    fs::create_dir_all(&out).context("creating script output dir")?;
    let info: CrateJobCommon =
        serde_json::from_slice(&fs::read(info_path).context("reading build script info")?)
            .context("deserializing build script info")?;
    let mut command = Command::new(script);
    command
        .env_remove("RUSTFLAGS")
        .env("CARGO_MAKEFLAGS", "")
        .env("CARGO_MANIFEST_PATH", &info.manifest_path)
        .env(
            "CARGO_MANIFEST_DIR",
            info.manifest_path
                .parent()
                .context("getting manifest directory")?,
        )
        .env("CARGO_PKG_NAME", &info.pname)
        .env("OUT_DIR", &out)
        .env("TARGET", &info.target)
        .env("HOST", rustc_host_tripple(&rustc)?.trim())
        .env("NUM_JOBS", "1")
        .env("RUSTC", &rustc)
        .env("RUSTDOC", &rustdoc)
        .env("CARGO_ENCODED_RUSTFLAGS", info.rustc_flags.join("\x1f"));
    info.add_metadaten_env(&cargo, &src, &mut command)?;
    if info.optimize {
        command.env("OPT_LEVEL", "3").env("PROFILE", "release");
    } else {
        command.env("OPT_LEVEL", "1").env("PROFILE", "debug");
    }
    if info.debuginfo {
        command.env("DEBUG", "true");
    } else {
        command.env("DEBUG", "false");
    }
    let mut cfgs: HashMap<&str, HashSet<&str>> = HashMap::new();
    cfgs.insert(
        "feature",
        info.features.iter().map(String::as_str).collect(),
    );
    let rustc_cfg = cfg_from_rustc(&info.target, &rustc)?;
    for r in parse_cfgs(&rustc_cfg)
        .into_iter()
        .chain(info.cfgs.iter().map(|c| parse_cfg(c)))
    {
        let (name, val) = r?;
        match (cfgs.entry(name), val) {
            (Occupied(_), None) => {}
            (Occupied(mut e), Some(v)) => {
                e.get_mut().insert(v);
            }
            (Vacant(e), None) => {
                e.insert(HashSet::new());
            }
            (Vacant(e), Some(v)) => {
                let mut set = HashSet::new();
                set.insert(v);
                e.insert(set);
            }
        }
    }
    for (name, vals) in cfgs {
        let name = "CARGO_CFG_".to_string() + &name.to_uppercase();
        let val = Vec::from_iter(vals).join(",");
        command.env(name, val);
    }
    for f in info.features {
        let name = "CARGO_FEATURE_".to_string() + &f.to_uppercase().replace("-", "_");
        command.env(name, "1");
    }
    for dep in info.deps {
        let dep_metadata: RustLibMetadata = toml::from_slice(
            &fs::read(dep.path.join("rust-lib.toml")).context("reading rust lib metadata")?,
        )
        .context("deserializing rust lib metadata")?;
        for (key, value) in dep_metadata.metadata {
            command.env(format!("DEP_{}_{key}", dep.name), value);
        }
    }
    out.pop();
    out.push("result.toml");
    let mut script = command
        .stdout(process::Stdio::piped())
        .spawn()
        .context("executing build script")?;

    let mut result = BuildScriptResult::default();
    let mut error = false;

    for line in BufReader::new(script.stdout.as_mut().expect("requested pipe")).lines() {
        parse_script_output_line(&line?, &mut result, &mut error);
    }
    if !script.wait()?.success() {
        return Err(eyre!("build script execution failed"));
    }

    fs::write(
        out,
        toml::to_string_pretty(&result).context("serializing build script result")?,
    )
    .context("writing build script result")?;
    if error {
        Err(eyre!("build script reported error"))
    } else {
        Ok(())
    }
}

static CFG_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"([^=\n]*)(?:="([^"\n]*)")?"#).unwrap());

static CFG_REGEX_STRICT: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"^([^=\n]*)(?:="([^"\n]*)")?$"#).unwrap());

fn parse_cfgs(str: &str) -> impl IntoIterator<Item = Result<(&str, Option<&str>)>> {
    CFG_REGEX.captures_iter(str).map(|m| {
        let name = m
            .get(1)
            .expect("first capture should always be there")
            .as_str();
        let val = m.get(2).map(|m| m.as_str());
        Ok((name, val))
    })
}
fn parse_cfg(str: &str) -> Result<(&str, Option<&str>)> {
    CFG_REGEX_STRICT
        .captures(str)
        .map(|m| {
            let name = m
                .get(1)
                .expect("first capture should always be there")
                .as_str();
            let val = m.get(2).map(|m| m.as_str());
            (name, val)
        })
        .ok_or_eyre("unable to parse cfg")
}

pub fn cfg_from_rustc(target: &str, rustc: &Path) -> Result<String> {
    String::from_utf8(
        Command::new(rustc)
            .arg("-O")
            .arg("--print=cfg")
            .arg("--target")
            .arg(target)
            .output()
            .context("getting cfg from rustc")?
            .stdout,
    )
    .context("outputs includes non utf-8")
}
pub fn rustc_host_tripple(rustc: &Path) -> Result<String> {
    String::from_utf8(
        Command::new(rustc)
            .arg("--print=host-tuple")
            .output()
            .context("getting host tuple from rustc")?
            .stdout,
    )
    .context("outputs includes non utf-8")
}

static SCRIPT_OUT_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^\s*cargo::?([a-z\-]+)=((?:([^=\s]+)=)?("(.*)"\s*|([^\s]+)\s*|.+))$"#).unwrap()
});


fn parse_script_output_line(line: &str, out: &mut BuildScriptResult, error: &mut bool) {
    if let Some(capture) = SCRIPT_OUT_REGEX.captures(line) {
        match capture
            .get(1)
            .expect("the first group is not optional")
            .as_str()
        {
            "rerun-if-changed" | "rerun-if-env-changed" => {
                return;
            }
            "rustc-link-arg" => {
                out.link_args.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }
            "rustc-link-arg-cdylib" => {
                out.link_args_cdylib.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }

            "rustc-link-arg-bin" => {
                if let Some(name) = capture.get(3) {
                    match out.link_args_bin.entry(name.as_str().to_string()) {
                        Occupied(e) => e.into_mut(),
                        Vacant(e) => e.insert(Vec::new()),
                    }
                    .push(
                        capture
                            .get(4)
                            .expect("not optional at this point")
                            .as_str()
                            .trim()
                            .to_string(),
                    );
                    return;
                }
            }
            "rustc-link-arg-bins" => {
                out.link_args_bins.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }
            "rustc-link-arg-tests" | "rustc-link-arg-examples" | "rustc-link-arg-benches" => {
                return;
            }
            "rustc-link-lib" => {
                if let Some(name) = capture.get(5) {
                    out.link_lib.push(name.as_str().to_string());
                    return;
                }
            }
            "rustc-link-search" => {
                out.lib_path.insert(
                    capture
                        .get(4)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string()
                        .into(),
                );
                return;
            }
            "rustc-flags" => {
                out.flags.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }
            "rustc-cfg" => {
                out.cfgs.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }
            "rustc-check-cfg" => {
                out.check_cfgs.push(
                    capture
                        .get(2)
                        .expect("not optional")
                        .as_str()
                        .trim()
                        .to_string(),
                );
                return;
            }
            "rustc-env" => {
                if let Some(name) = capture.get(3) {
                    out.envs.insert(
                        name.as_str().to_string(),
                        capture
                            .get(4)
                            .expect("not optional here")
                            .as_str()
                            .trim()
                            .to_string(),
                    );
                    return;
                }
            }
            "error" => {
                println!(
                    "{}: {}",
                    "error".red(),
                    capture.get(2).expect("not optional").as_str()
                );
                *error = true;
                return;
            }
            "warning" => {
                println!(
                    "{}: {}",
                    "warning".yellow(),
                    capture.get(2).expect("not optional").as_str()
                );
                return;
            }
            "metadata" => {
                if let Some(name) = capture.get(3) {
                    out.metadata.insert(
                        name.as_str().to_string(),
                        capture
                            .get(4)
                            .expect("not optional here")
                            .as_str()
                            .trim()
                            .to_string(),
                    );
                    return;
                }
            }
            _ => {}
        }
    }
    println!("{}: {line}", "build-script".blue())
}
