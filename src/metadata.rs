use color_eyre::eyre::{bail, eyre, Context, OptionExt, Result};
use serde::Serialize;
use std::{
    collections::HashMap, env, fs, path::{Path, PathBuf}
};

use cargo_metadata::{
    CargoOpt, CrateType, Edition, MetadataCommand, Node, Package, PackageId, TargetKind,
};

use cargo_util_schemas::manifest::FeatureName;

#[derive(Debug,Clone,PartialEq,Eq,Hash)]
enum PkgId<'s> {
    Original(&'s PackageId),
    Modified(String),
}

impl<'s> PkgId<'s> {
    fn new(pkg: &'s PackageId, src: &Path) -> Self{
        let src = src.to_str().expect("package id has non unicode char");
        if pkg.repr.contains(src) {
            Self::Modified(pkg.repr.replace(src, "source"))
        } else {
            Self::Original(pkg)
        }
    }
}

impl<'s> AsRef<str> for PkgId<'s> {
    fn as_ref(&self) -> &str {
        match self {
            PkgId::Original(p) => p.repr.as_str(),
            PkgId::Modified(p) => p.as_str(),
        }
    }
}

impl<'s> Serialize for PkgId<'s> {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer {
        serializer.serialize_str(self.as_ref())
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Common<'s> {
    manifest_path: &'s Path,
    version: String,
    authors: Option<String>,
    pname: &'s str,
    description: Option<&'s str>,
    homepage: Option<&'s str>,
    repository: Option<&'s str>,
    license: Option<&'s str>,
    license_file: Option<&'s Path>,
    rust_version: Option<String>,
    readme: Option<&'s Path>,
    target: &'s str,
    features: &'s Vec<FeatureName>,
    all_features: Vec<&'s String>,
    edition: Edition,
    main_workspace: bool,
}

impl<'s> Common<'s> {
    fn from_package(
        package: &'s Package,
        node: &'s Node,
        project_dir: &Path,
        vendor_dir: &Path,
        target: &'s str,
    ) -> Result<Self> {
        Ok(Self {
            manifest_path: make_relative(
                package.manifest_path.as_std_path(),
                project_dir,
                vendor_dir,
            )?,
            version: package.version.to_string(),
            authors: if package.authors.is_empty() {
                None
            } else {
                Some(package.authors.join(":"))
            },
            pname: &package.name,
            description: package.description.as_deref(),
            homepage: package.homepage.as_deref(),
            repository: package.repository.as_deref(),
            license: package.repository.as_deref(),
            license_file: if let Some(file) = package.license_file.as_ref() {
                Some(make_relative(file.as_std_path(), project_dir, vendor_dir)?)
            } else {
                None
            },
            rust_version: package.rust_version.as_ref().map(ToString::to_string),
            readme: if let Some(file) = package.readme.as_ref() {
                Some(make_relative(file.as_std_path(), project_dir, vendor_dir)?)
            } else {
                None
            },
            target,
            features: &node.features,
            all_features: package.features.keys().collect(),
            edition: package.edition,
            main_workspace: package.source.is_none(),
        })
    }
}

#[derive(Debug, Serialize, Clone)]
struct Dep<'s> {
    name: &'s str,
    pkg: PkgId<'s>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CompileJobCommon<'s> {
    target_name: &'s str,
    crate_name: String,
    deps: Vec<Dep<'s>>,
    crate_type: &'static str,
    entrypoint: &'s Path,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CompileJobBuildScript<'s> {
    main_deps: Vec<Dep<'s>>,
    main_crate_name: String,
    #[serde(flatten)]
    common: CompileJobCommon<'s>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ResolvedPackage<'s> {
    common: Common<'s>,
    build_script: Option<CompileJobBuildScript<'s>>,
    rust_lib: Option<CompileJobCommon<'s>>,
    c_lib: Option<CompileJobCommon<'s>>,
    bins: Option<Vec<CompileJobCommon<'s>>>,
}

fn make_crate_name(name: &str) -> String {
    name.replace("-", "_")
}

impl<'s> ResolvedPackage<'s> {
    fn from_package(
        package: &'s Package,
        node: &'s Node,
        project_dir: &Path,
        vendor_dir: &Path,
        target: &'s str,
    ) -> Result<Self> {
        let mut build_deps: Vec<Dep> = vec![];
        let mut deps: Vec<Dep> = vec![];
        for dep in &node.deps {
            let d = Dep {
                name: &dep.name,
                pkg: PkgId::new(&dep.pkg, project_dir) ,
            };
            for kind in &dep.dep_kinds {
                match kind.kind {
                    cargo_metadata::DependencyKind::Normal => deps.push(d.clone()),
                    cargo_metadata::DependencyKind::Build => build_deps.push(d.clone()),
                    _ => {}
                }
            }
        }
        let common = Common::from_package(package, node, project_dir, vendor_dir, target)
            .context("collecting commmon metadata")?;
        let mut build_script = None;
        let mut rust_lib = None;
        let mut c_lib = None;
        let mut bins = Vec::new();

        for target in &package.targets {
            if target.name == "build-script-build" {
                if target.kind != [TargetKind::CustomBuild] {
                    bail!("build script has wrong target kind {:?}", target.kind)
                }
                if target.crate_types != [CrateType::Bin] {
                    bail!("build script has wrong crate type {:?}", target.crate_types)
                }
                let script = CompileJobBuildScript {
                    main_deps: deps.clone(),
                    main_crate_name: make_crate_name(&package.name),
                    common: CompileJobCommon {
                        crate_name: "build_script_build".to_string(),
                        deps: build_deps.clone(),
                        crate_type: "bin",
                        target_name: &target.name,
                        entrypoint: make_relative(
                            target.src_path.as_std_path(),
                            project_dir,
                            vendor_dir,
                        )?,
                    },
                };
                if build_script.replace(script).is_some() {
                    bail!("more than one buildscript in crate")
                }
            } else if target.kind.contains(&TargetKind::Lib)
                && target.crate_types.contains(&CrateType::Lib)
            {
                if c_lib.is_some() {
                    bail!("already clib")
                }
                let job = CompileJobCommon {
                    crate_name: make_crate_name(&target.name),
                    deps: deps.clone(),
                    crate_type: "lib",
                    target_name: &target.name,
                    entrypoint: make_relative(
                        target.src_path.as_std_path(),
                        project_dir,
                        vendor_dir,
                    )?,
                };
                if rust_lib.replace(job).is_some() {
                    bail!("more than one lib in crate")
                }
            } else if target.kind.contains(&TargetKind::ProcMacro)
                && target.crate_types.contains(&CrateType::ProcMacro)
            {
                if c_lib.is_some() {
                    bail!("already clib")
                }
                let job = CompileJobCommon {
                    crate_name: make_crate_name(&target.name),
                    deps: deps.clone(),
                    target_name: &target.name,
                    crate_type: "proc-macro",
                    entrypoint: make_relative(
                        target.src_path.as_std_path(),
                        project_dir,
                        vendor_dir,
                    )?,
                };
                if rust_lib.replace(job).is_some() {
                    bail!("more than one lib in crate")
                }
            } else if target.kind.contains(&TargetKind::CDyLib)
                && target.crate_types.contains(&CrateType::CDyLib)
            {
                if rust_lib.is_some() {
                    bail!("already rust lib")
                }
                if !bins.is_empty() {
                    bail!("already bin")
                }
                let job = CompileJobCommon {
                    crate_name: make_crate_name(&target.name),
                    deps: deps.clone(),
                    target_name: &target.name,
                    crate_type: "cdylib",
                    entrypoint: make_relative(
                        target.src_path.as_std_path(),
                        project_dir,
                        vendor_dir,
                    )?,
                };
                if c_lib.replace(job).is_some() {
                    bail!("more than one clib in crate")
                }
            } else if target.kind.contains(&TargetKind::Bin)
                && target.crate_types.contains(&CrateType::Bin)
            {
                if c_lib.is_some() {
                    bail!("already clib")
                }
                let job = CompileJobCommon {
                    crate_name: make_crate_name(&target.name),
                    deps: deps.clone(),
                    target_name: &target.name,
                    crate_type: "bin",
                    entrypoint: make_relative(
                        target.src_path.as_std_path(),
                        project_dir,
                        vendor_dir,
                    )?,
                };
                bins.push(job);
            }
        }

        Ok(Self {
            common,
            build_script,
            rust_lib,
            c_lib,
            bins: if bins.is_empty() { None } else { Some(bins) },
        })
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Output<'s> {
    packages: HashMap<PkgId<'s>, ResolvedPackage<'s>>,
    workspace: HashMap<&'s str, PkgId<'s>>,
    main_package: Option<PkgId<'s>>,
}

fn make_relative<'s>(path: &'s Path, project_dir: &Path, vendor_dir: &Path) -> Result<&'s Path> {
    if path.is_relative() {
        Ok(path)
    } else if let Ok(path) = path.strip_prefix(project_dir) {
        Ok(path)
    } else if let Ok(path) = path.strip_prefix(vendor_dir) {
        let packet_dir = path.components().next().ok_or_eyre("no prefix")?;
        path.strip_prefix(packet_dir)
            .context("stripping prefix we just got")
    } else {
        Err(eyre!(
            "path {} is not part of project or vendor dir",
            path.display()
        ))
    }
}

pub fn run(project_dir: PathBuf, vendor_dir: PathBuf, target: String, out: PathBuf) -> Result<()> {
    let features = env::var("features").unwrap_or_default();
    let no_default_features = env::var("noDefaultFeatures")
        .map(|v| v == "1")
        .unwrap_or(false);

    let mut command = MetadataCommand::new();

    if no_default_features {
        command.features(CargoOpt::NoDefaultFeatures);
    }
    if !features.is_empty() {
        command.features(CargoOpt::SomeFeatures(
            features.split_whitespace().map(str::to_string).collect(),
        ));
    }
    let mut vendor_config = vendor_dir.clone();
    vendor_config.push("config.toml");
    let vendor_config = vendor_config.to_string_lossy().into_owned();

    let metadata = command
        .other_options(vec![
            "--frozen".to_string(),
            "--config".to_string(),
            vendor_config,
            "--filter-platform".to_string(),
            target.clone(),
        ])
        .current_dir(&project_dir)
        .exec()
        .context("collecting metadata")?;
    let packages: HashMap<&PackageId, &Package> =
        metadata.packages.iter().map(|p| (&p.id, p)).collect();
    let workspace_members: HashMap<&str, PkgId> = metadata
        .workspace_members
        .iter()
        .map(|p| -> Result<_> {
            Ok((
                packages.get(p).ok_or_eyre("unknown package")?.name.as_str(),
                PkgId::new(p, &project_dir),
            ))
        })
        .collect::<Result<_>>()?;
    let resolve = metadata.resolve.ok_or_eyre("no resolve in metadata")?;
    let main_package = resolve.root.as_ref().map(|p|PkgId::new(p, &project_dir));
    let mut ready_packages: HashMap<PkgId, ResolvedPackage> = HashMap::new();
    for node in &resolve.nodes {
        let id = PkgId::new(&node.id, &project_dir);
        let package = *packages
            .get(&node.id)
            .ok_or_eyre("getting package for resolve node")?;
        ready_packages.insert(
            id,
            ResolvedPackage::from_package(package, node, &project_dir, &vendor_dir, &target)
                .with_context(|| format!("resolving package {}", &node.id))?,
        );
    }
    fs::write(
        out,
        serde_json::to_string(&Output {
            packages: ready_packages,
            workspace: workspace_members,
            main_package,
        })
        .context("serializing output")?,
    )
    .context("writing output")?;
    Ok(())
}
