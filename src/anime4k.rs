//! Anime4K: the CLI's ten real-time shader modes (internal/upscaler/shaders.go).

use crate::http;
use anyhow::{Result, anyhow};
use serde::Serialize;
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
        name: "Fast (Mode A)",
        description: "Optimized for text-heavy anime with subtitles",
        files: &[CLAMP, "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "balanced",
        name: "Balanced (Mode B)",
        description: "General purpose anime upscaling, good balance",
        files: &[CLAMP, "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "quality",
        name: "Quality (Mode C)",
        description: "High quality for anime films, requires a good GPU",
        files: &[CLAMP, "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_L.glsl"],
    },
    Mode {
        key: "performance",
        name: "Performance (Low GPU)",
        description: "Minimal shaders for weaker GPUs",
        files: &[CLAMP, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "ultra",
        name: "Ultra (Max Enhancement)",
        description: "Maximum enhancement with denoise + deblur + upscale",
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
        name: "GAN UUL (360p→4K)",
        description: "Experimental SRGAN for 360p→4K, very heavy, needs a powerful GPU",
        files: &["Anime4K_Restore_GAN_UUL.glsl", "Anime4K_Upscale_GAN_x4_UUL.glsl", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"],
    },
    Mode {
        key: "aa",
        name: "Advanced A+A (Max Perceptual)",
        description: "Double restore pass, highest perceptual quality, may cause ringing",
        files: &[CLAMP, "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Restore_CNN_S.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "bb",
        name: "Advanced B+B (720p Optimized)",
        description: "Double soft restore, good for 720p with aliasing artifacts",
        files: &[CLAMP, "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Restore_CNN_Soft_S.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_S.glsl"],
    },
    Mode {
        key: "ca",
        name: "Advanced C+A (Upscaled Content)",
        description: "Quality + restore, good for downscaled 480p anime",
        files: &[CLAMP, "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_Restore_CNN_M.glsl", PRE2, PRE4, "Anime4K_Upscale_CNN_x2_M.glsl"],
    },
];

pub fn shader_dir() -> PathBuf {
    dirs::config_dir().unwrap_or_else(std::env::temp_dir).join("aikatsu").join("anime4k-shaders")
}

pub fn installed() -> bool {
    shader_dir().join(CLAMP).exists()
}

/// Downloads the pinned v4.0.1 shader pack (and the GAN pair when asked).
pub async fn install(gan: bool) -> Result<()> {
    let dir = shader_dir();
    tokio::fs::create_dir_all(&dir).await?;
    if !installed() {
        let bytes = http::PLAIN.get(ZIP_URL).send().await?.error_for_status()?.bytes().await?;
        let dir2 = dir.clone();
        tokio::task::spawn_blocking(move || extract_glsl(&bytes, &dir2)).await??;
    }
    if gan {
        for f in GAN_FILES {
            let target = dir.join(Path::new(f).file_name().unwrap());
            if !target.exists() {
                let body = http::PLAIN.get(format!("{GAN_BASE}{f}")).send().await?.error_for_status()?.bytes().await?;
                tokio::fs::write(target, body).await?;
            }
        }
    }
    Ok(())
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
        assert_eq!(MODES.len(), 9, "plus Off = the CLI's 10 modes");
    }
}
