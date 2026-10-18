//! Sources as Rhai scripts from plugin repos. A repo is an `index.json` listing
//! scripts with their SHA-256; Kyoko, the official one, is added on first run
//! and any other only after the user accepts a warning. Scripts are sandboxed:
//! the functions registered in `engine` (network, HTML, JSON, a small cache)
//! are all they can reach, so no files, no history, no settings.

use crate::push;
use crate::sources::{clean_sub_indo, height_of, sort_by_height};
use crate::{db, http};
use anyhow::{Context, Result, anyhow, bail};
use rhai::{AST, Array, Dynamic, Engine, EvalAltResult, FuncArgs, Map, Scope};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock, Mutex, RwLock};
use std::time::{Duration, Instant};

/// Bumped when host functions are added; plugins asking for more are skipped.
pub const API_VERSION: i64 = 1;
pub const OFFICIAL_REPO: &str = "https://github.com/KidiXDev/kyoko";
pub(crate) const REPOS_SETTING: &str = "pluginRepos";

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Index {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub plugins: Vec<Entry>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Entry {
    pub key: String,
    pub name: String,
    #[serde(default)]
    pub version: i64,
    #[serde(default = "first_api")]
    pub api: i64,
    /// Relative to the index.
    pub file: String,
    #[serde(default)]
    pub sha256: String,
}

fn first_api() -> i64 {
    1
}

pub struct Plugin {
    /// "<repo id>/<key>": what history, downloads and settings store.
    pub id: String,
    pub name: String,
    /// `name`, plus the repo's when another installed plugin has the same name.
    pub label: String,
    pub repo: String,
    pub version: i64,
    ast: AST,
}

impl Plugin {
    /// A script outside any repo, for the aikatsu-plugin CLI; `extra` (tests) is merged in.
    pub fn from_script(key: &str, src: &str, extra: &str) -> Result<Plugin> {
        let mut ast = compile(src)?;
        if !extra.is_empty() {
            ast = ast.merge(&ENGINE.compile(extra).map_err(|e| anyhow!("{e}"))?);
        }
        Ok(Plugin { id: format!("local/{key}"), name: key.to_owned(), label: key.to_owned(), repo: "local".into(), version: 0, ast })
    }

    pub fn functions(&self) -> Vec<String> {
        self.ast.iter_functions().map(|f| f.name.to_owned()).collect()
    }
}

const REQUIRED: [(&str, usize); 4] = [("search", 1), ("episodes", 1), ("heights", 1), ("stream", 2)];

fn compile(src: &str) -> Result<AST> {
    let ast = ENGINE.compile(src).map_err(|e| anyhow!("script error: {e}"))?;
    for (name, params) in REQUIRED {
        anyhow::ensure!(ast.iter_functions().any(|f| f.name == name && f.params.len() == params), "script has no {name}() taking {params} argument(s)");
    }
    Ok(ast)
}

static REGISTRY: LazyLock<RwLock<Vec<Arc<Plugin>>>> = LazyLock::new(|| RwLock::new(load_installed()));

/// In repo order, then the order each index lists them.
pub fn installed() -> Vec<Arc<Plugin>> {
    REGISTRY.read().unwrap().clone()
}

pub fn find(id: &str) -> Option<Arc<Plugin>> {
    REGISTRY.read().unwrap().iter().find(|p| p.id == id).cloned()
}

/// Makes a CLI-loaded script answer to its id like an installed one.
pub fn add_local(p: Plugin) -> Arc<Plugin> {
    let p = Arc::new(p);
    let mut reg = REGISTRY.write().unwrap();
    reg.retain(|x| x.id != p.id);
    reg.push(p.clone());
    p
}

fn reload() {
    *REGISTRY.write().unwrap() = load_installed();
    CACHE.lock().unwrap().clear();
    http::clear_pages();
    push("plugins", &Value::Null);
}

fn load_installed() -> Vec<Arc<Plugin>> {
    let mut out = Vec::new();
    for url in repo_urls() {
        let Some(index) = saved_index(&url) else { continue };
        for e in index.plugins.iter().filter(|e| e.api <= API_VERSION) {
            let loaded = std::fs::read_to_string(script_path(&url, &e.key)).map_err(anyhow::Error::from).and_then(|src| compile(&src));
            match loaded {
                Ok(ast) => out.push(Plugin {
                    id: format!("{}/{}", index.id, e.key),
                    name: e.name.clone(),
                    label: e.name.clone(),
                    repo: index.name.clone(),
                    version: e.version,
                    ast,
                }),
                Err(err) => tracing::warn!("plugin {}/{} not loaded: {err:#}", index.id, e.key),
            }
        }
    }
    let names: Vec<String> = out.iter().map(|p| p.name.to_lowercase()).collect();
    for p in &mut out {
        if names.iter().filter(|n| **n == p.name.to_lowercase()).count() > 1 {
            p.label = format!("{} ({})", p.name, p.repo);
        }
    }
    out.into_iter().map(Arc::new).collect()
}

/// For the UIs: installed sources by key.
pub fn list() -> Value {
    Value::Array(installed().iter().map(|p| json!({ "key": p.id, "name": p.label, "repo": p.repo, "version": p.version })).collect())
}

pub fn repo_urls() -> Vec<String> {
    db::setting(REPOS_SETTING).and_then(|v| serde_json::from_str(&v).ok()).unwrap_or_else(|| vec![OFFICIAL_REPO.to_owned()])
}

fn set_repo_urls(urls: &[String]) -> Result<()> {
    db::set_setting(REPOS_SETTING, &serde_json::to_string(urls)?)
}

/// What users paste — "github.com/user/repo", with or without https://, .git
/// or a trailing /tree/… — as one repo link, so the same repo is never added
/// twice. A direct link to an index.json (https, or file:// while developing)
/// is kept as it is.
fn canonical(input: &str) -> Result<String> {
    let s = input.trim().trim_end_matches('/');
    if s.ends_with(".json") {
        return Ok(s.to_owned());
    }
    let bare = s.strip_prefix("https://").or_else(|| s.strip_prefix("http://")).unwrap_or(s);
    let bare = bare.strip_prefix("www.").unwrap_or(bare);
    // GitHub's own rules: owners are letters, digits and -; repos may also use _ and .
    let owner_ok = |p: &str| !p.is_empty() && p.chars().all(|c| c.is_ascii_alphanumeric() || c == '-');
    let repo_ok = |p: &str| !p.is_empty() && !p.starts_with('.') && p.chars().all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c));
    match bare.strip_prefix("github.com/").map(|p| p.split('/').collect::<Vec<_>>()).as_deref() {
        Some([owner, repo, ..]) if owner_ok(owner) && repo_ok(repo.trim_end_matches(".git")) => {
            Ok(format!("https://github.com/{owner}/{}", repo.trim_end_matches(".git")))
        }
        _ => bail!("Paste a GitHub repo link, like https://github.com/user/repo"),
    }
}

/// A GitHub repo's index.json on its default branch.
fn index_url(repo: &str) -> String {
    match repo.strip_prefix("https://github.com/") {
        Some(path) => format!("https://raw.githubusercontent.com/{path}/HEAD/index.json"),
        None => repo.to_owned(),
    }
}

/// "user/repo" for GitHub repos, else the link.
fn short(repo: &str) -> &str {
    repo.strip_prefix("https://github.com/").unwrap_or(repo)
}

fn sha256_hex(data: &[u8]) -> String {
    Sha256::digest(data).iter().map(|b| format!("{b:02x}")).collect()
}

fn repo_dir(url: &str) -> PathBuf {
    crate::dirs().data.join("plugins").join(&sha256_hex(url.as_bytes())[..16])
}

fn script_path(url: &str, key: &str) -> PathBuf {
    repo_dir(url).join(format!("{key}.rhai"))
}

fn saved_index(url: &str) -> Option<Index> {
    serde_json::from_str(&std::fs::read_to_string(repo_dir(url).join("index.json")).ok()?).ok()
}

/// The last check or download failure per repo, shown under it in Settings.
static ERRORS: LazyLock<Mutex<HashMap<String, String>>> = LazyLock::new(Default::default);
static AVAILABLE: LazyLock<Mutex<HashMap<String, Index>>> = LazyLock::new(Default::default);
pub(crate) static SYNCING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

fn pending_updates(url: &str, index: &Index) -> usize {
    let saved = saved_index(url);
    let changed = index.plugins.iter().filter(|e| e.api <= API_VERSION)
        .filter(|e| saved.as_ref().and_then(|i| i.plugins.iter().find(|old| old.key == e.key)) != Some(*e) || !script_current(url, e))
        .count();
    changed + saved.iter().flat_map(|i| &i.plugins).filter(|old| !index.plugins.iter().any(|e| e.key == old.key)).count()
}

fn script_current(url: &str, e: &Entry) -> bool {
    std::fs::read(script_path(url, &e.key)).is_ok_and(|b| sha256_hex(&b).eq_ignore_ascii_case(&e.sha256))
}

/// Checks metadata only. Installed scripts and the running registry stay untouched.
pub async fn check_updates() -> Value {
    let _one = SYNCING.lock().await;
    for url in repo_urls() {
        let result = async {
            let index = fetch_index(&url).await?;
            check_unique(&url, &index.id)?;
            Ok::<_, anyhow::Error>(index)
        }.await;
        match result {
            Ok(index) => {
                AVAILABLE.lock().unwrap().insert(url.clone(), index);
                ERRORS.lock().unwrap().remove(&url);
            }
            Err(e) => {
                ERRORS.lock().unwrap().insert(url, format!("{e:#}"));
            }
        }
    }
    push("plugins", &Value::Null);
    repos()
}

/// For the Settings page: every repo with its plugins and last error.
pub fn repos() -> Value {
    let errors = ERRORS.lock().unwrap().clone();
    let available = AVAILABLE.lock().unwrap().clone();
    let loaded: HashSet<String> = installed().iter().map(|p| p.id.clone()).collect();
    Value::Array(
        repo_urls()
            .into_iter()
            .map(|url| {
                let official = url == OFFICIAL_REPO;
                let updates = available.get(&url).map_or(0, |i| pending_updates(&url, i));
                let index = saved_index(&url).or_else(|| available.get(&url).cloned());
                let name = index.as_ref().map(|i| i.name.clone()).unwrap_or_else(|| if official { "Kyoko".into() } else { short(&url).into() });
                let plugins: Vec<Value> = index
                    .iter()
                    .flat_map(|i| {
                        i.plugins.iter().map(|e| {
                            let key = format!("{}/{}", i.id, e.key);
                            let update = available.get(&url).and_then(|i| i.plugins.iter().find(|latest| latest.key == e.key))
                                .is_some_and(|latest| latest.api <= API_VERSION && (latest != e || !script_current(&url, latest)));
                            json!({ "loaded": loaded.contains(&key), "key": key, "name": e.name, "version": e.version, "compatible": e.api <= API_VERSION, "updateAvailable": update })
                        })
                    })
                    .collect();
                json!({ "url": url, "short": short(&url), "official": official, "name": name, "error": errors.get(&url), "plugins": plugins, "updates": updates })
            })
            .collect(),
    )
}

/// Fetches every repo's index and downloads the scripts that changed. A repo
/// that can't be reached keeps what it has, so sources work offline.
pub async fn sync_all() -> bool {
    let _one = SYNCING.lock().await;
    let mut updated = false;
    for url in repo_urls() {
        let res = sync_repo(&url).await;
        let mut errors = ERRORS.lock().unwrap();
        match res {
            Ok(changed) => {
                updated |= changed;
                errors.remove(&url)
            }
            Err(e) => {
                tracing::warn!("plugin repo {url}: {e:#}");
                errors.insert(url, format!("{e:#}"))
            }
        };
    }
    reload();
    updated
}

/// What the confirmation dialog shows before a repo is added.
pub async fn preview(input: &str) -> Result<Value> {
    let url = canonical(input)?;
    anyhow::ensure!(!repo_urls().contains(&url), "Already added");
    let index = fetch_index(&url).await?;
    check_unique(&url, &index.id)?;
    let plugins: Vec<Value> = index.plugins.iter().map(|e| json!({ "name": e.name, "version": e.version, "compatible": e.api <= API_VERSION })).collect();
    Ok(json!({ "url": url, "short": short(&url), "id": index.id, "name": index.name, "official": url == OFFICIAL_REPO, "plugins": plugins }))
}

pub async fn add(input: &str) -> Result<()> {
    let url = canonical(input)?;
    let _one = SYNCING.lock().await;
    let mut urls = repo_urls();
    anyhow::ensure!(!urls.contains(&url), "Already added");
    ERRORS.lock().unwrap().remove(&url);
    if let Err(e) = sync_repo(&url).await {
        // Added anyway when only some scripts failed: Settings shows why.
        if saved_index(&url).is_none() {
            let _ = std::fs::remove_dir_all(repo_dir(&url));
            return Err(e);
        }
        ERRORS.lock().unwrap().insert(url.clone(), format!("{e:#}"));
    }
    urls.push(url);
    set_repo_urls(&urls)?;
    reload();
    Ok(())
}

pub async fn remove(url: &str) -> Result<()> {
    let _one = SYNCING.lock().await;
    let urls: Vec<String> = repo_urls().into_iter().filter(|u| u != url).collect();
    set_repo_urls(&urls)?;
    let _ = std::fs::remove_dir_all(repo_dir(url));
    ERRORS.lock().unwrap().remove(url);
    AVAILABLE.lock().unwrap().remove(url);
    reload();
    Ok(())
}

/// After a synced repo list: drops removed repos. New ones download only when the user chooses.
pub async fn repos_synced(before: &[String]) {
    let _one = SYNCING.lock().await;
    let urls = repo_urls();
    for url in before.iter().filter(|u| !urls.contains(u)) {
        let _ = std::fs::remove_dir_all(repo_dir(url));
        ERRORS.lock().unwrap().remove(url);
        AVAILABLE.lock().unwrap().remove(url);
    }
    reload();
}

async fn sync_repo(url: &str) -> Result<bool> {
    let index = fetch_index(url).await?;
    check_unique(url, &index.id)?;
    AVAILABLE.lock().unwrap().insert(url.to_owned(), index.clone());
    let dir = repo_dir(url);
    tokio::fs::create_dir_all(&dir).await?;
    let mut failed = Vec::new();
    let mut updated = saved_index(url).as_ref() != Some(&index);
    for e in index.plugins.iter().filter(|e| e.api <= API_VERSION) {
        let path = script_path(url, &e.key);
        if script_current(url, e) {
            continue;
        }
        if let Err(err) = download(url, e, &path).await {
            failed.push(format!("{}: {err:#}", e.name));
        } else {
            updated = true;
        }
    }
    for f in std::fs::read_dir(&dir)?.flatten() {
        let name = f.file_name().to_string_lossy().into_owned();
        if let Some(key) = name.strip_suffix(".rhai")
            && !index.plugins.iter().any(|e| e.key == key)
        {
            let _ = std::fs::remove_file(f.path());
        }
    }
    std::fs::write(dir.join("index.json"), serde_json::to_string(&index)?)?;
    anyhow::ensure!(failed.is_empty(), "{}", failed.join("; "));
    Ok(updated)
}

/// A broken or tampered download never replaces the script that works.
async fn download(repo: &str, e: &Entry, path: &Path) -> Result<()> {
    let base = url::Url::parse(&index_url(repo))?;
    let url = base.join(&e.file)?;
    anyhow::ensure!(url.scheme() == base.scheme(), "{} points outside the repo", e.file);
    let src = read_url(url.as_str()).await?;
    anyhow::ensure!(
        sha256_hex(src.as_bytes()).eq_ignore_ascii_case(&e.sha256),
        "checksum mismatch (the repo may be mid-update; try again in a few minutes)"
    );
    compile(&src)?;
    tokio::fs::write(path, src).await?;
    Ok(())
}

async fn read_url(url: &str) -> Result<String> {
    let u = url::Url::parse(url).with_context(|| format!("not a link: {url}"))?;
    match u.scheme() {
        "https" => http::text("Plugin repo", repo_request(u)).await,
        // A repo on disk, for developing plugins.
        "file" => {
            anyhow::ensure!(crate::api::setting("developerMode") == "true", "Enable Developer Mode in Settings to install or update local plugins");
            Ok(tokio::fs::read_to_string(u.to_file_path().map_err(|_| anyhow!("not a file path: {url}"))?).await?)
        }
        s => bail!("plugin repos are https:// links, not {s}://"),
    }
}

fn repo_request(mut url: url::Url) -> wreq::RequestBuilder {
    // Raw GitHub files are CDN-cached; a check must see newly published indexes and scripts.
    let nonce = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_nanos();
    url.query_pairs_mut().append_pair("_aikatsu", &nonce.to_string());
    http::PLAIN.get(url.as_str()).header("User-Agent", http::API_UA).header("Cache-Control", "no-cache").timeout(Duration::from_secs(20))
}

async fn fetch_index(repo: &str) -> Result<Index> {
    let body = read_url(&index_url(repo)).await.map_err(|e| {
        if e.to_string().ends_with("HTTP 404") {
            anyhow!("No Aikatsu plugins in that repo")
        } else if http::is_unavailable(&e) {
            anyhow!("Couldn't reach the repo. Check your connection.")
        } else {
            e
        }
    })?;
    let index: Index = serde_json::from_str(&body).context("Not an Aikatsu plugin repo")?;
    validate(&index)?;
    Ok(index)
}

fn valid_key(s: &str) -> bool {
    (1..=32).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_')
}

fn validate(index: &Index) -> Result<()> {
    anyhow::ensure!(valid_key(&index.id), "repo id {:?} must be 1-32 lowercase letters, digits, - or _", index.id);
    anyhow::ensure!(!index.name.trim().is_empty(), "repo {} has no name", index.id);
    let mut keys = HashSet::new();
    for e in &index.plugins {
        anyhow::ensure!(valid_key(&e.key) && keys.insert(&e.key), "plugin key {:?} is invalid or listed twice", e.key);
        anyhow::ensure!(!e.name.trim().is_empty(), "plugin {} has no name", e.key);
        anyhow::ensure!(e.sha256.len() == 64 && e.sha256.bytes().all(|b| b.is_ascii_hexdigit()), "plugin {} has no valid sha256", e.key);
    }
    Ok(())
}

/// Plugin ids are "<repo id>/<key>", so two repos can't share an id.
fn check_unique(url: &str, id: &str) -> Result<()> {
    for other in repo_urls().into_iter().filter(|u| u != url) {
        if saved_index(&other).is_some_and(|i| i.id == id) {
            bail!("another added repo already uses the id \"{id}\" ({other})");
        }
    }
    Ok(())
}

// Running scripts.

thread_local! {
    /// The plugin running on this thread (id, name): the name labels errors and
    /// log lines, the id keeps its cache apart.
    static RUNNING: RefCell<(String, String)> = RefCell::default();
    static DEADLINE: Cell<Option<Instant>> = const { Cell::new(None) };
    /// A request failed on the provider's side (down, blocked): the breaker counts it.
    static UNAVAILABLE: Cell<bool> = const { Cell::new(false) };
}

/// Calls a script function on a blocking thread (host functions wait on the
/// network there), stopping the script once `limit` has passed.
pub async fn call(p: &Arc<Plugin>, f: &str, args: impl FuncArgs + Send + 'static, limit: Duration) -> Result<Dynamic> {
    let (p, f) = (p.clone(), f.to_owned());
    crate::RT.spawn_blocking(move || run(&p, &f, args, limit)).await?
}

fn run(p: &Plugin, f: &str, args: impl FuncArgs, limit: Duration) -> Result<Dynamic> {
    RUNNING.set((p.id.clone(), p.name.clone()));
    DEADLINE.set(Some(Instant::now() + limit));
    UNAVAILABLE.set(false);
    let res = ENGINE.call_fn::<Dynamic>(&mut Scope::new(), &p.ast, f, args);
    DEADLINE.set(None);
    res.map_err(|e| {
        let msg = match root_error(&e) {
            EvalAltResult::ErrorTerminated(..) => return http::Unavailable(format!("{}: {f} took longer than {}s", p.name, limit.as_secs())).into(),
            EvalAltResult::ErrorRuntime(v, _) => v.to_string(),
            other => format!("{}: script error in {f}(): {other}", p.name),
        };
        if UNAVAILABLE.get() { http::Unavailable(msg).into() } else { anyhow!(msg) }
    })
}

fn root_error(e: &EvalAltResult) -> &EvalAltResult {
    match e {
        EvalAltResult::ErrorInFunctionCall(_, _, inner, _) | EvalAltResult::ErrorInModule(_, inner, _) => root_error(inner),
        e => e,
    }
}

type Res<T> = Result<T, Box<EvalAltResult>>;

fn label() -> String {
    RUNNING.with_borrow(|r| r.1.clone())
}

fn fail(e: anyhow::Error) -> Box<EvalAltResult> {
    if http::is_unavailable(&e) {
        UNAVAILABLE.set(true);
    }
    format!("{e:#}").into()
}

fn block<T>(f: impl Future<Output = T>) -> T {
    crate::RT.handle().block_on(f)
}

static ENGINE: LazyLock<Engine> = LazyLock::new(engine);

/// The whole API a plugin gets, documented for authors in Kyoko's README.
fn engine() -> Engine {
    let mut e = Engine::new();
    e.set_max_string_size(16 << 20).set_max_array_size(100_000).set_max_map_size(100_000);
    // Rhai's release-build depths; debug builds (the CLI) would otherwise halve them.
    e.set_max_expr_depths(64, 32);
    e.on_progress(|_| DEADLINE.get().filter(|d| Instant::now() > *d).map(|_| Dynamic::UNIT));
    e.on_print(|s| tracing::info!("[{}] {s}", label()));
    e.on_debug(|s, _, _| tracing::debug!("[{}] {s}", label()));

    e.register_fn("page", |url: &str| page(url, ""));
    e.register_fn("page", page);
    e.register_fn("fetch", |url: &str| fetch(url, Map::new()));
    e.register_fn("fetch", fetch);
    e.register_fn("fetch_all", |urls: Array| fetch_all(urls, Map::new()));
    e.register_fn("fetch_all", fetch_all);
    e.register_fn("playable", |url: &str| block(http::playable(url, None)));
    e.register_fn("playable", |url: &str, referer: &str| block(http::playable(url, Some(referer))));

    e.register_fn("select", select);
    e.register_fn("attr", |el: Map, name: &str| attr(&el, name));
    e.register_fn("regex_match", regex_match);
    e.register_fn("regex_replace", regex_replace);
    e.register_fn("json_parse", json_parse);
    e.register_fn("base64_decode", base64_decode);
    e.register_fn("html_decode", |s: &str| html_escape::decode_html_entities(s).into_owned());
    e.register_fn("url_encode", http::query_escape);
    e.register_fn("url_join", http::absolute);
    e.register_fn("url_parse", url_parse);
    e.register_fn("url_set_param", url_set_param);

    e.register_fn("height_of", |s: &str| height_of(s) as i64);
    e.register_fn("sort_by_height", sort_by_height_of);
    e.register_fn("clean_sub_indo", clean_sub_indo);
    e.register_fn("cache_get", cache_get);
    e.register_fn("cache_set", cache_set);
    e
}

/// A cached, challenge-checked GET (`http::page`): the HTML pages.
fn page(url: &str, referer: &str) -> Res<String> {
    let mut rb = http::CHROME.get(url);
    if !referer.is_empty() {
        rb = rb.header("Referer", referer);
    }
    block(http::page(&label(), rb)).map_err(fail)
}

fn opt(opts: &Map, key: &str) -> String {
    opts.get(key).and_then(|v| v.clone().into_string().ok()).unwrap_or_default()
}

/// `opts`: method, referer, headers #{}, form #{}, json, client ("chrome" or
/// "plain" for file hosts), redirect (false: return the 3xx itself).
fn request(url: &str, opts: &Map) -> Res<wreq::RequestBuilder> {
    let plain = match opt(opts, "client").as_str() {
        "" | "chrome" => false,
        "plain" => true,
        c => return Err(format!("unknown client {c:?}").into()),
    };
    let (form, json) = (opts.get("form"), opts.get("json"));
    let method = match opt(opts, "method") {
        m if !m.is_empty() => m.to_uppercase(),
        _ if form.is_some() || json.is_some() => "POST".into(),
        _ => "GET".into(),
    };
    let method = wreq::Method::from_bytes(method.as_bytes()).map_err(|_| format!("bad method {method:?}"))?;
    let client = if plain { &*http::PLAIN } else { &*http::CHROME };
    let mut rb = client.request(method, url);
    if plain {
        rb = rb.header("User-Agent", http::UA).timeout(Duration::from_secs(15));
    }
    let referer = opt(opts, "referer");
    if !referer.is_empty() {
        rb = rb.header("Referer", referer);
    }
    for (k, v) in opts.get("headers").and_then(|h| h.clone().try_cast::<Map>()).unwrap_or_default() {
        rb = rb.header(k.as_str(), v.to_string());
    }
    if let Some(form) = form.and_then(|f| f.clone().try_cast::<Map>()) {
        let pairs: Vec<(String, String)> = form.into_iter().map(|(k, v)| (k.into(), v.to_string())).collect();
        rb = rb.form(&pairs);
    }
    if let Some(json) = json {
        rb = rb.json(&rhai::serde::from_dynamic::<Value>(json)?);
    }
    if opts.get("redirect").and_then(|v| v.as_bool().ok()) == Some(false) {
        rb = rb.redirect(wreq::redirect::Policy::none());
    }
    Ok(rb)
}

fn response(f: http::Fetched) -> Map {
    let headers: Map = f.headers.into_iter().map(|(k, v)| (k.into(), v.into())).collect();
    Map::from_iter([
        ("status".into(), (f.status as i64).into()),
        ("headers".into(), headers.into()),
        ("url".into(), f.url.into()),
        ("body".into(), f.body.into()),
    ])
}

/// Any request; statuses from 400 throw.
fn fetch(url: &str, opts: Map) -> Res<Map> {
    let rb = request(url, &opts)?;
    block(http::fetch(&label(), rb)).map(response).map_err(fail)
}

/// The same request to several URLs, 4 at a time, answers in order.
fn fetch_all(urls: Array, opts: Map) -> Res<Array> {
    use futures_util::StreamExt;
    let rbs = urls.iter().map(|u| request(&u.to_string(), &opts)).collect::<Res<Vec<_>>>()?;
    let label = label();
    let all: Vec<Result<http::Fetched>> = block(futures_util::stream::iter(rbs).map(|rb| http::fetch(&label, rb)).buffered(4).collect());
    all.into_iter().map(|r| r.map(|f| response(f).into()).map_err(fail)).collect()
}

/// Each match as #{text, html (inner), attrs}; text and attribute values trimmed.
fn select(html: &str, css: &str) -> Res<Array> {
    let sel = scraper::Selector::parse(css).map_err(|e| format!("bad selector {css:?}: {e}"))?;
    let doc = scraper::Html::parse_document(html);
    Ok(doc
        .select(&sel)
        .map(|el| {
            let attrs: Map = el.value().attrs().map(|(k, v)| (k.into(), v.trim().into())).collect();
            Map::from_iter([
                ("text".into(), el.text().collect::<String>().trim().into()),
                ("html".into(), el.inner_html().into()),
                ("attrs".into(), attrs.into()),
            ])
            .into()
        })
        .collect())
}

/// An attribute of a `select` match, "" when missing.
fn attr(el: &Map, name: &str) -> String {
    el.get("attrs").and_then(|a| a.clone().try_cast::<Map>()).and_then(|a| a.get(name).map(|v| v.to_string())).unwrap_or_default()
}

static REGEXES: LazyLock<Mutex<HashMap<String, regex::Regex>>> = LazyLock::new(Default::default);

fn regex(pattern: &str) -> Res<regex::Regex> {
    let mut cache = REGEXES.lock().unwrap();
    if let Some(r) = cache.get(pattern) {
        return Ok(r.clone());
    }
    let r = regex::Regex::new(pattern).map_err(|e| format!("bad regex {pattern:?}: {e}"))?;
    if cache.len() >= 512 {
        cache.clear(); // scripts use a few fixed patterns; this only stops one that builds them
    }
    cache.insert(pattern.to_owned(), r.clone());
    Ok(r)
}

/// The first match as [whole, group 1, …] ("" for a group that didn't take part), or ().
fn regex_match(text: &str, pattern: &str) -> Res<Dynamic> {
    Ok(match regex(pattern)?.captures(text) {
        Some(c) => c.iter().map(|m| Dynamic::from(m.map_or("", |m| m.as_str()).to_owned())).collect::<Array>().into(),
        None => Dynamic::UNIT,
    })
}

fn regex_replace(text: &str, pattern: &str, with: &str) -> Res<String> {
    Ok(regex(pattern)?.replace_all(text, with).into_owned())
}

fn json_parse(s: &str) -> Res<Dynamic> {
    let v: Value = serde_json::from_str(s).map_err(|e| format!("{}: invalid JSON: {e}", label()))?;
    rhai::serde::to_dynamic(v)
}

fn base64_decode(s: &str) -> Res<String> {
    use base64::Engine as _;
    let raw = base64::prelude::BASE64_STANDARD.decode(s.trim()).map_err(|e| format!("invalid base64: {e}"))?;
    Ok(String::from_utf8_lossy(&raw).into_owned())
}

/// #{scheme, host (lowercase), origin, path, query: #{}}, or () when not a URL.
fn url_parse(u: &str) -> Dynamic {
    let Ok(u) = url::Url::parse(u) else { return Dynamic::UNIT };
    let query: Map = u.query_pairs().map(|(k, v)| (k.as_ref().into(), v.into_owned().into())).collect();
    Map::from_iter([
        ("scheme".into(), u.scheme().into()),
        ("host".into(), u.host_str().unwrap_or_default().to_lowercase().into()),
        ("origin".into(), u.origin().ascii_serialization().into()),
        ("path".into(), u.path().into()),
        ("query".into(), query.into()),
    ])
    .into()
}

/// `u` with `key` set to `value` (moved to the end of the query).
fn url_set_param(u: &str, key: &str, value: &str) -> String {
    let Ok(mut url) = url::Url::parse(u) else { return u.to_owned() };
    let pairs: Vec<(String, String)> = url.query_pairs().filter(|(k, _)| k != key).map(|(k, v)| (k.into_owned(), v.into_owned())).collect();
    url.query_pairs_mut().clear().extend_pairs(pairs).append_pair(key, value);
    url.into()
}

/// Strings by their height ("720p"), maps by their `height` field.
fn sort_by_height_of(mut items: Array, quality: &str) -> Array {
    let height = |x: &Dynamic| match x.read_lock::<Map>() {
        Some(m) => m.get("height").and_then(|v| v.as_int().ok()).unwrap_or(0).clamp(0, u32::MAX as i64) as u32,
        None => height_of(&x.to_string()),
    };
    sort_by_height(&mut items, height_of(quality), height);
    items
}

/// Per plugin, in memory, at most an hour: a page or decrypted data that
/// `heights` and `stream` both need.
static CACHE: LazyLock<Mutex<HashMap<String, (Dynamic, Instant)>>> = LazyLock::new(Default::default);
const CACHE_ENTRIES: usize = 128;

fn cache_key(key: &str) -> String {
    RUNNING.with_borrow(|r| format!("{}\n{key}", r.0))
}

fn cache_get(key: &str) -> Dynamic {
    let mut cache = CACHE.lock().unwrap();
    cache.retain(|_, (_, until)| *until > Instant::now());
    cache.get(&cache_key(key)).map(|(v, _)| v.clone()).unwrap_or(Dynamic::UNIT)
}

fn cache_set(key: &str, value: Dynamic, ttl_secs: i64) {
    let until = Instant::now() + Duration::from_secs(ttl_secs.clamp(0, 3600) as u64);
    let mut cache = CACHE.lock().unwrap();
    if cache.len() >= CACHE_ENTRIES
        && let Some(soonest) = cache.iter().min_by_key(|(_, (_, u))| *u).map(|(k, _)| k.clone())
    {
        cache.remove(&soonest);
    }
    cache.insert(cache_key(key), (value.flatten(), until));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn script(body: &str) -> Arc<Plugin> {
        let stubs = "fn search(q) {[]} fn episodes(u) {[]} fn heights(u) {[]} fn stream(u, q) {#{}}";
        Arc::new(Plugin::from_script("t", stubs, body).unwrap())
    }

    fn eval(p: &Arc<Plugin>, f: &str) -> Result<Dynamic> {
        crate::RT.block_on(call(p, f, (), Duration::from_secs(5)))
    }

    #[test]
    fn host_helpers() {
        let p = script(
            r##"
            fn sel() {
                let a = select(`<ul><li><a href=" /x ">One <b>Piece</b></a></li><li><a>two</a></li></ul>`, "li a");
                [a.len(), a[0].text, attr(a[0], "href"), attr(a[1], "href"), a[0].html]
            }
            fn re() { [regex_match("Episode 12 END", #"(?i)episode\s*(\d+)"#), regex_match("x", #"(\d+)"#), regex_replace("a1b22", #"\d+"#, "#")] }
            fn urls() {
                let u = url_parse("https://Ylnime.com/watch?series=a&reso=360p");
                [u.host, u.origin, u.query.series, url_set_param("https://y.com/w?reso=360p&e=1", "reso", "720p"), url_join("https://a.com/x/", "../i.jpg"), url_parse("nope")]
            }
            fn misc() { [base64_decode("aGk="), json_parse(`{"a":[1,"b"]}`).a[1], height_of("MKV 1080p"), sort_by_height(["360p", "1080p", "720p"], "720p"), sort_by_height([#{height: 480}, #{height: 1080}], "best")[0].height] }
            fn caching() { cache_set("k", [1, 2], 60); cache_get("k").len() + if cache_get("missing") == () { 10 } else { 0 } }
            fn boom() { throw "T: nothing here"; }
            fn forever() { loop {} }
            "##,
        );
        let v = |f| serde_json::to_value(eval(&p, f).unwrap()).unwrap();
        assert_eq!(v("sel"), json!([2, "One Piece", "/x", "", "One <b>Piece</b>"]));
        assert_eq!(v("re"), json!([["Episode 12", "12"], null, "a#b#"]));
        assert_eq!(
            v("urls"),
            json!(["ylnime.com", "https://ylnime.com", "a", "https://y.com/w?e=1&reso=720p", "https://a.com/i.jpg", null])
        );
        assert_eq!(v("misc"), json!(["hi", "b", 1080, ["720p", "1080p", "360p"], 1080]));
        assert_eq!(v("caching"), json!(12));
        assert_eq!(eval(&p, "boom").unwrap_err().to_string(), "T: nothing here");
        let slow = crate::RT.block_on(call(&p, "forever", (), Duration::from_millis(200))).unwrap_err();
        assert!(http::is_unavailable(&slow), "{slow}");
    }

    #[test]
    fn scripts_must_define_the_source_functions() {
        assert!(compile("fn search(q) {[]}").unwrap_err().to_string().contains("episodes()"));
        assert!(compile("fn search(q) {").is_err());
    }

    #[test]
    fn add_update_and_remove_a_repo() {
        let dir = std::env::temp_dir().join(format!("aikatsu-repo-test-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("sources")).unwrap();
        let v1 = r#"fn search(q) {cache_set("old", "old", 3600); []} fn episodes(u) {[]} fn heights(u) {[]} fn stream(u, q) {#{}}"#;
        let publish = |script: &str, sha: &str| {
            std::fs::write(dir.join("sources/a.rhai"), script).unwrap();
            let index = json!({ "id": "test-repo", "name": "Test", "plugins": [{ "key": "a", "name": "A", "file": "sources/a.rhai", "sha256": sha }] });
            std::fs::write(dir.join("index.json"), index.to_string()).unwrap();
        };
        publish(v1, &sha256_hex(v1.as_bytes()));
        let url = url::Url::from_file_path(dir.join("index.json")).unwrap().to_string();
        let before = repo_urls();
        let developer_mode = crate::api::setting("developerMode");
        set_repo_urls(&[]).unwrap();
        crate::RT.block_on(async {
            crate::api::get("setSetting", json!({ "key": "developerMode", "value": "false" })).unwrap();
            assert!(preview(&url).await.unwrap_err().to_string().contains("Developer Mode"));
            assert!(add(&url).await.unwrap_err().to_string().contains("Developer Mode"));
            assert!(repo_urls().is_empty() && !repo_dir(&url).exists());
            crate::api::get("setSetting", json!({ "key": "developerMode", "value": "true" })).unwrap();
            assert_eq!(preview(&url).await.unwrap()["plugins"][0]["name"], "A");
            let added = crate::api::call("addRepo", json!({ "url": url })).await.unwrap();
            assert_eq!(added[0]["plugins"][0]["loaded"], true);
            assert!(find("test-repo/a").is_some());
            assert!(preview(&url).await.is_err() && add(&url).await.is_err(), "already added");
            assert_eq!(crate::api::call("syncPlugins", json!({})).await.unwrap()["updated"], false);
            crate::sources::search("test-repo/a", "query").await.unwrap();

            // The index moved on but the script didn't (a CDN mid-update): refused, v1 stays.
            publish(v1, &"0".repeat(64));
            let failed = crate::api::call("syncPlugins", json!({})).await.unwrap();
            assert!(failed["repos"][0]["error"].as_str().unwrap().contains("checksum"));
            assert_eq!(std::fs::read_to_string(script_path(&url, "a")).unwrap(), v1);

            crate::sources::search("test-repo/a", "query").await.unwrap();
            let v2 = v1.replace("cache_set(\"old\", \"old\", 3600);", "if cache_get(\"old\") != () {throw \"stale cache\";}");
            publish(&v2, &sha256_hex(v2.as_bytes()));
            let installed_index = std::fs::read(repo_dir(&url).join("index.json")).unwrap();
            let checked = crate::api::call("checkPluginUpdates", json!({})).await.unwrap();
            assert_eq!(checked[0]["updates"], 1);
            assert_eq!(std::fs::read_to_string(script_path(&url, "a")).unwrap(), v1, "checking must not download scripts");
            assert_eq!(std::fs::read(repo_dir(&url).join("index.json")).unwrap(), installed_index, "checking must not replace installed metadata");
            crate::sources::search("test-repo/a", "query").await.unwrap();
            let synced = crate::api::call("syncPlugins", json!({})).await.unwrap();
            assert_eq!(synced["updated"], true, "changed hashes update even without a version bump");
            assert_eq!(synced["repos"][0]["error"], Value::Null);
            assert_eq!(synced["repos"][0]["updates"], 0);
            assert_eq!(std::fs::read_to_string(script_path(&url, "a")).unwrap(), v2);
            crate::sources::search("test-repo/a", "query").await.unwrap();
            assert_eq!(crate::api::call("syncPlugins", json!({})).await.unwrap()["updated"], false);

            let mut index: Value = serde_json::from_str(&std::fs::read_to_string(dir.join("index.json")).unwrap()).unwrap();
            let mut b = index["plugins"][0].clone();
            b["key"] = json!("b");
            b["name"] = json!("B");
            index["plugins"].as_array_mut().unwrap().push(b);
            std::fs::write(dir.join("index.json"), index.to_string()).unwrap();
            assert_eq!(crate::api::call("checkPluginUpdates", json!({})).await.unwrap()[0]["updates"], 1);
            assert!(find("test-repo/b").is_none() && !script_path(&url, "b").exists());
            let synced = crate::api::call("syncPlugins", json!({})).await.unwrap();
            assert_eq!(synced["updated"], true);
            assert_eq!(synced["repos"][0]["plugins"][1]["loaded"], true, "new sources are ready in the returned list");
            assert!(find("test-repo/b").is_some());
            index["plugins"].as_array_mut().unwrap().pop();
            std::fs::write(dir.join("index.json"), index.to_string()).unwrap();
            assert_eq!(crate::api::call("checkPluginUpdates", json!({})).await.unwrap()[0]["updates"], 1);
            assert!(find("test-repo/b").is_some(), "checking must not remove installed plugins");
            assert_eq!(crate::api::call("syncPlugins", json!({})).await.unwrap()["updated"], true);
            assert!(find("test-repo/b").is_none());
            crate::api::get("setSetting", json!({ "key": "developerMode", "value": "false" })).unwrap();
            assert!(find("test-repo/a").is_some(), "turning off Developer Mode keeps installed sources");
            let blocked = crate::api::call("syncPlugins", json!({})).await.unwrap();
            assert_eq!(blocked["updated"], false);
            assert!(blocked["repos"][0]["error"].as_str().unwrap().contains("Developer Mode"));
            assert_eq!(std::fs::read_to_string(script_path(&url, "a")).unwrap(), v2);
        });
        crate::RT.block_on(crate::api::call("removeRepo", json!({ "url": url }))).unwrap();
        assert!(find("test-repo/a").is_none() && !repo_dir(&url).exists());
        set_repo_urls(&before).unwrap();
        db::set_setting("developerMode", &developer_mode).unwrap();
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn repo_requests_bypass_cdn_cache_and_keep_query_parameters() {
        let url = url::Url::parse("https://raw.githubusercontent.com/User/Repo/HEAD/index.json?token=example").unwrap();
        let first = repo_request(url.clone()).build().unwrap();
        let second = repo_request(url).build().unwrap();
        let fresh = url::Url::parse(&first.uri().to_string()).unwrap();
        assert_eq!(fresh.path(), "/User/Repo/HEAD/index.json");
        assert!(fresh.query_pairs().any(|(k, v)| k == "token" && v == "example"));
        assert!(fresh.query_pairs().any(|(k, v)| k == "_aikatsu" && !v.is_empty()));
        assert_ne!(first.uri(), second.uri());
        assert_eq!(first.headers()["cache-control"], "no-cache");
    }

    #[test]
    fn repo_links() {
        for input in ["github.com/User/My.Repo", "https://github.com/User/My.Repo/", " https://www.github.com/User/My.Repo.git ", "https://github.com/User/My.Repo/tree/dev"] {
            assert_eq!(canonical(input).unwrap(), "https://github.com/User/My.Repo", "{input}");
        }
        assert_eq!(index_url("https://github.com/User/My.Repo"), "https://raw.githubusercontent.com/User/My.Repo/HEAD/index.json");
        assert_eq!(canonical("file:///tmp/repo/index.json/").unwrap(), "file:///tmp/repo/index.json");
        assert_eq!(short(OFFICIAL_REPO), "KidiXDev/kyoko");
        for bad in ["", "https://gitlab.com/a/b", "github.com/onlyowner", "github.com/a/b?x=1", "github.com/../b"] {
            assert!(canonical(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn index_validation() {
        let entry = |key: &str| Entry { key: key.into(), name: "N".into(), version: 1, api: 1, file: "a.rhai".into(), sha256: "a".repeat(64) };
        let ok = Index { id: "kyoko".into(), name: "Kyoko".into(), plugins: vec![entry("otakudesu"), entry("samehadaku")] };
        assert!(validate(&ok).is_ok());
        assert!(validate(&Index { id: "Kyoko/x".into(), ..ok.clone() }).is_err());
        assert!(validate(&Index { plugins: vec![entry("a"), entry("a")], ..ok.clone() }).is_err());
        assert!(validate(&Index { plugins: vec![Entry { sha256: "xyz".into(), ..entry("a") }], ..ok }).is_err());
    }
}
