use clap::{Parser, Subcommand};
use color_eyre::Result;
use std::path::PathBuf;

use crate::{
    install_src_hash::install_src_hash, metadata::metadata, prepare_lockfile::prepare_lockfile,
    replace_output::replace_in_dir, write_vendor::write_vendor,
};

mod install_src_hash;
mod metadata;
mod prepare_lockfile;
mod replace_output;
mod run_build;
mod run_build_script;
mod run_common;
mod version;
mod write_vendor;

#[derive(Subcommand)]
enum Command {
    PrepareLockfile {
        lock_file: PathBuf,
        out: PathBuf,
    },
    ReplaceOutput {
        path: PathBuf,
        replace: String,
        with: String,
    },
    InstallSrcHash {
        archive: PathBuf,
        src: PathBuf,
        out: PathBuf,
    },
    WriteVendor {
        out: PathBuf,
        attrs: PathBuf,
    },
    Metadata {
        out: PathBuf,
        attrs: PathBuf,
    },
    RunBuildScript {
        src: PathBuf,
        out: PathBuf,
        args: PathBuf,
        script: PathBuf,
    },
    RunBuild {
        src: PathBuf,
        out: PathBuf,
        args: PathBuf,
    },
}
#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

fn main() -> Result<()> {
    unsafe { std::env::set_var("RUST_LIB_BACKTRACE", "1") };
    let args = Cli::parse();
    color_eyre::install()?;
    match args.command {
        Command::PrepareLockfile { lock_file, out } => prepare_lockfile(&lock_file, &out),
        Command::ReplaceOutput {
            path,
            replace,
            with,
        } => replace_in_dir(&path, &replace, &with),
        Command::InstallSrcHash { archive, src, out } => install_src_hash(&archive, &src, out),
        Command::WriteVendor { out, attrs } => write_vendor(&out, &attrs),
        Command::Metadata { out, attrs } => metadata(&attrs, &out),
        Command::RunBuildScript {
            src,
            out,
            args,
            script,
        } => run_build_script::run_build_script(&src, &out, &args, &script),
        Command::RunBuild { src, out, args } => run_build::run_build(&src, &out, &args)
    }
}
