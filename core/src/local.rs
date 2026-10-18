//! The built-in "local" source: anime from the user's own folders.

use crate::meta::Meta;
use crate::sources::{Episode, Stream};
use crate::{db, push};
use anyhow::{Result, ensure};
use regex::Regex;
use serde::Serialize;
use serde_json::json;
use std::collections::{BTreeMap, HashSet};
use std::path::{Component, Path, PathBuf};
use std::sync::{LazyLock, Mutex};

pub const SOURCE: &str = "local";
const ROOTS: &str = "localFolders";
const VIDEO: [&str; 10] = ["mkv", "mp4", "avi", "webm", "m4v", "mov", "ts", "m2ts", "wmv", "flv"];

#[derive(Debug, Serialize)]
pub struct Folder {
    pub path: String,
    pub available: bool,
}

#[derive(Debug, Serialize)]
pub struct Series {
    pub path: String,
    pub name: String,
    pub available: bool,
    pub episodes: usize,
    pub meta: Option<Meta>,
}

#[derive(Debug, Serialize)]
pub struct Library {
    pub folders: Vec<Folder>,
    pub series: Vec<Series>,
}

pub fn roots() -> Vec<String> {
    db::setting(ROOTS).and_then(|v| serde_json::from_str(&v).ok()).unwrap_or_default()
}

fn set_roots(list: &[String]) -> Result<()> {
    db::set_setting(ROOTS, &serde_json::to_string(list)?)
}

pub fn add_root(path: &str) -> Result<()> {
    let path = path.trim();
    ensure!(!path.is_empty() && Path::new(path).is_dir(), "Choose a folder");
    let mut list = roots();
    ensure!(!list.iter().any(|r| Path::new(r) == Path::new(path)), "That folder is already in your library");
    list.push(path.to_owned());
    set_roots(&list)
}

pub fn remove_root(path: &str) -> Result<()> {
    set_roots(&roots().into_iter().filter(|r| Path::new(r) != Path::new(path)).collect::<Vec<_>>())
}

fn in_library(path: &str) -> Result<&Path> {
    let p = Path::new(path);
    let inside = !p.components().any(|c| c == Component::ParentDir) && roots().iter().any(|r| p.starts_with(r));
    ensure!(inside, "This folder isn't in this device's library");
    Ok(p)
}

fn is_video(p: &Path) -> bool {
    p.extension().and_then(|e| e.to_str()).is_some_and(|e| VIDEO.contains(&e.to_ascii_lowercase().as_str()))
}

fn entries(dir: &Path) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> =
        std::fs::read_dir(dir).into_iter().flatten().flatten().filter(|e| !e.file_name().to_string_lossy().starts_with('.')).map(|e| e.path()).collect();
    paths.sort();
    paths
}

fn videos(dir: &Path) -> Vec<PathBuf> {
    entries(dir).into_iter().filter(|p| p.is_file() && is_video(p)).collect()
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

static SEASON_DIR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(?:season|s)\s*0*(\d+)$").unwrap());
static ANILIST_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\{anilist-(\d+)\}").unwrap());
static NAME_NOISE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\[[^\]]*\]|\([^)]*\)|\{[^}]*\}|\b\d{1,4}\s*[-~]\s*\d{1,4}\b|\b(?:\d{3,4}p|bd|bdrip|bluray|web-?dl|batch|complete|[xh]26[45]|hevc)\b").unwrap()
});

fn clean_name(name: &str) -> String {
    let clean = NAME_NOISE.replace_all(name, " ").split_whitespace().collect::<Vec<_>>().join(" ");
    if clean.is_empty() { name.to_owned() } else { clean }
}

fn name_of(dir: &Path) -> String {
    let name = file_name(dir);
    match SEASON_DIR.captures(&name) {
        Some(c) => format!("{} Season {}", clean_name(&dir.parent().map(file_name).unwrap_or_default()), &c[1]),
        None => clean_name(&name),
    }
}

fn tagged_id(path: &str) -> i64 {
    let season = SEASON_DIR.captures(&file_name(Path::new(path))).and_then(|c| c[1].parse::<u32>().ok()).unwrap_or(1);
    if season > 1 {
        return 0;
    }
    ANILIST_TAG.captures(path).and_then(|c| c[1].parse().ok()).unwrap_or(0)
}

fn series_dirs(root: &Path) -> Vec<(PathBuf, Vec<PathBuf>)> {
    let mut out = Vec::new();
    let mut level = vec![root.to_path_buf()];
    for _ in 0..3 {
        let mut next = Vec::new();
        for dir in level {
            let files = videos(&dir);
            next.extend(entries(&dir).into_iter().filter(|p| p.is_dir()));
            if !files.is_empty() {
                out.push((dir, files));
            }
        }
        level = next;
    }
    out
}

pub fn library() -> Library {
    let links = db::local_links().unwrap_or_default();
    let mut folders = Vec::new();
    let mut series: Vec<Series> = Vec::new();
    let mut seen = HashSet::new();
    for root in roots() {
        let available = Path::new(&root).is_dir();
        let found: Vec<(String, usize)> = if available {
            series_dirs(Path::new(&root)).into_iter().map(|(dir, files)| (dir.display().to_string(), numbered(files).len())).collect()
        } else {
            links.keys().filter(|p| Path::new(p).starts_with(&root)).map(|p| (p.clone(), 0)).collect()
        };
        for (path, episodes) in found {
            if seen.insert(path.clone()) {
                series.push(Series { name: name_of(Path::new(&path)), available, episodes, meta: links.get(&path).cloned(), path });
            }
        }
        folders.push(Folder { path: root, available });
    }
    series.sort_by_key(|s| s.name.to_lowercase());
    Library { folders, series }
}

static NOISE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)\[[^\]]*\]|\([^)]*\)|\{[^}]*\}|\b(?:\d{3,4}p|[xh]\.?26[45]|hevc|av1|10-?bit|8-?bit|aac|flac|opus|ddp?\d(?:\.\d)?|dts|web-?dl|bluray|bdrip)\b").unwrap()
});
static EPISODE_RES: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    [r"(?i)\bS\d{1,2}\s*E(\d{1,4})\b", r"(?i)\b(?:episode|ep|e)\s*(\d{1,4})(?:v\d)?\b", r"\s-\s*(\d{1,4})(?:v\d)?\b", r"第\s*(\d{1,4})\s*[話话集]"]
        .iter()
        .map(|r| Regex::new(r).unwrap())
        .collect()
});
static LAST_NUMBER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\b(\d{1,4})(?:v\d)?\b").unwrap());

pub fn episode_number(stem: &str) -> Option<u32> {
    let text = NOISE.replace_all(stem, " ").replace(['.', '_'], " ");
    let text = format!(" {} ", text.split_whitespace().collect::<Vec<_>>().join(" "));
    EPISODE_RES.iter().find_map(|re| re.captures(&text)).or_else(|| LAST_NUMBER.captures_iter(&text).last()).and_then(|c| c[1].parse().ok())
}

fn numbered(files: Vec<PathBuf>) -> Vec<Episode> {
    let mut by_num: BTreeMap<u32, Episode> = BTreeMap::new();
    let mut loose = Vec::new();
    for file in files {
        let stem = file.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        let url = file.display().to_string();
        match episode_number(&stem) {
            Some(num) => _ = by_num.insert(num, Episode { num, url, title: String::new() }),
            None => loose.push((url, stem)),
        }
    }
    let first_loose = by_num.keys().last().map_or(1, |n| n + 1);
    for (num, (url, title)) in (first_loose..).zip(loose) {
        by_num.insert(num, Episode { num, url, title });
    }
    by_num.into_values().collect()
}

pub fn episodes(folder: &str) -> Result<Vec<Episode>> {
    let dir = in_library(folder)?;
    ensure!(dir.is_dir(), "Can't find {folder}. Is the drive connected?");
    let eps = numbered(videos(dir));
    ensure!(!eps.is_empty(), "No videos in {folder}");
    Ok(eps)
}

pub fn stream(file: &str) -> Result<Stream> {
    let path = in_library(file)?;
    ensure!(path.is_file(), "Can't find {file}. Is the drive connected?");
    ensure!(is_video(path), "{file} isn't a video");
    Ok(Stream { url: file.to_owned(), referer: String::new() })
}

pub async fn link(path: &str, anilist_id: i64) -> Result<Meta> {
    ensure!(in_library(path)?.is_dir(), "Can't find {path}. Is the drive connected?");
    let meta = crate::api::enrich(anilist_id, "", "", false).await?;
    ensure!(meta.anilist_id > 0, "No AniList entry {anilist_id}");
    db::set_local_link(path, &meta)?;
    push("local", &json!({ "path": path }));
    Ok(meta)
}

static TRIED: LazyLock<Mutex<HashSet<String>>> = LazyLock::new(Default::default);
static MATCHING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

pub async fn match_all() -> Result<usize> {
    let Ok(_one) = MATCHING.try_lock() else { return Ok(0) };
    let lib = tokio::task::spawn_blocking(library).await?;
    let mut linked = 0;
    for s in lib.series.into_iter().filter(|s| s.available && s.meta.is_none()) {
        if !TRIED.lock().unwrap().insert(s.path.clone()) {
            continue;
        }
        match crate::api::enrich(tagged_id(&s.path), &s.name, "", false).await {
            Ok(m) if m.anilist_id > 0 => {
                db::set_local_link(&s.path, &m)?;
                linked += 1;
                push("local", &json!({ "path": s.path }));
            }
            Ok(_) => tracing::info!("local: no AniList match for {}", s.name),
            Err(e) => tracing::warn!("local: couldn't match {} ({e:#})", s.name),
        }
    }
    Ok(linked)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn episode_numbers_from_file_names() {
        let cases = [
            ("[Kusonime] Otonari no Tenshi-sama S2 - 01", Some(1)),
            ("[Kusonime] Otonari no Tenshi-sama S2 - 12 END", Some(12)),
            ("Show.S02E05.1080p.WEB-DL.DDP5.1.H.264", Some(5)),
            ("[Group] Show - 07v2 [ABCD1234]", Some(7)),
            ("Show Episode 3 [1080p]", Some(3)),
            ("Mob Psycho 100 - 03", Some(3)),
            ("86 - Eighty Six - 05 (1080p HEVC)", Some(5)),
            ("Re Zero - 2nd Season - 05", Some(5)),
            ("Bakemonogatari_04", Some(4)),
            ("Show E10", Some(10)),
            ("葬送のフリーレン 第12話", Some(12)),
            ("Movie (2019) [1080p x265]", None),
        ];
        for (name, want) in cases {
            assert_eq!(episode_number(name), want, "{name}");
        }
    }

    #[test]
    fn folders_episodes_and_trust_boundary() {
        let root = std::env::temp_dir().join(format!("aikatsu-local-{}", std::process::id()));
        let touch = |rel: &str| {
            let p = root.join(rel);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(&p, b"x").unwrap();
            p
        };
        touch("Loose - 01.mkv");
        touch("Otonari S2/[G] Otonari S2 - 01.mkv");
        touch("Otonari S2/[G] Otonari S2 - 02.mkv");
        touch("Otonari S2/[G] Otonari S2 - 02v2.mkv");
        touch("Otonari S2/Otonari OVA.mp4");
        touch("Otonari S2/notes.txt");
        touch("Frieren (2023) {anilist-154587}/Season 01/Frieren - S01E01.mp4");
        touch("Frieren (2023) {anilist-154587}/Season 02/Frieren - S02E01.mp4");
        touch("Empty/readme.txt");
        let outside = std::env::temp_dir().join(format!("aikatsu-local-outside-{}.mkv", std::process::id()));
        std::fs::write(&outside, b"x").unwrap();

        let before = roots();
        set_roots(&[]).unwrap();
        let root_s = root.display().to_string();
        add_root(&root_s).unwrap();
        assert!(add_root(&root_s).is_err(), "no duplicates");

        let lib = library();
        let found: Vec<(String, usize)> = lib.series.iter().map(|s| (s.name.clone(), s.episodes)).collect();
        assert_eq!(
            found,
            [
                (file_name(&root), 1),
                ("Frieren Season 1".to_owned(), 1),
                ("Frieren Season 2".to_owned(), 1),
                ("Otonari S2".to_owned(), 3),
            ]
        );
        let tags: Vec<i64> = lib.series.iter().filter(|s| s.name.starts_with("Frieren")).map(|s| tagged_id(&s.path)).collect();
        assert_eq!(tags, [154587, 0], "a later season of a downloaded show isn't the tagged first season");
        assert_eq!(clean_name("[Kusonime] Fantasi di Bawah Sinar Rembulan S2 01-12 1080p"), "Fantasi di Bawah Sinar Rembulan S2");
        assert_eq!(clean_name("[Kusonime] Di Manjakan Bidadari BD 1080p"), "Di Manjakan Bidadari");

        let otonari = root.join("Otonari S2").display().to_string();
        let eps = episodes(&otonari).unwrap();
        let summary: Vec<(u32, String, String)> =
            eps.iter().map(|e| (e.num, file_name(Path::new(&e.url)), e.title.clone())).collect();
        assert_eq!(
            summary,
            [
                (1, "[G] Otonari S2 - 01.mkv".into(), "".into()),
                (2, "[G] Otonari S2 - 02v2.mkv".into(), "".into()),
                (3, "Otonari OVA.mp4".into(), "Otonari OVA".into()),
            ]
        );
        assert_eq!(stream(&eps[0].url).unwrap().url, eps[0].url);
        assert!(stream(&root.join("Otonari S2/notes.txt").display().to_string()).is_err(), "not a video");
        assert!(stream(&outside.display().to_string()).is_err(), "outside the library");
        assert!(stream(&root.join("Otonari S2/../../escape.mkv").display().to_string()).is_err(), "no ..");
        assert!(episodes(&std::env::temp_dir().display().to_string()).is_err());

        remove_root(&root_s).unwrap();
        assert!(episodes(&otonari).is_err(), "removed folders stop playing");
        set_roots(&before).unwrap();
        std::fs::remove_dir_all(&root).unwrap();
        std::fs::remove_file(&outside).unwrap();
    }

    /// `LIVE_DIR=<folder> cargo test -p aikatsu-core live_local -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn live_local() {
        let dir = std::env::var("LIVE_DIR").expect("set LIVE_DIR to a folder of videos");
        let before = roots();
        set_roots(&[dir]).unwrap();
        for s in library().series {
            let eps = episodes(&s.path).unwrap();
            println!("{} ({} episodes): {:?}", s.name, s.episodes, eps.iter().map(|e| e.num).collect::<Vec<_>>());
        }
        crate::RT.block_on(match_all()).unwrap();
        for s in library().series {
            match s.meta {
                Some(m) => println!("{} -> {} (anilist {}, {} episodes)", s.name, m.title(), m.anilist_id, m.episodes),
                None => println!("{} -> no match; the user chooses", s.name),
            }
        }
        set_roots(&before).unwrap();
    }
}
