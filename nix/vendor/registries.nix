{
  mkStandardCrateRegistry =
    dl:
    {
      name,
      version,
      checksum,
    }:
    "${dl}/${name}/${version}/download";
  defaultCrateRegistries =
    { mkStandardCrateRegistry }:
    {
      "https://github.com/rust-lang/crates.io-index" =
        mkStandardCrateRegistry "https://crates.io/api/v1/crates";
    };
}
