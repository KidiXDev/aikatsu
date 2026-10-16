//! `aikatsu-plugin`: runs source plugins outside the app, for their authors
//! and a repo's CI. Scripts go through the same engine and checks as in the app.

use crate::plugins::{self, Index, Plugin};
use crate::sources;
use anyhow::{Context, Result, anyhow};
use std::path::{Path, PathBuf};
use std::time::Duration;

const USAGE: &str = "usage:
  aikatsu-plugin test <script.rhai | repo dir>   run the test_* functions in tests/<name>.rhai
  aikatsu-plugin live <script.rhai | repo dir> [query]   search, episodes, qualities and stream on the real site
  aikatsu-plugin call <script.rhai> <function> [args…]   print what one function returns, as JSON
  aikatsu-plugin index <repo dir>                refresh the sha256 of every script in index.json";

/// Test-only helpers, merged after the plugin; plugins themselves don't get these.
const PRELUDE: &str = r#"
fn assert(ok) { if !ok { throw "assertion failed"; } }
fn assert(ok, msg) { if !ok { throw msg; } }
fn assert_eq(got, want) { if got != want { throw `expected ${want}, got ${got}`; } }
"#;

pub fn main() -> i32 {
    tracing_subscriber::fmt().with_writer(std::io::stderr).with_target(false).init();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let res = match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["test", path] => test(Path::new(path)),
        ["live", path, rest @ ..] => live(Path::new(path), &rest.join(" ")),
        ["call", script, f, rest @ ..] => call(Path::new(script), f, rest),
        ["index", dir] => index(Path::new(dir)),
        _ => Err(anyhow!("{USAGE}")),
    };
    match res {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{e:#}");
            1
        }
    }
}

/// A repo dir means every script its index lists.
fn scripts(path: &Path) -> Result<Vec<PathBuf>> {
    if !path.is_dir() {
        return Ok(vec![path.to_owned()]);
    }
    Ok(read_index(path)?.plugins.iter().map(|e| path.join(&e.file)).collect())
}

fn read_index(dir: &Path) -> Result<Index> {
    let file = dir.join("index.json");
    serde_json::from_str(&std::fs::read_to_string(&file).with_context(|| format!("reading {}", file.display()))?).with_context(|| format!("parsing {}", file.display()))
}

fn key_of(script: &Path) -> String {
    script.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default()
}

fn load(script: &Path, extra: &str) -> Result<Plugin> {
    let src = std::fs::read_to_string(script).with_context(|| format!("reading {}", script.display()))?;
    Plugin::from_script(&key_of(script), &src, extra).with_context(|| script.display().to_string())
}

/// tests/<name>.rhai beside the script's folder (sources/ and tests/ in a repo).
fn tests_for(script: &Path) -> PathBuf {
    let root = script.parent().and_then(Path::parent).unwrap_or(Path::new("."));
    root.join("tests").join(format!("{}.rhai", key_of(script)))
}

fn test(path: &Path) -> Result<()> {
    let mut failed = 0;
    for script in scripts(path)? {
        let tests = tests_for(&script);
        let src = std::fs::read_to_string(&tests).with_context(|| format!("reading {}", tests.display()))?;
        let p = std::sync::Arc::new(load(&script, &format!("{PRELUDE}\n{src}"))?);
        let mut names: Vec<String> = p.functions().into_iter().filter(|f| f.starts_with("test_")).collect();
        names.sort();
        names.dedup();
        for name in names {
            match crate::RT.block_on(plugins::call(&p, &name, (), Duration::from_secs(30))) {
                Ok(_) => println!("ok    {} {name}", key_of(&script)),
                Err(e) => {
                    failed += 1;
                    println!("FAIL  {} {name}: {e:#}", key_of(&script));
                }
            }
        }
    }
    anyhow::ensure!(failed == 0, "{failed} test(s) failed");
    Ok(())
}

fn live(path: &Path, query: &str) -> Result<()> {
    let query = if query.is_empty() { "one piece" } else { query };
    let mut failed = 0;
    for script in scripts(path)? {
        let p = plugins::add_local(load(&script, "")?);
        let res = crate::RT.block_on(async {
            let found = sources::search(&p.id, query).await?;
            let anime = found.first().ok_or_else(|| anyhow!("no results"))?;
            let eps = sources::episodes(&p.id, &anime.url).await?;
            let ep = eps.last().ok_or_else(|| anyhow!("no episodes"))?;
            let q = sources::qualities(&p.id, &ep.url).await.unwrap_or_default();
            let s = sources::stream(&p.id, &ep.url, "best").await?;
            anyhow::Ok(format!("{} results, {} eps, q={q:?}, ep{} -> {}", found.len(), eps.len(), ep.num, &s.url[..s.url.len().min(80)]))
        });
        match res {
            Ok(line) => println!("{:<12} {line}", p.name),
            Err(e) => {
                failed += 1;
                println!("{:<12} FAIL {e:#}", p.name);
            }
        }
    }
    anyhow::ensure!(failed == 0, "{failed} source(s) failed");
    Ok(())
}

fn call(script: &Path, f: &str, args: &[&str]) -> Result<()> {
    let p = std::sync::Arc::new(load(script, "")?);
    let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let v = crate::RT.block_on(plugins::call(&p, f, args, Duration::from_secs(60)))?;
    println!("{}", serde_json::to_string_pretty(&v)?);
    Ok(())
}

fn index(dir: &Path) -> Result<()> {
    use sha2::Digest;
    let mut index = read_index(dir)?;
    for e in &mut index.plugins {
        let file = dir.join(&e.file);
        load(&file, "")?; // only scripts the app would accept
        let data = std::fs::read(&file)?;
        let sum: String = sha2::Sha256::digest(&data).iter().map(|b| format!("{b:02x}")).collect();
        if sum != e.sha256 {
            println!("{}: {}", e.key, if e.sha256.is_empty() { "added" } else { "changed" });
            e.sha256 = sum;
        }
    }
    std::fs::write(dir.join("index.json"), serde_json::to_string_pretty(&index)? + "\n")?;
    Ok(())
}
