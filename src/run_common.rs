use std::{
    collections::{BTreeMap, BTreeSet},
    env::{self},
    ffi::{OsStr, OsString},
    fs,
    path::{Path, PathBuf},
    process::Command,
};

use color_eyre::{
    Result,
    eyre::{OptionExt, bail, eyre},
};
use serde::{Deserialize, Serialize};

use crate::version::Version;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Common {
    pub filtered_dir: PathBuf,
    pub manifest_path: PathBuf,
    pub version: String,
    #[serde(default)]
    authors: Vec<String>,
    pub pname: String,
    description: Option<String>,
    homepage: Option<String>,
    repository: Option<String>,
    crate_name: String,
    pub target: String,
    #[serde(default)]
    pub rustc_flags: Vec<String>,
    pub links: Option<String>,
    pub optimize: bool,
    pub debuginfo: bool,
    pub edition: String,
    #[serde(default)]
    pub cfgs: Vec<String>,
    #[serde(default)]
    pub check_cfgs: Vec<String>,
    #[serde(default)]
    pub features: Vec<String>,
    #[serde(default)]
    pub all_features: Vec<String>,
    #[serde(default)]
    pub deps: Vec<Dep>,
}

impl Common {
    pub fn manifest_path(&self, src: &Path) -> Result<PathBuf> {
        let manifest_path = src.join(self.manifest_path.strip_prefix(&self.filtered_dir)?);
        Ok(manifest_path)
    }
}

#[derive(Deserialize)]
pub struct Dep {
    pub name: String,
    pub path: PathBuf,
}

#[derive(Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DepInfo {
    pub lib: PathBuf,
    pub deps: BTreeSet<PathBuf>,
    pub lib_path: BTreeSet<PathBuf>,
    pub links: Option<String>,
    pub metadata: BTreeMap<String, String>,
}

pub trait CmdExt {
    /// set environment if var is not already set
    fn env_def<'s>(&'s mut self, key: &str, val: impl AsRef<OsStr>) -> &'s mut Self;
    fn env_or_path<'s>(&'s mut self, env_name: &str, bin_name: &str) -> Result<&'s mut Self>;
    /// append value to path list
    fn env_path_append<'s>(&'s mut self, env_name: &str, append: impl AsRef<OsStr>)
    -> &'s mut Self;
}

impl CmdExt for Command {
    fn env_def<'s>(&'s mut self, key: &str, val: impl AsRef<OsStr>) -> &'s mut Self {
        fn inner<'s>(cmd: &'s mut Command, key: &str, val: &OsStr) -> &'s mut Command {
            if is_env_unset(key) {
                cmd.env(key, val);
            }
            cmd
        }
        inner(self, key, val.as_ref())
    }

    fn env_or_path<'s>(&'s mut self, env_name: &str, bin_name: &str) -> Result<&'s mut Self> {
        if is_env_unset(env_name) {
            let path = 'res: {
                for path in env::var("PATH")?.split(":") {
                    if fs::exists(path)? && fs::metadata(path)?.is_dir() {
                        for entry in fs::read_dir(path)? {
                            let entry = entry?;
                            if entry.file_name() == bin_name {
                                break 'res entry.path();
                            }
                        }
                    }
                }
                bail!("unable to find {bin_name} in PATH")
            };
            self.env(env_name, path);
        }
        Ok(self)
    }

    fn env_path_append<'s>(
        &'s mut self,
        env_name: &str,
        append: impl AsRef<OsStr>,
    ) -> &'s mut Self {
        fn inner<'s>(cmd: &'s mut Command, env_name: &str, append: &OsStr) -> &'s mut Command {
            if let Some(mut val) = env::var_os(env_name) {
                val.push(":");
                val.push(append);
                cmd.env(env_name, val.as_os_str())
            } else {
                cmd.env(env_name, append)
            }
        }
        inner(self, env_name, append.as_ref())
    }
}

fn is_env_unset(env_name: &str) -> bool {
    env::var_os(env_name).is_none()
}

pub fn cores() -> Result<String> {
    let jobs = env::var_os("NIX_BUILD_CORES")
        .map(OsString::into_string)
        .transpose()
        .map_err(|v| eyre!("NIX_BUILD_CORES has non unicode value {}", v.display()))?
        .unwrap_or_else(|| "1".to_string());
    Ok(jobs)
}

pub fn common_rustc_args(cmd: &mut Command, common: &Common, cores: &str) {
    cmd.arg("--crate-name")
        .arg(&common.crate_name)
        .arg(format!("--edition={}", common.edition))
        .arg("--check-cfg")
        .arg("cfg(docsrs,test)")
        .arg("--cap-lints")
        .arg("allow")
        .arg("--target")
        .arg(&common.target)
        .arg("--emit")
        .arg("link")
        .arg("-C")
        .arg("embed-bitcode=no")
        .arg("-C")
        .arg(format!("codegen-units={cores}"))
        .args(&common.rustc_flags)
        .args(common.cfgs.iter().flat_map(|cfg| ["--cfg", cfg.as_str()]))
        .args(
            common
                .check_cfgs
                .iter()
                .flat_map(|cfg| ["--check-cfg", cfg.as_str()]),
        );
    for feature in &common.features {
        cmd.arg("--cfg").arg(format!(r#"feature="{feature}""#));
    }
    if !common.all_features.is_empty() {
        let mut val = String::with_capacity(
            20 + common.all_features.len() * 2
                + common.all_features.iter().map(String::len).sum::<usize>(),
        );
        val.push_str("cfg(feature, values(");
        for (i, v) in common.all_features.iter().enumerate() {
            if i != 0 {
                val.push_str(", ");
            }
            val.push('"');
            val.push_str(v);
            val.push('"');
        }
        val.push_str("))");
        cmd.arg("--check-cfg").arg(val);
    }
    cmd.arg("-C").arg(if common.debuginfo {
        "debuginfo=2"
    } else {
        "strip=debuginfo"
    });
    if common.optimize {
        cmd.arg("-C").arg("opt-level=3");
    }
}

pub fn common_env(cmd: &mut Command, common: &Common, manifest_path: &Path) -> Result<()> {
    cmd.env_or_path("CARGO", "cargo")?;
    let manifest_dir = manifest_path
        .parent()
        .ok_or_eyre("manifest path should always have a parent")?;
    cmd.env_def("CARGO_MANIFEST_DIR", manifest_dir)
        .env_def("CARGO_MANIFEST_PATH", manifest_path);
    cmd.env_def("CARGO_PKG_VERSION", &common.version);
    let version = Version::from_str(&common.version).ok_or_eyre("unable to parse version")?;
    cmd.env_def(
        "CARGO_PKG_VERSION_MAJOR",
        version.major.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_VERSION_MINOR",
        version.minor.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_VERSION_PATCH",
        version.patch.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_VERSION_PRE",
        version.pre.as_deref().unwrap_or(""),
    )
    .env_def("CARGO_PKG_AUTHORS", common.authors.join(" "))
    .env_def("CARGO_PKG_NAME", &common.pname)
    .env_def(
        "CARGO_PKG_DESCRIPTION",
        common.description.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_HOMEPAGE",
        common.homepage.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_REPOSITORY",
        common.repository.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_LICENSE",
        common.repository.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_LICENSE_FILE",
        common.repository.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_RUST_VERSION",
        common.repository.as_deref().unwrap_or(""),
    )
    .env_def(
        "CARGO_PKG_README",
        common.repository.as_deref().unwrap_or(""),
    )
    .env_def("CARGO_CRATE_NAME", &common.crate_name)
    .env_path_append("PATH", manifest_dir);
    Ok(())
}
