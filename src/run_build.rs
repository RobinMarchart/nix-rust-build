use std::{
    collections::BTreeSet,
    ffi::OsStr,
    fs,
    os::unix::{fs::symlink, process::CommandExt},
    path::{Path, PathBuf},
    process::Command,
};

use color_eyre::{Result, eyre::OptionExt};
use serde::{
    Deserialize, Serialize,
    de::{Unexpected, Visitor},
};
use sha2::Digest;

use crate::{
    run_build_script::BuildScriptResult,
    run_common::{Common, Dep, DepInfo, common_env, common_rustc_args, cores},
    version::Version,
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    #[serde(flatten)]
    common: Common,
    build_script_run: Option<PathBuf>,
    crate_type: CrateType,
    entrypoint: PathBuf,
    target_name: String,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum CrateType {
    CDylib,
    Bin,
    ProcMacro,
    Lib,
}

impl Serialize for CrateType {
    fn serialize<S>(&self, serializer: S) -> std::prelude::v1::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let this = match self {
            CrateType::CDylib => "cdylib",
            CrateType::Bin => "bin",
            CrateType::ProcMacro => "proc-macro",
            CrateType::Lib => "lib",
        };
        serializer.serialize_str(this)
    }
}

impl<'de> Deserialize<'de> for CrateType {
    fn deserialize<D>(deserializer: D) -> std::prelude::v1::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        deserializer.deserialize_str(CrateTypeVisitor)
    }
}

struct CrateTypeVisitor;

impl<'de> Visitor<'de> for CrateTypeVisitor {
    type Value = CrateType;

    fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
        formatter.write_str(r#"one of the strings "cdylib", "proc-macro", "lib", or "bin""#)
    }

    fn visit_str<E>(self, v: &str) -> std::prelude::v1::Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        match v {
            "cdylib" => Ok(CrateType::CDylib),
            "proc-macro" => Ok(CrateType::ProcMacro),
            "lib" => Ok(CrateType::Lib),
            "bin" => Ok(CrateType::Bin),
            _ => Err(serde::de::Error::invalid_value(Unexpected::Str(v), &self)),
        }
    }
}

pub fn run_build(src: &Path, out: &Path, args: &Path) -> Result<()> {
    fs::create_dir(out)?;
    let mut args: Args = serde_json::from_slice(&fs::read(args)?)?;
    if &args.common.filtered_dir == "." {
        args.common.filtered_dir = PathBuf::new();
    }
    let mut command = Command::new("rustc");
    let manifest_path = args.common.manifest_path(src)?;
    let cores = cores()?;
    common_env(&mut command, &args.common, &manifest_path)?;
    common_rustc_args(&mut command, &args.common, &cores);
    let mut dep_info = DepInfo::default();
    if let Some(build_script) = args.build_script_run.as_ref() {
        with_build_script(
            &mut command,
            build_script,
            &mut dep_info,
            args.crate_type,
            &args.target_name,
        )?;
    }
    command.arg(src.join(args.entrypoint.strip_prefix(&args.common.filtered_dir)?));
    for dep in &args.common.deps {
        add_dep(&mut command, dep, &mut dep_info)?
    }
    match args.crate_type {
        CrateType::CDylib => {
            let lib = out.join("lib");
            fs::create_dir(&lib)?;
            let verson =
                Version::from_str(&args.common.version).ok_or_eyre("parsing crate version")?;
            let mut lib_file_name = OsStr::new("lib").to_os_string();
            lib_file_name.push(&args.target_name);
            lib_file_name.push(lib_extension(&args.common.target));
            let lib_path = lib.join(&lib_file_name);
            lib_file_name.push(".");
            lib_file_name.push(verson.major.ok_or_eyre("missing major version")?);
            let lib_major_path = lib.join(&lib_file_name);
            lib_file_name.push(".");
            lib_file_name.push(verson.minor.ok_or_eyre("missing major version")?);
            let lib_full_path = lib.join(&lib_file_name);
            symlink(&lib_full_path, &lib_path)?;
            symlink(&lib_full_path, &lib_major_path)?;
            command
                .current_dir(lib)
                .arg("-o")
                .arg(lib_full_path)
                .arg("--crate-type")
                .arg("cdylib");
        }
        CrateType::Bin => {
            let bin = out.join("bin");
            fs::create_dir(&bin)?;
            command
                .current_dir(bin)
                .arg("-o")
                .arg(&args.target_name)
                .arg("--crate-type")
                .arg("bin")
                .env("CARGO_BIN_NAME", &args.target_name);
        }
        CrateType::ProcMacro => {
            let name_hash = name_hash(&args.common);
            let mut lib_file_name = OsStr::new("lib").to_os_string();
            lib_file_name.push(args.common.pname.replace("-", "_"));
            lib_file_name.push("-");
            lib_file_name.push(&name_hash);
            lib_file_name.push(lib_extension(&args.common.target));
            let lib_path = out.join(lib_file_name);
            let metadata_path = out.join("rust-lib.json");
            command
                .current_dir(out)
                .arg("-C")
                .arg(format!("metadata={name_hash}"))
                .arg("-C")
                .arg(format!("extra-filename=-{name_hash}"))
                .arg("--out-dir")
                .arg(out)
                .arg("--extern")
                .arg("proc_macro")
                .arg("--crate-type")
                .arg("proc-macro");
            dep_info.lib = lib_path;
            dep_info.deps = Default::default();
            dep_info.lib_path = Default::default();
            fs::write(metadata_path, serde_json::to_vec(&dep_info)?)?;
        }
        CrateType::Lib => {
            let name_hash = name_hash(&args.common);
            let mut lib_file_name = OsStr::new("lib").to_os_string();
            lib_file_name.push(args.common.pname.replace("-", "_"));
            lib_file_name.push("-");
            lib_file_name.push(&name_hash);
            lib_file_name.push(".rlib");
            let lib_path = out.join(lib_file_name);
            let metadata_path = out.join("rust-lib.json");
            command
                .current_dir(out)
                .arg("-C")
                .arg(format!("metadata={name_hash}"))
                .arg("-C")
                .arg(format!("extra-filename=-{name_hash}"))
                .arg("--out-dir")
                .arg(out)
                .arg("--crate-type")
                .arg("lib");
            dep_info.lib = lib_path;
            dep_info.links = args.common.links.clone();
            fs::write(metadata_path, serde_json::to_vec(&dep_info)?)?;
        }
    }
    println!("Executing {command:?}");
    Err(command.exec().into())
}

fn name_hash(common: &Common) -> String {
    let mut hasher = sha2::Sha256::new();
    hasher.update(&common.pname);
    hasher.update(":🦀:");
    hasher.update(&common.version);
    for feature in &common.features {
        hasher.update(":🦀:");
        hasher.update(feature);
    }
    let res = hasher.finalize();
    hex::encode(&res[0..8])
}

fn lib_extension(target: &str) -> &'static str {
    if target.contains("darwin") {
        ".dylib"
    } else {
        ".so"
    }
}

fn add_dep(command: &mut Command, dep: &Dep, info: &mut DepInfo) -> Result<()> {
    let mut meta: DepInfo = serde_json::from_slice(&fs::read(dep.path.join("rust-lib.json"))?)?;
    let mut extern_arg = OsStr::new(&dep.name).to_os_string();
    extern_arg.push("=");
    extern_arg.push(meta.lib);
    command.arg("--extern").arg(extern_arg);
    add_lib_path(command, &meta.lib_path);
    info.lib_path.append(&mut meta.lib_path);
    fn add_dep_path(command: &mut Command, p: &Path) {
        let mut s = OsStr::new("dependency=").to_os_string();
        s.push(p);
        command.arg("-L").arg(s);
    }
    add_dep_path(command, &dep.path);
    info.deps.insert(dep.path.clone());
    meta.deps.iter().for_each(|p| add_dep_path(command, p));
    info.deps.append(&mut meta.deps);
    Ok(())
}

fn add_link_args(command: &mut Command, args: &[String]) {
    for arg in args {
        command.arg("-C").arg(format!("link-arg=-Wl,{arg}"));
    }
}

fn with_build_script(
    command: &mut Command,
    job: &Path,
    dep_info: &mut DepInfo,
    crate_type: CrateType,
    target_name: &str,
) -> Result<()> {
    let run: BuildScriptResult = serde_json::from_slice(&fs::read(job.join("result.json"))?)?;
    dep_info.metadata = run.metadata;
    dep_info.lib_path = run.lib_path.clone();
    command
        .envs(run.envs)
        .env("OUT_DIR", job.join("output"))
        .args(run.flags);
    add_lib_path(command, &run.lib_path);
    for lib in run.link_lib {
        command.arg("-l").arg(lib);
    }
    for cfg in run.cfgs {
        command.arg("--cfg").arg(cfg);
    }
    for check_cfg in run.check_cfgs {
        command.arg("--check-cfg").arg(check_cfg);
    }
    add_link_args(command, &run.link_args);
    match crate_type {
        CrateType::CDylib => add_link_args(command, &run.link_args_cdylib),
        CrateType::Bin => {
            add_link_args(command, &run.link_args_bins);
            if let Some(args) = run.link_args_bin.get(target_name) {
                add_link_args(command, args);
            }
        }
        CrateType::ProcMacro | CrateType::Lib => {}
    }
    Ok(())
}

fn add_lib_path(command: &mut Command, lib_path: &BTreeSet<PathBuf>) {
    for lib in lib_path {
        command.arg("-L").arg(lib);
    }
}
