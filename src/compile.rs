use cargo_metadata::Edition;
use color_eyre::eyre::{bail, eyre, Context, OptionExt, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    env, fs,
    os::unix::{fs::symlink, process::CommandExt},
    path::{Path, PathBuf},
    process::Command,
};

use crate::run_build_script::BuildScriptResult;

#[derive(Debug, Serialize, Deserialize)]
pub struct RustLibMetadata {
    pub lib: PathBuf,
    pub deps: HashSet<PathBuf>,
    pub metadata: HashMap<String, String>,
    pub lib_path: HashSet<PathBuf>,
    pub links: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ResolvedDep {
    pub name: String,
    pub path: PathBuf,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CrateJobCommon {
    pub rustc_flags: Vec<String>,
    pub cfgs: Vec<String>,
    pub link_args: Vec<String>,
    pub manifest_path: PathBuf,
    pub version: String,
    pub authors: Option<String>,
    pub pname: String,
    pub description: Option<String>,
    pub homepage: Option<String>,
    pub repository: Option<String>,
    pub license: Option<String>,
    pub license_file: Option<PathBuf>,
    pub rust_version: Option<String>,
    pub readme: Option<PathBuf>,
    pub target: String,
    pub features: Vec<String>,
    pub all_features: Vec<String>,
    pub crate_name: String,
    pub edition: Edition,
    pub deps: Vec<ResolvedDep>,
    pub links: Option<String>,
    pub optimize: bool,
    pub debuginfo: bool,
}

fn s(s: &Option<String>) -> &str {
    s.as_deref().unwrap_or("")
}

fn p(p: &Option<PathBuf>, base: &Path) -> PathBuf {
    p.as_deref().map(|p| base.join(p)).unwrap_or_default()
}

impl CrateJobCommon {
    pub fn add_metadata_env(&self, cargo: &Path, src: &Path, command: &mut Command) -> Result<()> {
        let version = cargo_metadata::semver::Version::parse(&self.version)
            .context("parsing crate version")?;
        let manifest_path = src.join(&self.manifest_path);
        command
            .env("CARGO", cargo)
            .env(
                "CARGO_MANIFEST_DIR",
                manifest_path
                    .parent()
                    .ok_or_eyre("manifest has no parent dir")?,
            )
            .env("CARGO_MANIFEST_PATH", manifest_path)
            .env("CARGO_PKG_VERSION", &self.version)
            .env("CARGO_PKG_VERSION_MAJOR", version.major.to_string())
            .env("CARGO_PKG_VERSION_MINOR", version.minor.to_string())
            .env("CARGO_PKG_VERSION_PATCH", version.patch.to_string())
            .env("CARGO_PKG_VERSION_PRE", version.pre.as_str())
            .env("CARGO_PKG_AUTHORS", s(&self.authors))
            .env("CARGO_PKG_NAME", &self.pname)
            .env("CARGO_PKG_DESCRIPTION", s(&self.description))
            .env("CARGO_PKG_HOMEPAGE", s(&self.homepage))
            .env("CARGO_PKG_REPOSITORY", s(&self.repository))
            .env("CARGO_PKG_LICENSE", s(&self.license))
            .env("CARGO_PKG_LICENSE_FILE", p(&self.license_file, src))
            .env("CARGO_PKG_RUST_VERSION", s(&self.rust_version))
            .env("CARGO_PKG_README", p(&self.readme, src))
            .env("CARGO_CRATE_NAME", &self.crate_name);
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CrateJob {
    #[serde(flatten)]
    common: CrateJobCommon,
    crate_type: String,
    entrypoint: PathBuf,
    target_name: String,
    build_script_run: Option<PathBuf>,
    #[serde(default)]
    metadata: HashMap<String, String>,
    #[serde(default)]
    lib_path: HashSet<PathBuf>,
    #[serde(default)]
    link_lib: Vec<String>,
    #[serde(default)]
    all_deps: HashSet<PathBuf>,
    #[serde(default)]
    check_cfgs: Vec<String>,
    #[serde(default)]
    envs: HashMap<String, String>,
}

impl CrateJob {
    fn with_build_script(&mut self) -> Result<&mut Self> {
        if let Some(path) = self.build_script_run.as_ref() {
            let mut build_script: BuildScriptResult = toml::from_str(
                &fs::read_to_string(path.join("result.toml"))
                    .context("reading build script result")?,
            )
            .context("deserializing build script result")?;
            self.metadata = build_script.metadata;
            self.lib_path = build_script.lib_path;
            self.common.rustc_flags.append(&mut build_script.flags);
            self.common.cfgs.append(&mut build_script.cfgs);
            self.common.link_args.append(&mut build_script.link_args);
            match self.crate_type.as_str() {
                "cdylib" => self
                    .common
                    .link_args
                    .append(&mut build_script.link_args_cdylib),
                "bin" => {
                    self.common
                        .link_args
                        .append(&mut build_script.link_args_bins);
                    if let Some(specific) = build_script.link_args_bin.get_mut(&self.common.pname) {
                        self.common.link_args.append(specific);
                    }
                }
                _ => {}
            }
            self.check_cfgs = build_script.check_cfgs;
            self.envs = build_script.envs;
            self.envs.insert(
                "OUT_DIR".to_string(),
                path.join("output")
                    .into_os_string()
                    .into_string()
                    .map_err(|path| {
                        eyre!("path \"{}\" contains non unicode value", path.display())
                    })?,
            );
        }
        Ok(self)
    }

    fn lib_path_from_env(&mut self) -> &mut Self {
        if let Ok(var) = env::var("LD_LIBRARY_PATH") {
            for path in var.split(":") {
                self.lib_path.insert(PathBuf::from(path));
            }
        }
        self
    }

    fn command_common(&mut self, cargo: &Path, rustc: &Path, src: &Path) -> Result<Command> {
        let mut command = Command::new(rustc);
        self.common.add_metadata_env(cargo, src, &mut command)?;
        command
            .arg("--crate-name")
            .arg(&self.common.crate_name)
            .arg("--edition=".to_string() + self.common.edition.as_str())
            .arg(src.join(&self.entrypoint))
            .arg("--check-cfg")
            .arg("cfg(docsrs,test)")
            .arg("-C")
            .arg("embed-bitcode=no")
            .arg("--cap-lints")
            .arg("allow")
            .arg("--target")
            .arg(&self.common.target)
            .arg("--emit")
            .arg("link")
            .arg("--crate-type")
            .arg(&self.crate_type);
        command.envs(self.envs.iter());
        command.args(&self.common.rustc_flags);
        for arg in &self.common.cfgs {
            command.arg("--cfg").arg(arg);
        }
        for cfg in &self.check_cfgs {
            command.arg("--check-cfg").arg(cfg);
        }
        for dep in &self.common.deps {
            let dep_metadata: RustLibMetadata = toml::from_str(
                &fs::read_to_string(dep.path.join("rust-lib.toml"))
                    .context("reading rust lib metadata")?,
            )
            .context("deserializing rust lib metadata")?;
            command
                .arg("--extern")
                .arg(format!("{}={}", &dep.name, dep_metadata.lib.display()));
            self.lib_path.extend(dep_metadata.lib_path);
            self.all_deps.insert(dep.path.clone());
            self.all_deps.extend(dep_metadata.deps);
        }
        if ["bin", "cdylib", "proc-macro"].contains(&self.crate_type.as_str()) {
            for arg in &self.common.link_args {
                command.arg("-C").arg(format!("link-arg={arg}"));
            }
            for lib in &self.lib_path {
                command.arg("-L").arg(lib);
            }
        }
        for lib in &self.link_lib {
            command.arg("-l").arg(lib);
        }
        for dep in &self.all_deps {
            command
                .arg("-L")
                .arg(format!("dependency={}", dep.display()));
        }
        for feature in &self.common.features {
            command.arg("--cfg").arg(format!("feature=\"{feature}\""));
        }
        let mut check_features = "cfg(feature, values(".to_string();
        for (index, feature) in self.common.all_features.iter().enumerate() {
            if index != 0 {
                check_features.push_str(", ");
            }
            check_features.push('"');
            check_features.push_str(feature);
            check_features.push('"');
        }
        check_features.push_str("))");
        command.arg("--check-cfg").arg(check_features);
        if self.common.debuginfo {
            command.args(["-C", "debuginfo=2"]);
        } else {
            command.args(["-C", "strip=debuginfo"]);
        }
        if self.common.optimize {
            command.args(["-C", "opt-level=3"]);
        }
        Ok(command)
    }
    fn bin(self, command: &mut Command, out: &Path) -> Result<()> {
        let bin = out.join("bin");
        fs::create_dir_all(&bin).context("creating output dir")?;
        command
            .current_dir(bin)
            .arg("-o")
            .arg(&self.target_name)
            .env("CARGO_BIN_NAME", self.target_name);
        Ok(())
    }
    fn lib(self, command: &mut Command, out: &Path) -> Result<()> {
        fs::create_dir_all(out).context("creating output dir")?;
        let mut hash = Sha256::new();
        hash.update(&self.common.pname);
        hash.update(&self.common.version);
        for f in &self.common.features {
            hash.update(f);
        }
        let hash = hex::encode(&hash.finalize().as_slice()[0..8]);
        command
            .arg("-C")
            .arg(format!("metadata={hash}"))
            .arg("-C")
            .arg(format!("extra-filename=-{hash}"))
            .arg("--out-dir")
            .arg(out);
        let lib_path = out.join(format!("lib{}-{hash}.rlib", &self.common.crate_name));
        let metadata_path = out.join("rust-lib.toml");
        if !self.metadata.is_empty() && self.common.links.is_none(){
            bail!("metadata without links");
        }
        fs::write(
            metadata_path,
            toml::to_string_pretty(&RustLibMetadata {
                lib: lib_path,
                deps: self.all_deps,
                metadata: self.metadata,
                lib_path: self.lib_path,
                links: self.common.links,
            })
            .context("serializing library metadata")?,
        )
        .context("writing library metadata")?;
        Ok(())
    }
    fn proc_macro(self, command: &mut Command, out: &Path) -> Result<()> {
        fs::create_dir_all(out).context("creating output dir")?;
        let mut hash = Sha256::new();
        hash.update(&self.common.pname);
        hash.update(&self.common.version);
        for f in &self.common.features {
            hash.update(f);
        }
        let hash = hex::encode(&hash.finalize().as_slice()[0..8]);
        command
            .arg("-C")
            .arg(format!("metadata={hash}"))
            .arg("-C")
            .arg(format!("extra-filename=-{hash}"))
            .arg("--out-dir")
            .arg(out)
            .arg("--extern")
            .arg("proc_macro");
        let lib_path = out.join(format!("lib{}-{hash}.so", &self.common.crate_name));
        let metadata_path = out.join("rust-lib.toml");
        fs::write(
            metadata_path,
            toml::to_string_pretty(&RustLibMetadata {
                lib: lib_path,
                deps: HashSet::new(),
                metadata: self.metadata,
                lib_path: HashSet::new(),
                links: None
            })
            .context("serializing library metadata")?,
        )
        .context("writing library metadata")?;
        Ok(())
    }
    fn cdylib(self, command: &mut Command, out: &Path) -> Result<()> {
        let lib_dir = out.join("lib");
        fs::create_dir_all(&lib_dir).context("creating output dir")?;
        let version = cargo_metadata::semver::Version::parse(&self.common.version)
            .context("parsing crate version")?;
        command.current_dir(&lib_dir);
        let lib_name = format!("lib{}.so", self.target_name);
        let lib_path = lib_dir.join(&lib_name);
        let lib_major_path = lib_dir.join(format!("{}.{}", &lib_name, version.major));
        let lib_full_path = lib_dir.join(format!(
            "{}.{}.{}.{}",
            &lib_name, version.major, version.minor, version.patch
        ));
        command.arg("-o").arg(&lib_full_path);
        symlink(&lib_full_path, &lib_path).context("creating symlink without version")?;
        symlink(&lib_full_path, &lib_major_path).context("creating symlink with major version")?;
        Ok(())
    }
}

pub fn run(src: PathBuf, cargo: PathBuf, rustc: PathBuf, job: PathBuf, out: PathBuf) -> Result<()> {
    let mut job: CrateJob = serde_json::from_slice(&fs::read(job).context("reading job")?)
        .context("deserializing job")?;
    let mut command = job
        .with_build_script()?
        .lib_path_from_env()
        .command_common(&cargo, &rustc, &src)?;
    match job.crate_type.as_str() {
        "bin" => job.bin(&mut command, &out),
        "lib" => job.lib(&mut command, &out),
        "proc-macro" => job.proc_macro(&mut command, &out),
        "cdylib" => job.cdylib(&mut command, &out),
        c => Err(eyre!("unknown crate type {c}")),
    }?;
    println!("executing {command:?}");
    Err(command.exec()).context("executing rustc")
}
