use std::{
    env::args_os,
    fs::{read, read_dir, read_link, remove_file, write},
    io::{Error, Result},
    os::unix::fs::symlink,
    path::{Path, PathBuf},
};

fn main() -> Result<()> {
    let mut args = args_os();
    let Some(_) = args.next() else {
        return Err(Error::other("binary name is not set"));
    };
    let Some(from) = args.next().map(PathBuf::from) else {
        return Err(Error::other("missing first argument (file)"));
    };
    let Some(replace) = args.next().and_then(|s| s.into_string().ok()) else {
        return Err(Error::other("missing second argument (replace)"));
    };
    let Some(with) = args.next().and_then(|s| s.into_string().ok()) else {
        return Err(Error::other("missing third argument (with)"));
    };
    move_dir(&from, &replace, &with)
}

fn move_file(from: &Path, replace: &str, with: &str) -> Result<()> {
    let content = read(from)?;
    let content = if let Ok(content) = str::from_utf8(&content) {
        println!("processing text in {}", from.display());
        content.replace(replace, with).into()
    } else {
        println!("skipping binary file {}", from.display());
        content
    };
    write(from, content)
}

fn move_symlink(from: &Path, replace: &str, with: &str) -> Result<()> {
    println!("processing symlink {}", from.display());
    let target = read_link(from)?;
    let Some(target) = target.to_str() else {
        return Err(Error::other("non utf-8 link target name"));
    };
    let target = target.replace(replace, with);
    remove_file(from)?;
    symlink(target, from)
}

fn move_dir(from: &Path, replace: &str, with: &str) -> Result<()> {
    println!("processing directory {}", from.display());
    for entry in read_dir(from)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            move_dir(&entry.path(), replace, with)?
        } else if file_type.is_file() {
            move_file(&entry.path(), replace, with)?
        } else if file_type.is_symlink() {
            move_symlink(&entry.path(), replace, with)?
        }
    }
    Ok(())
}
