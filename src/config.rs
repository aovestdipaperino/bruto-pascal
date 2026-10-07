use std::path::{Path, PathBuf};

use bruto_lang::language::{BuildOptions, BuildProfile, OptimizeFor};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub show_about_dialog_on_start: bool,
    pub build: BuildConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            show_about_dialog_on_start: true,
            build: BuildConfig::default(),
        }
    }
}

/// `[build]` table: the IDE's Build Options, stored as plain strings so a
/// hand-edited or unknown value falls back to the default instead of
/// making the whole file unreadable.
#[derive(Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct BuildConfig {
    /// `"debug"` or `"retail"`.
    pub mode: String,
    /// `"size"`, `"both"` or `"speed"`.
    pub optimize: String,
    /// Enable code obfuscation during the build process.
    pub obfuscation: bool,
}

impl Default for BuildConfig {
    fn default() -> Self {
        Self::from(&BuildOptions::default())
    }
}

impl From<&BuildOptions> for BuildConfig {
    fn from(o: &BuildOptions) -> Self {
        Self {
            mode: o.profile.as_str().to_string(),
            optimize: o.optimize.as_str().to_string(),
            obfuscation: o.obfuscate,
        }
    }
}

impl BuildConfig {
    pub fn to_options(&self) -> BuildOptions {
        BuildOptions {
            profile: BuildProfile::parse(&self.mode).unwrap_or_default(),
            optimize: OptimizeFor::parse(&self.optimize).unwrap_or_default(),
            obfuscate: self.obfuscation,
        }
    }
}

impl Config {
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|text| toml::from_str(&text).ok())
            .unwrap_or_default()
    }

    /// Load, apply `f`, and write back — so changing one setting never
    /// drops the others.
    pub fn update(path: &Path, f: impl FnOnce(&mut Config)) -> std::io::Result<()> {
        let mut cfg = Self::load(path);
        f(&mut cfg);
        cfg.save(path)
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let text = toml::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        std::fs::write(path, text)
    }
}

pub fn config_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("bruto-pascal").join("config.toml")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_build_table_uses_defaults() {
        let cfg: Config = toml::from_str("show_about_dialog_on_start = false\n").unwrap();
        assert_eq!(cfg.build.to_options(), BuildOptions::default());
    }

    #[test]
    fn build_table_round_trips() {
        let opts = BuildOptions {
            profile: BuildProfile::Retail,
            optimize: OptimizeFor::Speed,
            obfuscate: true,
        };
        let cfg = Config {
            show_about_dialog_on_start: false,
            build: BuildConfig::from(&opts),
        };
        let text = toml::to_string_pretty(&cfg).unwrap();
        let back: Config = toml::from_str(&text).unwrap();
        assert_eq!(back.build.to_options(), opts);
    }

    #[test]
    fn unknown_values_fall_back_to_defaults() {
        let cfg: Config =
            toml::from_str("[build]\nmode = \"turbo\"\noptimize = \"fast\"\n").unwrap();
        assert_eq!(cfg.build.to_options(), BuildOptions::default());
    }
}
