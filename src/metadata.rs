use cargo_metadata::{
    CargoOpt, CrateType, DependencyKind, Edition, FeatureName, Metadata, Node, Package, PackageId,
    PackageName, TargetKind,
    camino::{Utf8Component, Utf8Path, Utf8PathBuf},
};
use color_eyre::{
    Result,
    eyre::{Context, OptionExt, bail},
};
use serde::{Deserialize, Serialize};
use std::{
    borrow::Cow,
    collections::{BTreeMap, HashMap},
    fs,
    path::Path,
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Options {
    vendor_dir: Utf8PathBuf,
    src: Utf8PathBuf,
    target: String,
    no_default_features: bool,
    features: Vec<String>,
}

#[derive(Serialize, Clone, PartialEq, Eq, PartialOrd, Ord)]
#[serde(transparent)]
struct OutputPackageId {
    id: String,
}

#[derive(Serialize)]
#[serde(transparent)]
struct OutputPath {
    path: Utf8PathBuf,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Output {
    main_package: Option<OutputPackageId>,
    workspace_members: BTreeMap<PackageName, OutputPackageId>,
    packages: BTreeMap<OutputPackageId, OutputPackage>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OutputPackage {
    common: PackageCommon,
    #[serde(skip_serializing_if = "Option::is_none")]
    build_script: Option<BuildScript>,
    #[serde(skip_serializing_if = "Option::is_none")]
    rust_lib: Option<Job>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    bins: Vec<Job>,
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PackageCommon {
    manifest_path: OutputPath,
    version: String,
    pname: String,
    description: Option<String>,
    readme: Option<OutputPath>,
    authors: Vec<String>,
    long_description: Option<String>,
    homepage: Option<String>,
    repository: Option<String>,
    license: Option<String>,
    license_file: Option<OutputPath>,
    rust_version: Option<String>,
    target: String,
    features: Vec<FeatureName>,
    all_features: Vec<String>,
    main_workspace: bool,
    links: Option<String>,
    crate_name: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BuildScript {
    main_deps: Vec<OutputDep>,
    #[serde(flatten)]
    job: Job,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Job {
    deps: Vec<OutputDep>,
    crate_type: CrateType,
    target_name: Cow<'static, str>,
    entrypoint: OutputPath,
    edition: Edition,
}

#[derive(Serialize, Clone)]
struct OutputDep {
    name: String,
    pkg: OutputPackageId,
}

pub fn metadata(options: &Path, out: &Path) -> Result<()> {
    let options: Options = serde_json::from_slice(&fs::read(options)?)?;
    let metadata = collect_metadata(&options)?;
    let pkg_map: HashMap<_, _> = metadata
        .packages
        .iter()
        .map(|p| (p.id.clone(), p.clone()))
        .collect();
    let src = options.src.clone().into_string();
    let resolve = metadata.resolve.ok_or_eyre("missing resolved packages")?;
    let main_package = resolve.root.as_ref().map(|id| mk_pkg_id(id, &src));
    let workspace_members = metadata
        .workspace_members
        .into_iter()
        .map(|id| {
            (
                pkg_map.get(&id).expect("no such package").name.clone(),
                mk_pkg_id(&id, &src),
            )
        })
        .collect();
    let mut packages = BTreeMap::new();
    for node in resolve.nodes {
        let package = pkg_map.get(&node.id).ok_or_eyre("node without package")?;
        let (key, value) = mk_package_def(
            node,
            package,
            &src,
            &options.src,
            &options.vendor_dir,
            &options.target,
        )?;
        packages.insert(key, value);
    }
    fs::write(
        out,
        &serde_json::to_vec(&Output {
            main_package,
            workspace_members,
            packages,
        })?,
    )?;

    Ok(())
}

fn mk_pkg_id(id: &PackageId, src: &str) -> OutputPackageId {
    OutputPackageId {
        id: id.repr.replace(src, "source"),
    }
}

fn make_relative(path: &Utf8Path, src: &Utf8Path, vendor: &Utf8Path) -> Result<OutputPath> {
    let path = if path.starts_with(src) {
        path.strip_prefix(src)?.to_owned()
    } else if path.starts_with(vendor) {
        let dir = path.strip_prefix(vendor)?;
        let Utf8Component::Normal(dir_name) =
            dir.components().next().expect("should have vendor dir")
        else {
            bail!("path is not relative?")
        };
        dir.strip_prefix(dir_name)?.to_owned()
    } else {
        path.to_owned()
    };
    Ok(OutputPath { path })
}

fn collect_metadata(options: &Options) -> Result<Metadata> {
    let mut command = cargo_metadata::MetadataCommand::new();
    let vendor_cfg = options.vendor_dir.join("config.toml").into_string();
    command.other_options([
        "--frozen".to_owned(),
        "--filter-platform".to_owned(),
        options.target.clone(),
        "--config".to_owned(),
        vendor_cfg,
    ]);
    if options.no_default_features {
        command.features(CargoOpt::NoDefaultFeatures);
    }
    command.features(CargoOpt::SomeFeatures(options.features.clone()));
    command.current_dir(&options.src);
    command.verbose(true);
    command.exec().context("cargo metadata")
}

fn mk_package_def(
    node: Node,
    package: &Package,
    src: &str,
    src_path: &Utf8Path,
    vendor: &Utf8Path,
    target: &str,
) -> Result<(OutputPackageId, OutputPackage)> {
    let id = mk_pkg_id(&package.id, src);
    let common = PackageCommon {
        manifest_path: make_relative(&package.manifest_path, src_path, vendor)?,
        version: package.version.to_string(),
        pname: package.name.clone().into_inner(),
        description: package.description.clone(),
        readme: package
            .readme()
            .as_deref()
            .map(|readme| make_relative(readme, src_path, vendor))
            .transpose()?,
        authors: package.authors.clone(),
        long_description: package.readme().as_deref().and_then(|readme| {
            fs::read_to_string(readme.as_std_path())
                .inspect_err(|e| println!("warn: could not read readme file: {e:?}"))
                .ok()
        }),
        homepage: package.homepage.clone(),
        repository: package.repository.clone(),
        license: package.license.clone(),
        license_file: package
            .license_file()
            .as_deref()
            .map(|readme| make_relative(readme, src_path, vendor))
            .transpose()?,
        rust_version: package.rust_version.as_ref().map(|v| v.to_string()),
        target: target.to_owned(),
        features: node.features.clone(),
        all_features: package.features.keys().cloned().collect(),
        main_workspace: package.source.is_none(),
        links: package.links.clone(),
        crate_name: package.name.as_str().replace("-", "_"),
    };
    let mut deps = Vec::new();
    let mut deps_build = Vec::new();
    for dep in node.deps {
        for kind in dep.dep_kinds {
            match kind.kind {
                DependencyKind::Normal => {
                    deps.push(OutputDep {
                        name: dep.name.clone(),
                        pkg: mk_pkg_id(&dep.pkg, src),
                    });
                }
                DependencyKind::Build => {
                    deps_build.push(OutputDep {
                        name: dep.name.clone(),
                        pkg: mk_pkg_id(&dep.pkg, src),
                    });
                }
                _ => {}
            }
        }
    }
    let mut build_script = None;
    let mut rust_lib = None;
    let mut bins = Vec::new();

    for target in &package.targets {
        for kind in &target.kind {
            match kind {
                TargetKind::CustomBuild => {
                    if build_script.is_some() {
                        bail!("more than one build script")
                    } else if target.crate_types.contains(&CrateType::Bin) {
                        build_script = Some(BuildScript {
                            main_deps: deps.clone(),
                            job: Job {
                                deps: deps_build.clone(),
                                crate_type: CrateType::Bin,
                                target_name: "build_script".into(),
                                entrypoint: make_relative(&target.src_path, src_path, vendor)?,
                                edition: target.edition,
                            },
                        })
                    } else {
                        bail!("build script target must be of type bin")
                    }
                }
                TargetKind::Lib => {
                    if rust_lib.is_some() {
                        bail!("more than one library target")
                    } else if target.crate_types.contains(&CrateType::Lib) {
                        rust_lib = Some(Job {
                            deps: deps.clone(),
                            crate_type: CrateType::Lib,
                            target_name: target.name.clone().into(),
                            entrypoint: make_relative(&target.src_path, src_path, vendor)?,
                            edition: target.edition,
                        })
                    } else {
                        bail!("lib target must be of type lib")
                    }
                }
                TargetKind::ProcMacro => {
                    if rust_lib.is_some() {
                        bail!("more than one library target")
                    } else if target.crate_types.contains(&CrateType::ProcMacro) {
                        rust_lib = Some(Job {
                            deps: deps.clone(),
                            crate_type: CrateType::ProcMacro,
                            target_name: target.name.clone().into(),
                            entrypoint: make_relative(&target.src_path, src_path, vendor)?,
                            edition: target.edition,
                        })
                    } else {
                        bail!("proc_macro target must be of type proc_macro")
                    }
                }
                TargetKind::Bin => {
                    if target.crate_types.contains(&CrateType::Bin) {
                        bins.push(Job {
                            deps: deps.clone(),
                            crate_type: CrateType::Bin,
                            target_name: target.name.clone().into(),
                            entrypoint: make_relative(&target.src_path, src_path, vendor)?,
                            edition: target.edition,
                        })
                    } else {
                        bail!("bin target must be of type bin")
                    }
                }
                _ => {}
            }
        }
    }

    if rust_lib.is_some() && !bins.is_empty() {
        let dep = OutputDep {
            name: package.name.as_str().to_owned(),
            pkg: id.clone(),
        };
        for bin in &mut bins {
            bin.deps.push(dep.clone());
        }
    }
    Ok((
        id,
        OutputPackage {
            common,
            build_script,
            rust_lib,
            bins,
        },
    ))
}
