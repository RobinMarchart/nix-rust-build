use std::{
    fs::{read, read_dir, read_link, remove_file, write},
    os::unix::fs::symlink,
    path::Path,
};

use color_eyre::{Result, eyre::bail};

fn replace_in_file(from: &Path, replace: &str, with: &str) -> Result<()> {
    let content = read(from)?;
    let content = if let Ok(content) = str::from_utf8(&content) {
        println!("processing text in {}", from.display());
        content.replace(replace, with).into()
    } else {
        println!("skipping binary file {}", from.display());
        content
    };
    write(from, content)?;
    Ok(())
}

fn replace_in_symlink(from: &Path, replace: &str, with: &str) -> Result<()> {
    println!("processing symlink {}", from.display());
    let target = read_link(from)?;
    let Some(target) = target.to_str() else {
        bail!("non utf-8 link target name");
    };
    let target = target.replace(replace, with);
    remove_file(from)?;
    symlink(target, from)?;
    Ok(())
}

pub fn replace_in_dir(from: &Path, replace: &str, with: &str) -> Result<()> {
    println!("processing directory {}", from.display());
    for entry in read_dir(from)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            replace_in_dir(&entry.path(), replace, with)?
        } else if file_type.is_file() {
            replace_in_file(&entry.path(), replace, with)?
        } else if file_type.is_symlink() {
            replace_in_symlink(&entry.path(), replace, with)?
        }
    }
    Ok(())
}
