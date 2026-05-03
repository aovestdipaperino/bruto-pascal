//! Self-update flow for bruto-pascal.
//!
//! Mirrors tokensave's mechanics:
//! 1. Hit GitHub's "latest release" API with a 2 second timeout.
//! 2. If the tag is newer than `CARGO_PKG_VERSION`, pop a Y/N dialog.
//! 3. On Yes, download the platform tar.gz from the release, extract the
//!    `brutop` binary, replace the running executable via `self_replace`,
//!    and re-exec the new one so the user lands back in the IDE.
//!
//! Failures are silent at the API check (so the IDE never blocks on a
//! flaky network) and surface as a message-box only after the user has
//! explicitly accepted the upgrade.

use std::path::{Path, PathBuf};
use std::time::Duration;

use turbo_vision::app::Application;
use turbo_vision::core::command::CM_YES;
use turbo_vision::views::msgbox::{
    confirmation_box_yes_no, message_box_error, message_box_ok,
};

const REPO: &str = "aovestdipaperino/bruto-pascal";
const BIN_NAME: &str = "brutop";
const API_TIMEOUT: Duration = Duration::from_secs(2);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(120);

/// Entry point — runs the whole flow when called from the IDE's
/// on_desktop_ready hook. No-op for `cargo run` builds (binary lives in
/// `target/`); also no-op when the version check times out or fails.
pub fn check_and_prompt(app: &mut Application) {
    if running_from_target_dir() {
        return;
    }

    let current = env!("CARGO_PKG_VERSION");
    let Some(latest) = fetch_latest_version() else { return };
    if !is_newer(current, &latest) {
        return;
    }

    let prompt = format!(
        "A new version of bruto-pascal is available.\n\n\
         Current: {current}\nLatest:  {latest}\n\n\
         Upgrade and restart now?",
    );
    if confirmation_box_yes_no(app, &prompt) != CM_YES {
        return;
    }

    if let Err(e) = perform_upgrade(&latest) {
        message_box_error(app, &format!("Upgrade failed:\n{e}"));
        return;
    }

    message_box_ok(
        app,
        &format!("bruto-pascal v{latest} installed.\n\nThe IDE will now restart."),
    );
    restart_ide();
}

/// Skip the flow when running out of a Cargo build directory — replacing
/// `target/debug/brutop` with a release tarball would be both surprising
/// and useless (next `cargo run` would put the dev binary right back).
fn running_from_target_dir() -> bool {
    let Ok(exe) = std::env::current_exe() else { return true };
    let s = exe.to_string_lossy();
    s.contains("/target/") || s.contains("\\target\\")
}

/// Hit `releases/latest` with a 2s budget. Anything that fails returns
/// `None` so the IDE never blocks on the network.
fn fetch_latest_version() -> Option<String> {
    #[derive(serde::Deserialize)]
    struct Release {
        tag_name: String,
    }

    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(API_TIMEOUT))
        .build()
        .into();

    let url = format!("https://api.github.com/repos/{REPO}/releases/latest");
    let release: Release = agent
        .get(&url)
        .header("User-Agent", "brutop")
        .call()
        .ok()?
        .body_mut()
        .read_json()
        .ok()?;

    Some(release.tag_name.trim_start_matches('v').to_string())
}

/// True if `latest` semver-newer than `current`. Pre-release suffixes
/// (e.g. `1.0.0-beta.1`) split into separate channels — we don't suggest
/// crossing them.
fn is_newer(current: &str, latest: &str) -> bool {
    fn parse(v: &str) -> Option<(u64, u64, u64, Option<&str>)> {
        let (base, pre) = match v.split_once('-') {
            Some((b, p)) => (b, Some(p)),
            None => (v, None),
        };
        let mut parts = base.split('.');
        let major = parts.next()?.parse().ok()?;
        let minor = parts.next()?.parse().ok()?;
        let patch = parts.next()?.parse().ok()?;
        Some((major, minor, patch, pre))
    }

    match (parse(current), parse(latest)) {
        (Some((cm, cn, cp, cpre)), Some((lm, ln, lp, lpre))) => {
            if cpre.is_some() != lpre.is_some() {
                return false;
            }
            if (lm, ln, lp) != (cm, cn, cp) {
                return (lm, ln, lp) > (cm, cn, cp);
            }
            match (cpre, lpre) {
                (Some(a), Some(b)) => b > a,
                _ => false,
            }
        }
        _ => false,
    }
}

fn perform_upgrade(version: &str) -> Result<(), String> {
    let asset = asset_name(version);
    let url = fetch_asset_url(version, &asset)?;
    let tmp = download_and_extract(&url)?;
    self_replace::self_replace(&tmp).map_err(|e| format!("binary replacement failed: {e}"))?;
    let _ = std::fs::remove_file(&tmp);
    Ok(())
}

/// Matches the release workflow's archive convention:
/// `bruto-pascal-v{version}-aarch64-macos.tar.gz`.
fn asset_name(version: &str) -> String {
    let platform = current_platform();
    format!("bruto-pascal-v{version}-{platform}.tar.gz")
}

fn current_platform() -> &'static str {
    if cfg!(target_os = "macos") && cfg!(target_arch = "aarch64") {
        "aarch64-macos"
    } else if cfg!(target_os = "macos") && cfg!(target_arch = "x86_64") {
        "x86_64-macos"
    } else if cfg!(target_os = "linux") && cfg!(target_arch = "x86_64") {
        "x86_64-linux"
    } else if cfg!(target_os = "linux") && cfg!(target_arch = "aarch64") {
        "aarch64-linux"
    } else {
        "unknown"
    }
}

fn fetch_asset_url(version: &str, expected: &str) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct Asset {
        name: String,
        browser_download_url: String,
    }
    #[derive(serde::Deserialize)]
    struct Release {
        assets: Vec<Asset>,
    }

    let url = format!(
        "https://api.github.com/repos/{REPO}/releases/tags/v{version}",
    );
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(DOWNLOAD_TIMEOUT))
        .build()
        .into();

    let release: Release = agent
        .get(&url)
        .header("User-Agent", "brutop")
        .call()
        .map_err(|e| format!("failed to reach GitHub: {e}"))?
        .body_mut()
        .read_json()
        .map_err(|e| format!("failed to parse release info: {e}"))?;

    release
        .assets
        .into_iter()
        .find(|a| a.name == expected)
        .map(|a| a.browser_download_url)
        .ok_or_else(|| {
            format!(
                "release v{version} exists but '{expected}' is not yet available — \
                 CI may still be in progress.",
            )
        })
}

fn download_and_extract(url: &str) -> Result<PathBuf, String> {
    use std::io::Read;

    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(DOWNLOAD_TIMEOUT))
        .build()
        .into();

    let mut buf = Vec::new();
    agent
        .get(url)
        .header("User-Agent", "brutop")
        .call()
        .map_err(|e| format!("download failed: {e}"))?
        .body_mut()
        .as_reader()
        .read_to_end(&mut buf)
        .map_err(|e| format!("download read failed: {e}"))?;

    let dest = std::env::temp_dir().join(format!("brutop_upgrade_{}", std::process::id()));
    extract_tar_gz(&buf, BIN_NAME, &dest)?;
    Ok(dest)
}

fn extract_tar_gz(data: &[u8], bin_name: &str, dest: &Path) -> Result<(), String> {
    use flate2::read::GzDecoder;
    use std::io::Cursor;
    use tar::Archive;

    let gz = GzDecoder::new(Cursor::new(data));
    let mut archive = Archive::new(gz);
    for entry in archive.entries().map_err(|e| format!("archive open failed: {e}"))? {
        let mut entry = entry.map_err(|e| format!("archive read failed: {e}"))?;
        let path = entry
            .path()
            .map_err(|e| format!("archive path error: {e}"))?
            .to_path_buf();
        if path.file_name().and_then(|n| n.to_str()) == Some(bin_name) {
            entry
                .unpack(dest)
                .map_err(|e| format!("extract failed: {e}"))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let mut perms = std::fs::metadata(dest)
                    .map_err(|e| format!("stat failed: {e}"))?
                    .permissions();
                perms.set_mode(0o755);
                std::fs::set_permissions(dest, perms)
                    .map_err(|e| format!("chmod failed: {e}"))?;
            }
            return Ok(());
        }
    }
    Err(format!("'{bin_name}' not found in archive"))
}

/// Spawn the freshly installed binary with the same argv and exit so the
/// user lands back in the IDE on the new version. On Unix we use `execv`
/// to replace the process image (preserves the terminal cleanly); on
/// other platforms we spawn + exit.
fn restart_ide() {
    let exe = match std::env::current_exe() {
        Ok(p) => p,
        Err(_) => std::process::exit(0),
    };
    let args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        let _ = std::process::Command::new(&exe).args(&args).exec();
        // `exec` only returns on failure — fall through to exit so we
        // don't leave the user in the (now-stale) running process.
    }

    #[cfg(not(unix))]
    {
        let _ = std::process::Command::new(&exe).args(&args).spawn();
    }

    std::process::exit(0);
}
