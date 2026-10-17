//! Updates to Aikatsu itself, from its GitHub releases. `check` compares the
//! latest release with this build; `install` downloads the file that updates
//! this copy, checks its SHA-256 and hands it to the platform's installer.

use crate::{http, push};
use anyhow::{Context, Result, anyhow, ensure};
use futures_util::StreamExt;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::AsyncWriteExt;

const LATEST: &str = "https://api.github.com/repos/KidiXDev/aikatsu/releases/latest";
const CURRENT: &str = env!("CARGO_PKG_VERSION");

/// How this copy was installed, which decides the file that updates it.
enum Install {
    /// The Windows setup.exe, which leaves uninstall.exe beside aikatsu.exe.
    WindowsSetup,
    /// The AppImage runtime puts the file's own path in `$APPIMAGE`.
    AppImage(PathBuf),
    Android,
    /// The Windows ZIP or a build from source: updated by hand from the release page.
    Manual,
}

fn this_install() -> Install {
    if cfg!(target_os = "android") {
        Install::Android
    } else if cfg!(windows) && std::env::current_exe().is_ok_and(|exe| exe.with_file_name("uninstall.exe").is_file()) {
        Install::WindowsSetup
    } else if let Some(path) = std::env::var_os("APPIMAGE").filter(|_| cfg!(target_os = "linux")) {
        Install::AppImage(path.into())
    } else {
        Install::Manual
    }
}

/// The end of the release file's name, as .github/workflows/release.yml names them.
fn asset_suffix(install: &Install) -> Option<String> {
    let arch = std::env::consts::ARCH;
    match install {
        Install::WindowsSetup => Some("-windows-x64-setup.exe".into()),
        Install::AppImage(_) => Some(format!("-{arch}.AppImage")),
        // This process' ABI, so a 32-bit build on a 64-bit phone stays 32-bit.
        Install::Android => Some(format!("-android-{}.apk", match arch {
            "aarch64" => "arm64-v8a",
            "arm" => "armeabi-v7a",
            other => other,
        })),
        Install::Manual => None,
    }
}

struct Asset {
    name: String,
    url: String,
    size: u64,
    sha256: String,
}

struct Release {
    version: String,
    page: String,
    /// None when this copy can't update itself, or the file has no checksum to verify.
    asset: Option<Asset>,
}

fn parse(release: &Value, suffix: Option<&str>) -> Result<Release> {
    let tag = release["tag_name"].as_str().context("the latest release has no tag")?;
    let asset = suffix.and_then(|suffix| {
        let a = release["assets"].as_array()?.iter().find(|a| a["name"].as_str().is_some_and(|n| n.ends_with(suffix)))?;
        Some(Asset {
            name: a["name"].as_str()?.to_owned(),
            url: a["browser_download_url"].as_str()?.to_owned(),
            size: a["size"].as_u64()?,
            sha256: a["digest"].as_str()?.strip_prefix("sha256:")?.to_lowercase(),
        })
    });
    Ok(Release { version: tag.trim_start_matches('v').to_owned(), page: release["html_url"].as_str().unwrap_or_default().to_owned(), asset })
}

/// Numeric `MAJOR.MINOR.PATCH` only; anything else (a pre-release tag) is never newer.
fn newer(latest: &str, current: &str) -> bool {
    let parts = |v: &str| v.split('.').map(|p| p.parse::<u64>().ok()).collect::<Option<Vec<_>>>();
    matches!((parts(latest), parts(current)), (Some(l), Some(c)) if l > c)
}

async fn latest(install: &Install) -> Result<Release> {
    let rb = http::PLAIN.get(LATEST).header("User-Agent", http::API_UA).header("Accept", "application/vnd.github+json");
    let body = http::text("GitHub releases", rb).await?;
    parse(&serde_json::from_str(&body)?, asset_suffix(install).as_deref())
}

pub async fn check() -> Result<Value> {
    let release = latest(&this_install()).await?;
    Ok(json!({
        "current": CURRENT,
        "version": release.version,
        "newer": newer(&release.version, CURRENT),
        "page": release.page,
        // Without it the UI sends people to `page` instead of calling `install`.
        "installable": release.asset.is_some(),
    }))
}

static INSTALLING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Desktop: `{ quit: true }` once the update waits for this app to close.
/// Android: `{ apk }` for the system installer, which only the app can start.
pub async fn install() -> Result<Value> {
    let _busy = INSTALLING.try_lock().map_err(|_| anyhow!("the update is already downloading"))?;
    let install = this_install();
    let release = latest(&install).await?;
    ensure!(newer(&release.version, CURRENT), "Aikatsu {CURRENT} is already up to date");
    let asset = release.asset.context("this copy of Aikatsu can't update itself; get the new version from the release page")?;
    match install {
        Install::WindowsSetup => {
            let setup = std::env::temp_dir().join("aikatsu-update").join(&asset.name);
            download(&asset, &setup).await?;
            // /UPDATE: wait for this app to exit, then open the new one (desktop/packaging/aikatsu.nsi).
            std::process::Command::new(&setup)
                .args(["/S", "/UPDATE"])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .context("couldn't start the installer")?;
            Ok(json!({ "quit": true }))
        }
        Install::AppImage(path) => {
            let mut part = path.clone().into_os_string();
            part.push(".part");
            let part = PathBuf::from(part);
            download(&asset, &part).await?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                tokio::fs::set_permissions(&part, std::fs::Permissions::from_mode(0o755)).await?;
            }
            // Same folder, so the new file replaces the old one in one step.
            tokio::fs::rename(&part, &path).await.with_context(|| format!("couldn't replace {}", path.display()))?;
            open_after_exit(&path)?;
            Ok(json!({ "quit": true }))
        }
        Install::Android => {
            let apk = crate::dirs().data.join("update").join(&asset.name);
            download(&asset, &apk).await?;
            Ok(json!({ "apk": apk }))
        }
        Install::Manual => unreachable!("manual installs have no asset"),
    }
}

/// Streams `asset` to `dest`, pushing `appUpdate` progress. A file whose SHA-256
/// doesn't match the release's is deleted.
async fn download(asset: &Asset, dest: &Path) -> Result<()> {
    let result = async {
        tokio::fs::create_dir_all(dest.parent().context("no folder for the update")?).await?;
        let resp = http::PLAIN.get(&asset.url).header("User-Agent", http::API_UA).send().await?.error_for_status()?;
        let mut file = tokio::fs::File::create(dest).await?;
        let mut hash = Sha256::new();
        let (mut done, mut shown) = (0u64, 0u64);
        let mut body = resp.bytes_stream();
        while let Some(chunk) = body.next().await {
            let chunk = chunk?;
            hash.update(&chunk);
            file.write_all(&chunk).await?;
            done += chunk.len() as u64;
            if done - shown >= 1 << 20 || done == asset.size {
                shown = done;
                push("appUpdate", &json!({ "done": done, "total": asset.size }));
            }
        }
        file.flush().await?;
        let got: String = hash.finalize().iter().map(|b| format!("{b:02x}")).collect();
        ensure!(got == asset.sha256, "{} didn't download intact; try again", asset.name);
        Ok(())
    }
    .await;
    if result.is_err() {
        let _ = tokio::fs::remove_file(dest).await;
    }
    result
}

/// Opens `path` once this process is gone: the single-instance lock would turn it away sooner.
fn open_after_exit(path: &Path) -> Result<()> {
    let mut cmd = std::process::Command::new("sh");
    cmd.args(["-c", r#"while kill -0 "$0" 2>/dev/null; do sleep 0.2; done; exec "$1""#])
        .arg(std::process::id().to_string())
        .arg(path)
        // Not inside this AppImage's mount, which goes away with it.
        .current_dir("/")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(unix)]
    std::os::unix::process::CommandExt::process_group(&mut cmd, 0);
    cmd.spawn().context("couldn't schedule the restart")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_numerically() {
        assert!(newer("0.10.0", "0.9.9"));
        assert!(newer("1.0.0", "0.99.0"));
        assert!(newer("0.3.4", "0.3.3"));
        assert!(!newer("0.3.3", "0.3.3"));
        assert!(!newer("0.3.2", "0.3.3"));
        assert!(!newer("0.4.0-beta.1", "0.3.3"));
        assert!(!newer("", "0.3.3"));
    }

    #[test]
    fn picks_this_installs_file_and_needs_its_checksum() {
        let release = json!({
            "tag_name": "v0.4.0",
            "html_url": "https://github.com/KidiXDev/aikatsu/releases/tag/v0.4.0",
            "assets": [
                { "name": "Aikatsu-v0.4.0-windows-x64.zip", "browser_download_url": "https://x/zip", "size": 1, "digest": "sha256:AA" },
                { "name": "Aikatsu-v0.4.0-windows-x64-setup.exe", "browser_download_url": "https://x/setup", "size": 2, "digest": "sha256:BB" },
                { "name": "Aikatsu-v0.4.0-android-arm64-v8a.apk", "browser_download_url": "https://x/apk", "size": 3 },
            ],
        });
        let r = parse(&release, Some("-windows-x64-setup.exe")).unwrap();
        assert_eq!(r.version, "0.4.0");
        assert_eq!(r.page, "https://github.com/KidiXDev/aikatsu/releases/tag/v0.4.0");
        let a = r.asset.unwrap();
        assert_eq!((a.name.as_str(), a.url.as_str(), a.size, a.sha256.as_str()), ("Aikatsu-v0.4.0-windows-x64-setup.exe", "https://x/setup", 2, "bb"));
        assert!(parse(&release, Some("-android-arm64-v8a.apk")).unwrap().asset.is_none(), "no digest");
        assert!(parse(&release, Some("-x86_64.AppImage")).unwrap().asset.is_none());
        assert!(parse(&release, None).unwrap().asset.is_none());
        assert!(parse(&json!({}), None).is_err());
    }

    #[tokio::test]
    #[ignore]
    async fn live_latest_release() {
        let r = latest(&Install::Android).await.unwrap();
        println!("{} {}", r.version, r.page);
        assert!(newer(&r.version, "0.0.1"));
        assert!(r.asset.unwrap().name.ends_with(&asset_suffix(&Install::Android).unwrap()));
    }

    #[tokio::test]
    async fn download_keeps_only_an_intact_file() {
        use axum::{Router, routing::get};

        const DATA: &[u8] = b"new aikatsu";
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move { axum::serve(listener, Router::new().route("/file", get(|| async { DATA }))).await.unwrap() });
        let dir = std::env::temp_dir().join(format!("aikatsu-update-test-{}", std::process::id()));
        let dest = dir.join("setup.exe");
        let sha256 = Sha256::digest(DATA).iter().map(|b| format!("{b:02x}")).collect();
        let mut asset = Asset { name: "setup.exe".into(), url: format!("http://{address}/file"), size: DATA.len() as u64, sha256 };
        download(&asset, &dest).await.unwrap();
        assert_eq!(std::fs::read(&dest).unwrap(), DATA);

        asset.sha256 = "0".repeat(64);
        assert!(download(&asset, &dest).await.unwrap_err().to_string().contains("didn't download intact"));
        assert!(!dest.exists());
        server.abort();
        std::fs::remove_dir_all(dir).unwrap();
    }
}
