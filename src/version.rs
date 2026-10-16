use std::sync::LazyLock;

use regex::Regex;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Version {
    pub major: Option<String>,
    pub minor: Option<String>,
    pub patch: Option<String>,
    pub pre: Option<String>,
    pub meta: Option<String>,
}

static PATTERN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<pre>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<meta>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$").expect("creating regex failed")
});

impl Version {
    pub fn from_str(from: &str) -> Option<Self> {
        PATTERN.captures(from).map(|m| Version {
            major: m.name("major").map(|v| v.as_str().to_string()),
            minor: m.name("minor").map(|v| v.as_str().to_string()),
            patch: m.name("patch").map(|v| v.as_str().to_string()),
            pre: m.name("pre").map(|v| v.as_str().to_string()),
            meta: m.name("meta").map(|v| v.as_str().to_string()),
        })
    }
}
