//! Anime4K sharpening presets for mpv, and the one-time shader download.

use crate::http;
use anyhow::{Result, anyhow};
use futures_util::StreamExt;
use serde::Serialize;
use serde_json::json;
use std::io::Read;
use std::path::{Path, PathBuf};

const ZIP_URL: &str = "https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip";
const GAN_BASE: &str = "https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/";
const GAN_FILES: [&str; 2] = ["Restore/Anime4K_Restore_GAN_UUL.glsl", "Upscale/Anime4K_Upscale_GAN_x4_UUL.glsl"];

#[derive(Serialize)]
pub struct Mode {
    pub key: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    #[serde(skip)]
    files: &'static [&'static str],
}

const CLAMP: &str = "Anime4K_Clamp_Highlights.glsl";
const PRE2: &str = "Anime4K_AutoDownscalePre_x2.glsl";
const PRE4: &str = "Anime4K_AutoDownscalePre_x4.glsl";

pub const MODES: &[Mode] = &[
    Mode {
        key: "fast",
        name: "Standard",
        description: "Good for most anime",
        files: &[CLAMP, "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "balanced",
        name: "Soft",
        description: "Gentler, for video that already looks clean",
        files: &[CLAMP, "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "quality",
        name: "Denoise",
        description: "Smooths grain and blocky video. Needs a good graphics card",
        files: &[CLAMP, "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_L.glsl"],
    },
    Mode {
        key: "performance",
        name: "Light",
        description: "Smallest effect, for weaker graphics cards",
        files: &[CLAMP, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "ultra",
        name: "Maximum",
        description: "Strongest clean-up and sharpening. Needs a powerful graphics card",
        files: &[
            CLAMP,
            "Anime4K_Denoise_Bilateral_Mode.glsl",
            "Anime4K_Deblur_DoG.glsl",
            "Anime4K_Darken_HQ.glsl",
            "Anime4K_Thin_HQ.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl",
            PRE2,
            PRE4,
            "Anime4K_Upscale_CNN_x2_L.glsl",
        ],
    },
    Mode {
        key: "gan",
        name: "Experimental",
        description: "For very low quality (360p) video. Very heavy on the graphics card",
        files: &["Anime4K_Restore_GAN_UUL.glsl", "Anime4K_Upscale_GAN_x4_UUL.glsl", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"],
    },
    Mode {
        key: "aa",
        name: "Extra sharp",
        description: "Crispest lines, may add faint halos around them",
        files: &[CLAMP, "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Restore_CNN_S.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "bb",
        name: "Extra soft",
        description: "Good for 720p video with jagged edges",
        files: &[CLAMP, "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Restore_CNN_Soft_S.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "ca",
        name: "Denoise + sharpen",
        description: "Good for 480p video",
        files: &[CLAMP, "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_Restore_CNN_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_M.glsl"],
    },
];

pub fn shader_dir() -> PathBuf {
    crate::dirs().config.join("anime4k-shaders")
}

pub fn installed() -> bool {
    shader_dir().join(CLAMP).exists()
}

static ONE: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Downloads the pinned v4.0.1 shader pack (and the GAN pair when asked), pushing
/// `anime4k` events with the overall `progress` from 0 to 1.
pub async fn install(gan: bool) -> Result<()> {
    let _one = ONE.lock().await;
    let dir = shader_dir();
    tokio::fs::create_dir_all(&dir).await?;
    let zip = !installed();
    let gan: Vec<(String, PathBuf)> = GAN_FILES
        .iter()
        .filter(|_| gan)
        .map(|f| (format!("{GAN_BASE}{f}"), dir.join(Path::new(f).file_name().unwrap())))
        .filter(|(_, target)| !target.exists())
        .collect();
    let total = usize::from(zip) + gan.len();
    if zip {
        let bytes = fetch(ZIP_URL, 0, total).await?;
        let dir2 = dir.clone();
        tokio::task::spawn_blocking(move || extract_glsl(&bytes, &dir2)).await??;
    }
    for (i, (url, target)) in gan.iter().enumerate() {
        tokio::fs::write(target, fetch(url, usize::from(zip) + i, total).await?).await?;
    }
    Ok(())
}

/// One of `total` downloads, `done` before it.
async fn fetch(url: &str, done: usize, total: usize) -> Result<Vec<u8>> {
    let resp = http::PLAIN.get(url).send().await?.error_for_status()?;
    // None when the body arrives compressed; progress then moves per file.
    let size = resp.content_length().unwrap_or(0);
    let mut body = Vec::with_capacity(size as usize);
    let mut stream = resp.bytes_stream();
    let mut shown = None;
    while let Some(chunk) = stream.next().await {
        body.extend_from_slice(&chunk?);
        let part = if size == 0 { 0.0 } else { (body.len() as f64 / size as f64).min(1.0) };
        let percent = ((done as f64 + part) / total as f64 * 100.0) as u32;
        if shown != Some(percent) {
            shown = Some(percent);
            crate::push("anime4k", &json!({ "progress": f64::from(percent) / 100.0 }));
        }
    }
    Ok(body)
}

fn extract_glsl(zip_bytes: &[u8], dir: &Path) -> Result<()> {
    let mut archive = zip::ZipArchive::new(std::io::Cursor::new(zip_bytes))?;
    for i in 0..archive.len() {
        let mut f = archive.by_index(i)?;
        // Only flat *.glsl entries; never trust archive paths.
        let Some(name) = Path::new(f.name()).file_name().map(|n| n.to_owned()) else { continue };
        if !name.to_string_lossy().ends_with(".glsl") {
            continue;
        }
        let mut buf = Vec::new();
        f.read_to_end(&mut buf)?;
        std::fs::write(dir.join(name), buf)?;
    }
    Ok(())
}

/// Shader paths for a mode, installing the pack on first use.
pub async fn shaders(mode: &str) -> Result<Vec<PathBuf>> {
    let m = MODES.iter().find(|m| m.key == mode).ok_or_else(|| anyhow!("unknown Anime4K mode {mode}"))?;
    install(mode == "gan").await?;
    let dir = shader_dir();
    let paths: Vec<PathBuf> = m.files.iter().map(|f| dir.join(f)).filter(|p| p.exists()).collect();
    anyhow::ensure!(!paths.is_empty(), "Anime4K shaders missing in {}", dir.display());
    Ok(paths)
}

/// mpv path-list separator: ';' on Windows, ':' elsewhere.
pub fn path_list(paths: &[PathBuf]) -> String {
    let sep = if cfg!(windows) { ";" } else { ":" };
    paths.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(sep)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn modes() {
        assert_eq!(MODES.len(), 9, "nine presets plus Off");
    }
}
