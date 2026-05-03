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
/// Homebrew formula name. The Cellar path layout is
/// `<prefix>/Cellar/<FORMULA_NAME>/<version>/bin/<BIN_NAME>`.
const FORMULA_NAME: &str = "bruto-pascal";
const API_TIMEOUT: Duration = Duration::from_secs(2);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(120);

/// How brutop was installed, detected from the running binary's path.
/// We dispatch on this when replacing the binary so brew/scoop metadata
/// stay in sync with the new version.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InstallMethod {
    Brew,
    Scoop,
    Cargo,
    Unknown,
}

fn detect_install_method() -> InstallMethod {
    let Ok(exe) = std::env::current_exe() else { return InstallMethod::Unknown };
    let path = exe.to_string_lossy();
    if path.contains(".cargo/bin") || path.contains(".cargo\\bin") {
        InstallMethod::Cargo
    } else if path.contains("/homebrew/") || path.contains("/Cellar/") {
        InstallMethod::Brew
    } else if path.contains("\\scoop\\") || path.contains("/scoop/") {
        InstallMethod::Scoop
    } else {
        InstallMethod::Unknown
    }
}

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
    let method = detect_install_method();
    let result = replace_binary(&tmp, method, version);
    let _ = std::fs::remove_file(&tmp);
    result
}

/// Dispatch the binary swap to the strategy that matches how brutop was
/// installed. Each strategy keeps the package manager's metadata in sync
/// so `brew info bruto-pascal` / `scoop status brutop` report the new
/// version after the upgrade.
fn replace_binary(new_exe: &Path, method: InstallMethod, new_version: &str) -> Result<(), String> {
    match method {
        InstallMethod::Brew => replace_for_brew(new_exe, new_version),
        InstallMethod::Scoop => replace_for_scoop(new_exe, new_version),
        InstallMethod::Cargo | InstallMethod::Unknown => replace_default(new_exe),
    }
}

fn replace_default(new_exe: &Path) -> Result<(), String> {
    // self_replace resolves symlinks via fs::read_link, which can return
    // relative targets (Homebrew always does this). When that happens
    // subsequent operations resolve the path from CWD instead of the
    // symlink's parent, which fails. Canonicalising up-front sidesteps it.
    #[cfg(unix)]
    {
        let exe = std::env::current_exe().ok();
        let canonical = exe.as_ref().and_then(|e| e.canonicalize().ok());
        if let (Some(exe), Some(ref canonical)) = (&exe, canonical) {
            if exe.as_path() != canonical.as_path() {
                return install_binary(new_exe, canonical);
            }
        }
    }
    self_replace::self_replace(new_exe)
        .map_err(|e| format!("binary replacement failed: {e}"))
}

/// Atomic replace by copying into a sibling temp path, chmod+x, and
/// renaming over the target. Avoids ETXTBSY on Linux (rename swaps the
/// directory entry rather than writing into the running executable).
#[cfg(unix)]
fn install_binary(src: &Path, target: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    let dir = target
        .parent()
        .ok_or_else(|| "cannot determine target directory".to_string())?;
    let temp = dir.join(format!(".brutop_upgrade_{}", std::process::id()));
    std::fs::copy(src, &temp).map_err(|e| format!("cannot copy new binary: {e}"))?;
    std::fs::set_permissions(&temp, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("cannot set permissions: {e}"))?;
    if let Err(e) = std::fs::rename(&temp, target) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("cannot replace binary: {e}"));
    }
    Ok(())
}

#[cfg(not(unix))]
fn install_binary(_src: &Path, _target: &Path) -> Result<(), String> {
    Err("install_binary not implemented on this platform".into())
}

// ── Homebrew ────────────────────────────────────────────────────────────

#[cfg(unix)]
fn replace_for_brew(new_exe: &Path, new_version: &str) -> Result<(), String> {
    let exe = std::env::current_exe()
        .map_err(|e| format!("cannot determine current exe: {e}"))?;
    let canonical = exe
        .canonicalize()
        .map_err(|e| format!("cannot resolve binary path: {e}"))?;

    // Validate Cellar layout: <prefix>/Cellar/<formula>/<version>/bin/<binary>
    let bin_dir = match canonical.parent() {
        Some(p) if p.file_name().and_then(|n| n.to_str()) == Some("bin") => p,
        _ => return replace_default(new_exe),
    };
    let Some(version_dir) = bin_dir.parent() else { return replace_default(new_exe) };
    let Some(formula_dir) = version_dir.parent() else { return replace_default(new_exe) };
    let cellar_dir = match formula_dir.parent() {
        Some(p) if p.file_name().and_then(|n| n.to_str()) == Some("Cellar") => p,
        _ => return replace_default(new_exe),
    };
    let Some(prefix) = cellar_dir.parent() else { return replace_default(new_exe) };

    let Some(bin_name) = canonical.file_name() else { return replace_default(new_exe) };
    let Some(old_version_os) = version_dir.file_name() else { return replace_default(new_exe) };
    let old_version = old_version_os.to_string_lossy().to_string();

    // Step 1 (critical): atomic binary swap inside the Cellar.
    install_binary(new_exe, &canonical)?;

    // Steps 2-4 update Cellar metadata so `brew` reports the new version.
    // Best-effort: failures here just leave brew slightly out-of-date.
    if old_version != new_version {
        let new_version_dir = formula_dir.join(new_version);

        if std::fs::rename(version_dir, &new_version_dir).is_ok() {
            // Update <prefix>/bin/<binary> symlink.
            let symlink_path = prefix.join("bin").join(bin_name);
            if let Ok(meta) = std::fs::symlink_metadata(&symlink_path) {
                if meta.file_type().is_symlink() {
                    if let Ok(old_target) = std::fs::read_link(&symlink_path) {
                        let new_target = std::path::PathBuf::from(
                            old_target
                                .to_string_lossy()
                                .replacen(&old_version, new_version, 1),
                        );
                        let _ = std::fs::remove_file(&symlink_path);
                        let _ = std::os::unix::fs::symlink(&new_target, &symlink_path);
                    }
                }
            }

            // Patch INSTALL_RECEIPT.json so `brew info` is accurate.
            let receipt = new_version_dir.join("INSTALL_RECEIPT.json");
            if receipt.exists() {
                if let Ok(text) = std::fs::read_to_string(&receipt) {
                    let _ = std::fs::write(&receipt, text.replace(&old_version, new_version));
                }
            }
        }
    }

    // FORMULA_NAME is unused by this code path right now (we discover the
    // formula directory by walking up from the binary). Keep the constant
    // visible as a single source of truth for any future Cellar work.
    let _ = FORMULA_NAME;
    Ok(())
}

#[cfg(not(unix))]
fn replace_for_brew(new_exe: &Path, _new_version: &str) -> Result<(), String> {
    replace_default(new_exe)
}

// ── Scoop ───────────────────────────────────────────────────────────────

#[cfg(windows)]
fn replace_for_scoop(new_exe: &Path, new_version: &str) -> Result<(), String> {
    self_replace::self_replace(new_exe)
        .map_err(|e| format!("binary replacement failed: {e}"))?;
    update_scoop_metadata(new_version);
    Ok(())
}

#[cfg(windows)]
fn update_scoop_metadata(new_version: &str) {
    let Ok(exe) = std::env::current_exe() else { return };
    let canonical = exe.canonicalize().unwrap_or(exe);
    let Some(version_dir) = find_scoop_version_dir(&canonical) else { return };
    let Some(app_dir) = version_dir.parent() else { return };
    let old_version = version_dir
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_default();
    if old_version == new_version || old_version == "current" {
        return;
    }

    let new_version_dir = app_dir.join(new_version);
    if std::fs::create_dir_all(&new_version_dir).is_err() { return }

    // Copy the old version directory's metadata files into the new one.
    if let Ok(entries) = std::fs::read_dir(&version_dir) {
        for entry in entries.flatten() {
            if !entry.file_type().map(|t| t.is_file()).unwrap_or(false) {
                continue;
            }
            let name = entry.file_name();
            if name.to_string_lossy().contains("__self_delete__") { continue }
            let _ = std::fs::copy(entry.path(), new_version_dir.join(&name));
        }
    }

    // Patch the manifest.
    let manifest = new_version_dir.join("manifest.json");
    if manifest.exists() {
        if let Ok(text) = std::fs::read_to_string(&manifest) {
            let _ = std::fs::write(&manifest, text.replace(&old_version, new_version));
        }
    }

    // Re-point the `current` junction.
    let current = app_dir.join("current");
    let _ = std::fs::remove_dir(&current);
    use std::os::windows::process::CommandExt;
    let _ = std::process::Command::new("cmd")
        .args([
            "/c", "mklink", "/J",
            &current.to_string_lossy(),
            &new_version_dir.to_string_lossy(),
        ])
        .creation_flags(0x08000000) // CREATE_NO_WINDOW
        .status();
}

/// Walk the canonical path looking for `<scoop>/apps/<app>/<version>/…`.
#[cfg(windows)]
fn find_scoop_version_dir(path: &Path) -> Option<PathBuf> {
    let mut found_apps = false;
    let mut depth_after_apps = 0u8;
    let mut result = PathBuf::new();
    for comp in path.components() {
        result.push(comp);
        if found_apps {
            depth_after_apps += 1;
            if depth_after_apps == 2 {
                return Some(result);
            }
        } else if let std::path::Component::Normal(name) = comp {
            if name.to_string_lossy().eq_ignore_ascii_case("apps") {
                found_apps = true;
            }
        }
    }
    None
}

#[cfg(not(windows))]
fn replace_for_scoop(new_exe: &Path, _new_version: &str) -> Result<(), String> {
    replace_default(new_exe)
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
