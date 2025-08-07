use std::path::PathBuf;

use clap::{Parser, Subcommand};
use color_eyre::eyre::Result;

#[derive(Subcommand)]
enum Command {
    Lockfile {
        lock_file: PathBuf,
        out: PathBuf,
    },
    Metadata {
        project_dir: PathBuf,
        vendor_dir: PathBuf,
        target: String,
        out: PathBuf,
    },
    WriteVendor {
        job: PathBuf,
        out: PathBuf,
    },
    UnpackVendor {
        src: PathBuf,
        out: PathBuf,
    },
    Compile {
        src: PathBuf,
        cargo: PathBuf,
        rustc: PathBuf,
        job: PathBuf,
        out: PathBuf,
    },
    RunBuildScript {
        script: PathBuf,
        cargo: PathBuf,
        rustc: PathBuf,
        rustdoc: PathBuf,
        src: PathBuf,
        info_path: PathBuf,
        out: PathBuf,
    },
}

#[derive(Parser)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

mod compile;
mod metadata;
mod prepare_lockfile;
mod run_build_script;
mod unpack_vendor;
mod write_vendor;

fn main() -> Result<()> {
    match Cli::parse().command {
        Command::Lockfile { lock_file, out } => prepare_lockfile::run(&lock_file, &out),
        Command::Metadata {
            project_dir,
            vendor_dir,
            target,
            out,
        } => metadata::run(project_dir, vendor_dir, target, out),
        Command::WriteVendor { job, out } => write_vendor::run(job, out),
        Command::UnpackVendor { src, out } => unpack_vendor::run(src, out),
        Command::Compile {
            src,
            cargo,
            rustc,
            job,
            out,
        } => compile::run(src, cargo, rustc, job, out),
        Command::RunBuildScript {
            script,
            cargo,
            rustc,
            rustdoc,
            src,
            info_path,
            out,
        } => run_build_script::run(script, cargo, rustc, rustdoc, src, info_path, out),
    }
}
