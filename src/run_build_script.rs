use std::{
    collections::{BTreeMap, BTreeSet, btree_map},
    ffi::OsString,
    fs::{self, create_dir},
    io::Read,
    path::{Path, PathBuf},
    process::{Command, ExitStatus, Stdio},
    sync::LazyLock,
};

use color_eyre::{
    Result,
    eyre::{OptionExt, bail},
    owo_colors::{OwoColorize, colors::xterm::BlazeOrange},
};
use regex::Regex;
use serde::{Deserialize, Serialize};

use crate::run_common::{CmdExt, Common, DepInfo, common_env, common_rustc_args, cores};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Args {
    #[serde(flatten)]
    common: Common,
}

fn add_host_tuple(command: &mut Command) -> Result<()> {
    let host_tuple = {
        let res = Command::new("rustc")
            .arg("--print=host-tuple")
            .stderr(Stdio::inherit())
            .output()?;
        if !res.status.success() {
            bail!("printing host tuple failed")
        }
        String::from_utf8(res.stdout)?
    };
    command.env("HOST", host_tuple.trim());
    Ok(())
}

static CFG_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^(?<name>[^=\n]*)(?:="(?<val>[^"\n]*)")?$"#).expect("correct regex")
});

fn add_cfg_vars(command: &mut Command, common: &Common, cores: &str) -> Result<()> {
    let mut print_cfg = Command::new("rustc");
    print_cfg.arg("--print=cfg");
    common_rustc_args(&mut print_cfg, common, cores);
    let output = print_cfg.stderr(Stdio::piped()).output()?;
    if !output.status.success() {
        bail!("print config failed");
    }
    let output = String::from_utf8(output.stdout)?;
    let mut cfgs = BTreeMap::new();
    for line in output.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let captures = CFG_PATTERN
            .captures(line)
            .ok_or_eyre("unable to parse line")?;
        let name = captures.name("name").ok_or_eyre("missing name")?.as_str();
        let val = captures.name("val").map(|m| m.as_str());
        let out = match cfgs.entry(name) {
            btree_map::Entry::Occupied(occupied_entry) => occupied_entry.into_mut(),
            btree_map::Entry::Vacant(vacant_entry) => vacant_entry.insert(String::new()),
        };
        if let Some(val) = val {
            if !out.is_empty() {
                out.push(',');
            }
            out.push_str(val);
        }
    }
    for (name, val) in cfgs {
        let mut var_name = String::new();
        let prefix = "CARGO_CFG_";
        var_name.push_str(prefix);
        var_name.push_str(name);
        var_name[prefix.len()..].make_ascii_uppercase();
        command.env(var_name, val);
    }
    Ok(())
}

fn add_dep_vars(command: &mut Command, common: &Common) -> Result<()> {
    for dep in &common.deps {
        let info_path = dep.path.join("rust-lib.json");
        let mut info: DepInfo = serde_json::from_slice(&fs::read(&info_path)?)?;
        let Some(links) = info.links.as_mut() else {
            continue;
        };
        links.make_ascii_uppercase();
        for (key, val) in &info.metadata {
            let key = key.to_uppercase();
            let key = format!("DEP_{links}_{key}");
            command.env(key, val);
        }
    }
    Ok(())
}

pub fn run_build_script(src: &Path, out: &Path, args: &Path, script: &Path) -> Result<()> {
    create_dir(out)?;
    let script_out = out.join("output");
    create_dir(&script_out)?;
    let mut args: Args = serde_json::from_slice(&fs::read(args)?)?;
    if &args.common.filtered_dir == "." {
        args.common.filtered_dir = PathBuf::new();
    }
    let mut command = Command::new(script);
    let jobs = cores()?;
    let mut makeflags = OsString::from("-j ");
    makeflags.push(&jobs);
    let encoded_rust_flags = args.common.rustc_flags.join("\u{1f}");
    let manifest_path = args.common.manifest_path(src)?;
    let manifest_dir = manifest_path
        .parent()
        .ok_or_eyre("parent dir of manifest file")?;
    command
        .env("RUST_BACKTRACE", "1")
        .env("CARGO_MAKEFLAGS", makeflags)
        .env("OUT_DIR", &script_out)
        .env("TARGET", &args.common.target)
        .env("NUM_JOBS", &jobs)
        .env_or_path("RUSTC", "rustc")?
        .env_or_path("RUSTDOC", "rustdoc")?
        .env("CARGO_ENCODED_RUSTFLAGS", encoded_rust_flags);
    add_host_tuple(&mut command)?;
    if let Some(links) = args.common.links.as_ref() {
        command.env("CARGO_MANIFEST_LINKS", links);
    }
    if args.common.optimize {
        command.env("OPT_LEVEL", "3").env("PROFILE", "release");
    } else {
        command.env("OPT_LEVEL", "0").env("PROFILE", "debug");
    }
    command.env(
        "DEBUG",
        if args.common.debuginfo {
            "true"
        } else {
            "false"
        },
    );
    add_cfg_vars(&mut command, &args.common, &jobs)?;
    for feature in &args.common.features {
        let prefix = "CARGO_CFG_";
        let mut name = String::with_capacity(prefix.len() + feature.len());
        name.push_str(prefix);
        name.push_str(feature);
        name[prefix.len()..].make_ascii_uppercase();
        command.env(name, "1");
    }
    add_dep_vars(&mut command, &args.common)?;
    common_env(&mut command, &args.common, &manifest_path)?;
    println!("pwd: {}", manifest_dir.display());
    command.current_dir(manifest_dir);
    let mut result = BuildScriptResult::default();
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    let res = spawn_build_script(&mut command, &mut result, &mut warnings, &mut errors)?;
    for warning in warnings {
        println!("[{}]: {}", "warning".fg::<BlazeOrange>(), warning);
    }
    if !errors.is_empty() || !res.success() {
        for error in &errors {
            println!("[{}]: {}", "error".red(), error);
        }
        bail!("build script produced some errors");
    }
    fs::write(out.join("result.json"), serde_json::to_vec(&result)?)?;
    Ok(())
}

#[derive(Default, Serialize, Deserialize)]
pub struct BuildScriptResult {
    pub metadata: BTreeMap<String, String>,
    pub link_args: Vec<String>,
    pub link_args_cdylib: Vec<String>,
    pub link_args_bins: Vec<String>,
    pub link_args_bin: BTreeMap<String, Vec<String>>,
    pub link_lib: Vec<String>,
    pub lib_path: BTreeSet<PathBuf>,
    pub flags: Vec<String>,
    pub cfgs: Vec<String>,
    pub check_cfgs: Vec<String>,
    pub envs: BTreeMap<String, String>,
}

static OUTPUT_PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r#"^\s*cargo(?<cargo>::?)(?<cmd>[a-z\-_]+)=(?<full>(?:(?<name>[^=\s]+)=)?(?<val>.*))$"#,
    )
    .expect("regex")
});

fn handle_build_script_output(
    line: &str,
    out: &mut BuildScriptResult,
    warnings: &mut Vec<String>,
    errors: &mut Vec<String>,
) {
    let Some(captures) = OUTPUT_PATTERN.captures(line) else {
        return;
    };
    match &captures["cmd"] {
        "rerun-if-changed"
        | "rerun-if-env-changed"
        | "rustc-link-arg-tests"
        | "rustc-link-arg-examples"
        | "rustc-link-arg-benches" => {}
        "rustc-link-arg" => {
            out.link_args.push(captures["full"].trim().to_string());
        }
        "rustc-link-arg-cdylib" => {
            out.link_args_cdylib
                .push(captures["full"].trim().to_string());
        }
        "rustc-link-arg-bins" => {
            out.link_args_bins.push(captures["full"].trim().to_string());
        }
        "rustc-link-arg-bin" => {
            if let Some(name) = captures.name("name") {
                out.link_args_bin
                    .entry(name.as_str().trim().to_string())
                    .or_default()
                    .push(captures["val"].trim().to_string());
            } else {
                errors.push("rustc-link-arg-bin cargo command has invalid arguments".to_string());
            };
        }
        "rustc-link-lib" => {
            out.link_lib.push(captures["full"].trim().to_string());
        }
        "rustc-link-search" => {
            out.lib_path.insert(PathBuf::from(captures["full"].trim()));
        }
        "rustc-flags" => {
            out.flags.push(captures["full"].trim().to_string());
        }
        "rustc-cfg" => {
            out.cfgs.push(captures["full"].trim().to_string());
        }
        "rustc-check-cfg" => {
            out.check_cfgs.push(captures["full"].trim().to_string());
        }
        "rustc-env" => {
            if let Some(name) = captures.name("name") {
                out.envs.insert(
                    name.as_str().trim().to_string(),
                    captures["val"].trim().to_string(),
                );
            } else {
                errors.push("rustc-env cargo command has invalid arguments".to_string());
            }
        }
        "metadata" => {
            if "::" == &captures["cargo"] {
                if let Some(name) = captures.name("name") {
                    out.metadata.insert(
                        name.as_str().trim().to_string(),
                        captures["val"].trim().to_string(),
                    );
                } else {
                    errors.push("metadata cargo command has invalid arguments".to_string());
                }
            } else {
                out.metadata
                    .insert("metadata".to_string(), captures["full"].trim().to_string());
            }
        }
        "warning" => {
            warnings.push(captures["full"].trim().to_string());
        }
        "error" => {
            errors.push(captures["full"].trim().to_string());
        }
        name => {
            if ":" == &captures["cargo"] {
                out.metadata
                    .insert(name.to_string(), captures["full"].trim().to_string());
            }
        }
    }
}

static LINE_PATTERN: LazyLock<regex::bytes::Regex> =
    LazyLock::new(|| regex::bytes::Regex::new("\n").expect("pattern not correct"));

fn spawn_build_script(
    command: &mut Command,
    out: &mut BuildScriptResult,
    warnings: &mut Vec<String>,
    errors: &mut Vec<String>,
) -> Result<ExitStatus> {
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let mut out_stream = child.stdout.take().ok_or_eyre("out is missing")?;
    let mut buf = vec![0u8; 4096];
    let mut buf_pos = 0usize;
    loop {
        let len = out_stream.read(&mut buf[buf_pos..])?;
        if len == 0 {
            break;
        }
        buf_pos += len;
        let buf_slice = &buf[0..buf_pos];
        let mut matches = LINE_PATTERN.find_iter(buf_slice);
        let Some(mut last) = matches.next() else {
            continue;
        };
        handle_build_script_output(
            str::from_utf8(&buf_slice[0..last.start()])?,
            out,
            warnings,
            errors,
        );
        for m in matches {
            handle_build_script_output(
                str::from_utf8(&buf_slice[last.end()..m.start()])?,
                out,
                warnings,
                errors,
            );
            last = m;
        }
        let residual = last.end()..buf_pos;
        buf_pos = residual.len();
        buf.copy_within(residual, 0);
    }
    handle_build_script_output(str::from_utf8(&buf[0..buf_pos])?, out, warnings, errors);
    Ok(child.wait()?)
}
