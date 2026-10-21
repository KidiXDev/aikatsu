//! Anime details: AniList first, Jikan as the fallback and for episode titles,
//! TMDB for season splits (optional), AniSkip for opening/ending times.

use crate::http::{self, API_UA};
use anyhow::{Result, anyhow};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::sync::LazyLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct SeasonRange {
    pub season: u32,
    pub start: u32,
    pub end: u32,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct NextAiring {
    pub episode: i64,
    pub airing_at: i64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct CharacterEntry {
    pub id: i64,
    pub name: String,
    pub native_name: String,
    pub image: String,
    pub role: String,
    pub va_name: String,
    pub va_native_name: String,
    pub va_image: String,
    pub va_language: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct StaffEntry {
    pub id: i64,
    pub name: String,
    pub native_name: String,
    pub image: String,
    pub role: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct RelatedAnime {
    pub anilist_id: i64,
    pub mal_id: i64,
    pub media_type: String,
    pub relation: String,
    pub title_romaji: String,
    pub title_english: String,
    pub cover: String,
    pub format: String,
    pub status: String,
    pub episodes: i64,
    pub year: i64,
    pub score: i64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct RecommendedAnime {
    pub anilist_id: i64,
    pub mal_id: i64,
    pub title_romaji: String,
    pub title_english: String,
    pub cover: String,
    pub format: String,
    pub episodes: i64,
    pub year: i64,
    pub score: i64,
    pub rating: i64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
pub struct MediaTag {
    pub name: String,
    pub rank: i64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Meta {
    pub anilist_id: i64,
    pub mal_id: i64,
    pub title_romaji: String,
    pub title_english: String,
    pub title_native: String,
    pub cover: String,
    pub banner: String,
    pub color: String,
    pub description: String,
    pub genres: Vec<String>,
    pub score: i64,
    pub episodes: i64,
    pub year: i64,
    pub status: String,
    pub season_map: Vec<SeasonRange>,
    #[serde(default)]
    pub format: String,
    #[serde(default)]
    pub season: String,
    #[serde(default)]
    pub season_year: i64,
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub start_date: String,
    #[serde(default)]
    pub end_date: String,
    #[serde(default)]
    pub mean_score: i64,
    #[serde(default)]
    pub popularity: i64,
    #[serde(default)]
    pub favourites: i64,
    #[serde(default)]
    pub hashtag: String,
    #[serde(default)]
    pub country_of_origin: String,
    #[serde(default)]
    pub synonyms: Vec<String>,
    #[serde(default)]
    pub studios: Vec<String>,
    #[serde(default)]
    pub producers: Vec<String>,
    #[serde(default)]
    pub next_airing: Option<NextAiring>,
    #[serde(default)]
    pub tags: Vec<MediaTag>,
    #[serde(default)]
    pub characters: Vec<CharacterEntry>,
    #[serde(default)]
    pub staff: Vec<StaffEntry>,
    #[serde(default)]
    pub relations: Vec<RelatedAnime>,
    #[serde(default)]
    pub recommendations: Vec<RecommendedAnime>,
}

impl Meta {
    /// Absolute episode → (season, episode in season). Without a map, season 1.
    pub fn absolute_to_season(&self, ep: u32) -> (u32, u32) {
        let Some(last) = self.season_map.last() else { return (1, ep) };
        self.season_map
            .iter()
            .find(|s| ep >= s.start && ep <= s.end)
            .map(|s| (s.season, ep - s.start + 1))
            .unwrap_or((last.season, ep.saturating_sub(last.start) + 1))
    }

    pub fn title(&self) -> &str {
        if !self.title_english.is_empty() { &self.title_english } else { &self.title_romaji }
    }
}

pub(crate) const ANILIST: &str = "https://graphql.anilist.co";
const MEDIA_FIELDS: &str = "id idMal title { romaji english native } coverImage { extraLarge large color } bannerImage
    description(asHtml: false) genres synonyms format status source(version: 3) season seasonYear episodes duration
    averageScore meanScore popularity favourites hashtag countryOfOrigin
    startDate { year month day } endDate { year month day }
    nextAiringEpisode { episode airingAt }
    studios { edges { isMain node { name } } }
    tags { name rank isMediaSpoiler isGeneralSpoiler }
    characters(sort: [ROLE, RELEVANCE, ID], perPage: 18) {
        edges {
            role
            node { id name { full native } image { large medium } }
            voiceActors(language: JAPANESE, sort: [RELEVANCE, ID]) { id name { full native } image { large medium } languageV2 }
        }
    }
    staff(sort: [RELEVANCE, ID], perPage: 12) {
        edges {
            role
            node { id name { full native } image { large medium } }
        }
    }
    relations {
        edges {
            relationType(version: 2)
            node { id idMal type title { romaji english } format status episodes averageScore coverImage { large medium } startDate { year month } }
        }
    }
    recommendations(sort: [RATING_DESC, ID], perPage: 10) {
        nodes {
            rating
            mediaRecommendation { id idMal type title { romaji english } format status episodes averageScore seasonYear coverImage { large medium } }
        }
    }";

async fn anilist(query: &str, variables: Value) -> Result<Value> {
    let resp = http::PLAIN
        .post(ANILIST)
        .header("User-Agent", API_UA)
        .header("Accept", "application/json")
        .json(&json!({ "query": query, "variables": variables }))
        .timeout(Duration::from_secs(20))
        .send()
        .await?;
    let status = resp.status();
    let body: Value = resp.json().await?;
    // A search with no match is 404 + `Media: null`: try the next term, not an outage.
    anyhow::ensure!(status.is_success() || status.as_u16() == 404, "AniList returned {status}");
    Ok(body)
}

fn format_fuzzy_date(d: &Value) -> String {
    const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    let y = d["year"].as_i64().unwrap_or(0);
    let m = d["month"].as_u64().unwrap_or(0) as usize;
    let day = d["day"].as_i64().unwrap_or(0);
    match (y > 0, (1..=12).contains(&m), day > 0) {
        (true, true, true) => format!("{} {day}, {y}", MONTHS[m - 1]),
        (true, true, false) => format!("{} {y}", MONTHS[m - 1]),
        (true, false, _) => y.to_string(),
        _ => String::new(),
    }
}

fn parse_media(m: &Value) -> Option<Meta> {
    let id = m["id"].as_i64().filter(|&id| id > 0)?;
    let s = |v: &Value| v.as_str().unwrap_or_default().to_owned();
    let img = |v: &Value| v["extraLarge"].as_str().or(v["large"].as_str()).or(v["medium"].as_str()).unwrap_or_default().to_owned();
    let episodes = m["episodes"].as_i64().unwrap_or(0);

    let mut studios = Vec::new();
    let mut producers = Vec::new();
    for edge in m["studios"]["edges"].as_array().into_iter().flatten() {
        let name = s(&edge["node"]["name"]);
        if name.is_empty() {
            continue;
        }
        if edge["isMain"].as_bool().unwrap_or(false) {
            if !studios.contains(&name) {
                studios.push(name);
            }
        } else if !producers.contains(&name) {
            producers.push(name);
        }
    }

    let next_airing = m["nextAiringEpisode"]["episode"].as_i64().and_then(|ep| {
        let at = m["nextAiringEpisode"]["airingAt"].as_i64()?;
        Some(NextAiring { episode: ep, airing_at: at })
    });

    let tags = m["tags"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|t| !t["isMediaSpoiler"].as_bool().unwrap_or(false) && !t["isGeneralSpoiler"].as_bool().unwrap_or(false))
        .filter_map(|t| {
            let name = t["name"].as_str()?.trim().to_owned();
            if name.is_empty() {
                return None;
            }
            Some(MediaTag { name, rank: t["rank"].as_i64().unwrap_or(0) })
        })
        .take(12)
        .collect();

    let characters = m["characters"]["edges"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|edge| {
            let node = &edge["node"];
            let name = s(&node["name"]["full"]);
            if name.is_empty() {
                return None;
            }
            let va = edge["voiceActors"].as_array().and_then(|v| v.first());
            Some(CharacterEntry {
                id: node["id"].as_i64().unwrap_or(0),
                name,
                native_name: s(&node["name"]["native"]),
                image: img(&node["image"]),
                role: s(&edge["role"]),
                va_name: va.map(|v| s(&v["name"]["full"])).unwrap_or_default(),
                va_native_name: va.map(|v| s(&v["name"]["native"])).unwrap_or_default(),
                va_image: va.map(|v| img(&v["image"])).unwrap_or_default(),
                va_language: va.map(|v| s(&v["languageV2"])).unwrap_or_default(),
            })
        })
        .collect();

    let staff = m["staff"]["edges"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|edge| {
            let node = &edge["node"];
            let name = s(&node["name"]["full"]);
            if name.is_empty() {
                return None;
            }
            Some(StaffEntry {
                id: node["id"].as_i64().unwrap_or(0),
                name,
                native_name: s(&node["name"]["native"]),
                image: img(&node["image"]),
                role: s(&edge["role"]),
            })
        })
        .collect();

    let relations = m["relations"]["edges"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|edge| {
            let node = &edge["node"];
            let rel_id = node["id"].as_i64().filter(|&x| x > 0)?;
            let title_romaji = s(&node["title"]["romaji"]);
            let title_english = s(&node["title"]["english"]);
            if title_romaji.is_empty() && title_english.is_empty() {
                return None;
            }
            Some(RelatedAnime {
                anilist_id: rel_id,
                mal_id: node["idMal"].as_i64().unwrap_or(0),
                media_type: s(&node["type"]),
                relation: s(&edge["relationType"]),
                title_romaji,
                title_english,
                cover: img(&node["coverImage"]),
                format: s(&node["format"]),
                status: s(&node["status"]),
                episodes: node["episodes"].as_i64().unwrap_or(0),
                year: node["startDate"]["year"].as_i64().unwrap_or(0),
                score: node["averageScore"].as_i64().unwrap_or(0),
            })
        })
        .collect();

    let recommendations = m["recommendations"]["nodes"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|n| {
            let rec = &n["mediaRecommendation"];
            let rec_id = rec["id"].as_i64().filter(|&x| x > 0)?;
            let title_romaji = s(&rec["title"]["romaji"]);
            let title_english = s(&rec["title"]["english"]);
            if title_romaji.is_empty() && title_english.is_empty() {
                return None;
            }
            Some(RecommendedAnime {
                anilist_id: rec_id,
                mal_id: rec["idMal"].as_i64().unwrap_or(0),
                title_romaji,
                title_english,
                cover: img(&rec["coverImage"]),
                format: s(&rec["format"]),
                episodes: rec["episodes"].as_i64().unwrap_or(0),
                year: rec["seasonYear"].as_i64().unwrap_or(0),
                score: rec["averageScore"].as_i64().unwrap_or(0),
                rating: n["rating"].as_i64().unwrap_or(0),
            })
        })
        .collect();

    let year = m["seasonYear"].as_i64().filter(|&y| y > 0).unwrap_or_else(|| m["startDate"]["year"].as_i64().unwrap_or(0));
    let mut meta = Meta {
        anilist_id: id,
        mal_id: m["idMal"].as_i64().unwrap_or(0),
        title_romaji: s(&m["title"]["romaji"]),
        title_english: s(&m["title"]["english"]),
        title_native: s(&m["title"]["native"]),
        cover: img(&m["coverImage"]),
        banner: s(&m["bannerImage"]),
        color: s(&m["coverImage"]["color"]),
        description: strip_html(&s(&m["description"])),
        genres: m["genres"].as_array().map(|g| g.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect()).unwrap_or_default(),
        score: m["averageScore"].as_i64().unwrap_or(0),
        episodes,
        year,
        status: s(&m["status"]),
        season_map: Vec::new(),
        format: s(&m["format"]),
        season: s(&m["season"]),
        season_year: m["seasonYear"].as_i64().unwrap_or(year),
        duration: m["duration"].as_i64().unwrap_or(0),
        source: s(&m["source"]),
        start_date: format_fuzzy_date(&m["startDate"]),
        end_date: format_fuzzy_date(&m["endDate"]),
        mean_score: m["meanScore"].as_i64().unwrap_or(0),
        popularity: m["popularity"].as_i64().unwrap_or(0),
        favourites: m["favourites"].as_i64().unwrap_or(0),
        hashtag: s(&m["hashtag"]),
        country_of_origin: s(&m["countryOfOrigin"]),
        synonyms: m["synonyms"].as_array().map(|g| g.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect()).unwrap_or_default(),
        studios,
        producers,
        next_airing,
        tags,
        characters,
        staff,
        relations,
        recommendations,
    };
    meta.season_map = season_map_from_relations(episodes, &m["relations"]["edges"]);
    Some(meta)
}

/// Season 1 = this entry; later seasons = SEQUEL relations (no specials/OVAs)
/// ordered by start date. Empty when there are no sequels.
fn season_map_from_relations(episodes: i64, edges: &Value) -> Vec<SeasonRange> {
    if episodes <= 0 {
        return Vec::new();
    }
    let mut sequels: Vec<(i64, i64, i64)> = edges
        .as_array()
        .into_iter()
        .flatten()
        .filter(|e| e["relationType"] == "SEQUEL")
        .map(|e| &e["node"])
        .filter(|n| n["episodes"].as_i64().unwrap_or(0) > 0 && !matches!(n["format"].as_str(), Some("SPECIAL" | "OVA")))
        .map(|n| (n["startDate"]["year"].as_i64().unwrap_or(0), n["startDate"]["month"].as_i64().unwrap_or(0), n["episodes"].as_i64().unwrap_or(0)))
        .collect();
    if sequels.is_empty() {
        return Vec::new();
    }
    sequels.sort_by_key(|&(y, m, _)| (y, m));
    let mut out = vec![SeasonRange { season: 1, start: 1, end: episodes as u32 }];
    let mut next = episodes as u32 + 1;
    for (i, (_, _, eps)) in sequels.into_iter().enumerate() {
        out.push(SeasonRange { season: i as u32 + 2, start: next, end: next + eps as u32 - 1 });
        next += eps as u32;
    }
    out
}

static TAG_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<[^>]+>").unwrap());
fn strip_html(s: &str) -> String {
    html_escape::decode_html_entities(&TAG_RE.replace_all(&s.replace("<br>", "\n"), "")).trim().to_owned()
}


static NOISE_RES: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    [
        r"(?i)[🔥🌐]?\[[^\]]*\]\s*",
        r"\s*[–—]\s+.*$",
        r"(?i)\s+-\s+(?:sub|dub|episode\s*\d+|ep\s*\d+|season\s*\d+|\d+(?:st|nd|rd|th)\s*season|part\s*\d+).*$",
        r"(?i)\s*\([^)]*(?:dub|sub)[^)]*\)",
        r"(?i)\s+(?:subtitle\s+indonesia|sub\s+indo)\s*$",
        r"(?i)\s+(?:episode|ep)\s*\d+(?:\s*-\s*\d+)?\s*$",
        r"(?i)\s*\(\d+\s+(?:episodes?|eps?)\)",
    ]
    .iter()
    .map(|r| Regex::new(r).unwrap())
    .collect()
});

pub fn clean_title(title: &str) -> String {
    let mut s = title.to_owned();
    for re in NOISE_RES.iter() {
        s = re.replace_all(&s, "").trim().to_owned();
    }
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

static ROMAN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+(?:II|III|IV|V|VI|VII|VIII|IX|X)\s*$").unwrap());
static TRAILING_NUM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+\d+\s*$").unwrap());
static SEASON_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(.+?)\s+(?:s|season\s*)(\d{1,2})$").unwrap());
static SLUG_NOISE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)(?:-(?:sub-indo|subtitle-indonesia|episode-\d+|eps?-\d+|batch))+$").unwrap());

fn title_case(s: &str) -> String {
    s.split_whitespace()
        .map(|w| {
            let mut c = w.chars();
            c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
        })
        .collect::<Vec<String>>()
        .join(" ")
}

fn variations(name: &str, url: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut add = |v: String| {
        let v = v.trim().to_owned();
        if !v.is_empty() && !out.iter().any(|o| o.eq_ignore_ascii_case(&v)) {
            out.push(v);
        }
    };
    add(name.to_owned());
    // "Title S2" → AniList's "Title Season 2" / "Title 2nd Season", ahead of the
    // shortened variations below that would match season 1.
    if let Some(c) = SEASON_RE.captures(name) {
        let n: u32 = c[2].parse().unwrap_or(0);
        let suffix = match n % 10 {
            _ if (11..=13).contains(&(n % 100)) => "th",
            1 => "st",
            2 => "nd",
            3 => "rd",
            _ => "th",
        };
        add(format!("{} Season {n}", &c[1]));
        add(format!("{} {n}{suffix} Season", &c[1]));
    }
    // URL slug romaji, e.g. /anime/kimetsu-no-yaiba-sub-indo/ → "kimetsu no yaiba"
    if let Some(slug) = url::Url::parse(url).ok().and_then(|u| u.path_segments()?.rev().find(|s| !s.is_empty()).map(str::to_owned))
        && slug != "anime"
    {
        let romaji = SLUG_NOISE_RE.replace(&slug, "").replace('-', " ");
        add(romaji.clone());
        add(title_case(&romaji));
    }
    if name == name.to_lowercase() {
        add(title_case(name));
    }
    if let Some((before, _)) = name.split_once(':') {
        add(before.to_owned());
    }
    add(ROMAN_RE.replace(name, "").into_owned());
    add(TRAILING_NUM_RE.replace(name, "").into_owned());
    add(name.replace(" no ", " "));
    if name.to_lowercase().starts_with("the ") {
        add(name[4..].to_owned());
    }
    let words: Vec<&str> = name.split_whitespace().collect();
    if words.len() > 4 {
        add(words[..3].join(" "));
        add(words[..4].join(" "));
    }
    out
}

/// AniList lookup by name (trying search variations), falling back to Jikan
/// when AniList is down or has no match.
pub async fn enrich(name: &str, source_url: &str) -> Result<Meta> {
    let clean = clean_title(name);
    let query = format!("query ($search: String) {{ Media(search: $search, type: ANIME) {{ {MEDIA_FIELDS} }} }}");
    let mut last = anyhow!("no matching anime found on AniList");
    for term in variations(&clean, source_url) {
        match anilist(&query, json!({ "search": term })).await {
            Ok(v) => {
                if let Some(m) = parse_media(&v["data"]["Media"]) {
                    return Ok(m);
                }
            }
            Err(e) => {
                last = e;
                break; // AniList itself is failing: go to Jikan
            }
        }
    }
    tracing::debug!("AniList enrichment failed ({last}); trying Jikan");
    jikan_search(&clean).await
}

pub async fn by_anilist_id(id: i64) -> Result<Meta> {
    let query = format!("query ($id: Int) {{ Media(id: $id, type: ANIME) {{ {MEDIA_FIELDS} }} }}");
    parse_media(&anilist(&query, json!({ "id": id })).await?["data"]["Media"]).ok_or_else(|| anyhow!("no AniList result for ID {id}"))
}

/// A scheduled episode from AniList's airing calendar.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Airing {
    pub episode: i64,
    pub airing_at: i64, // unix seconds
    pub anime: Meta,
}

/// What's going on in anime, for a Home that isn't empty on a fresh install.
/// Information only: the sources may not carry a show, so the user still searches.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Discover {
    /// The last and the next 24 hours, oldest first; the UI splits aired from upcoming.
    pub schedule: Vec<Airing>,
    pub trending: Vec<Meta>,
    /// Not yet released, most anticipated first.
    pub coming_soon: Vec<Meta>,
}

/// MEDIA_FIELDS without relations (lists don't need season maps), plus isAdult:
/// the airing calendar has no filter for it.
const LIST_FIELDS: &str = "id idMal title { romaji english native } coverImage { extraLarge large color } bannerImage
    description(asHtml: false) genres averageScore episodes status startDate { year month } isAdult";

pub async fn discover() -> Result<Discover> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64;
    let query = format!(
        "query ($dayAgo: Int, $now: Int, $dayAhead: Int) {{
            aired: Page(perPage: 50) {{ airingSchedules(airingAt_greater: $dayAgo, airingAt_lesser: $now, sort: TIME_DESC) {{ episode airingAt media {{ {LIST_FIELDS} }} }} }}
            next: Page(perPage: 50) {{ airingSchedules(airingAt_greater: $now, airingAt_lesser: $dayAhead, sort: TIME) {{ episode airingAt media {{ {LIST_FIELDS} }} }} }}
            trending: Page(perPage: 20) {{ media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {{ {LIST_FIELDS} }} }}
            comingSoon: Page(perPage: 20) {{ media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC, isAdult: false) {{ {LIST_FIELDS} }} }}
        }}"
    );
    let v = anilist(&query, json!({ "dayAgo": now - 86400, "now": now, "dayAhead": now + 86400 })).await?;
    anyhow::ensure!(v["data"].is_object(), "AniList returned no data: {}", v["errors"]);
    Ok(parse_discover(&v["data"]))
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Upcoming {
    pub anilist_id: i64,
    pub episode: i64,
    pub airing_at: i64, // unix seconds
}

/// The next two weeks of episodes for these shows, soonest first, at most 100
/// (Android keeps only about 500 alarms per app).
pub async fn upcoming(ids: &[i64]) -> Result<Vec<Upcoming>> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64;
    let query = "query ($ids: [Int], $now: Int, $until: Int, $page: Int) { Page(perPage: 50, page: $page) { pageInfo { hasNextPage }
        airingSchedules(mediaId_in: $ids, airingAt_greater: $now, airingAt_lesser: $until, sort: TIME) { episode airingAt mediaId } } }";
    let mut out = Vec::new();
    for page in 1..=2 {
        let v = anilist(query, json!({ "ids": ids, "now": now, "until": now + 14 * 86400, "page": page })).await?;
        anyhow::ensure!(v["data"].is_object(), "AniList returned no data: {}", v["errors"]);
        let p = &v["data"]["Page"];
        out.extend(p["airingSchedules"].as_array().into_iter().flatten().filter_map(|s| {
            Some(Upcoming { anilist_id: s["mediaId"].as_i64()?, episode: s["episode"].as_i64()?, airing_at: s["airingAt"].as_i64()? })
        }));
        if p["pageInfo"]["hasNextPage"] != true {
            break;
        }
    }
    Ok(out)
}

pub async fn search(query: &str) -> Result<Vec<Meta>> {
    let query = query.trim();
    if query.is_empty() {
        return Ok(Vec::new());
    }
    let q = format!("query ($search: String) {{ Page(perPage: 12) {{ media(search: $search, type: ANIME) {{ {LIST_FIELDS} }} }} }}");
    let v = anilist(&q, json!({ "search": query })).await?;
    anyhow::ensure!(v["data"].is_object(), "AniList returned no data: {}", v["errors"]);
    Ok(v["data"]["Page"]["media"].as_array().into_iter().flatten().filter_map(parse_media).collect())
}

fn parse_discover(d: &Value) -> Discover {
    let media = |page: &Value| -> Vec<Meta> { page["media"].as_array().into_iter().flatten().filter_map(parse_media).collect() };
    let mut schedule: Vec<Airing> = ["aired", "next"]
        .iter()
        .flat_map(|k| d[k]["airingSchedules"].as_array().into_iter().flatten())
        .filter(|s| s["media"]["isAdult"].as_bool() != Some(true))
        .filter_map(|s| Some(Airing { episode: s["episode"].as_i64()?, airing_at: s["airingAt"].as_i64()?, anime: parse_media(&s["media"])? }))
        .collect();
    schedule.sort_by_key(|a| a.airing_at);
    Discover { schedule, trending: media(&d["trending"]), coming_soon: media(&d["comingSoon"]) }
}

async fn jikan(path: &str) -> Result<Value> {
    let resp = http::PLAIN.get(format!("https://api.jikan.moe/v4{path}")).header("User-Agent", API_UA).timeout(Duration::from_secs(15)).send().await?;
    anyhow::ensure!(resp.status().is_success(), "Jikan returned {}", resp.status());
    Ok(resp.json().await?)
}

async fn jikan_search(name: &str) -> Result<Meta> {
    let v = jikan(&format!("/anime?q={}&limit=1", http::query_escape(name))).await?;
    let a = v["data"].get(0).ok_or_else(|| anyhow!("no Jikan result for {name:?}"))?;
    let s = |v: &Value| v.as_str().unwrap_or_default().to_owned();
    let names = |v: &Value| -> Vec<String> {
        v.as_array().map(|arr| arr.iter().filter_map(|x| x["name"].as_str().map(str::to_owned)).collect()).unwrap_or_default()
    };
    let year = a["year"].as_i64().unwrap_or_else(|| a["aired"]["prop"]["from"]["year"].as_i64().unwrap_or(0));
    Ok(Meta {
        mal_id: a["mal_id"].as_i64().unwrap_or(0),
        title_romaji: s(&a["title"]),
        title_english: s(&a["title_english"]),
        title_native: s(&a["title_japanese"]),
        cover: s(&a["images"]["jpg"]["large_image_url"]),
        description: s(&a["synopsis"]),
        genres: names(&a["genres"]),
        score: (a["score"].as_f64().unwrap_or(0.0) * 10.0) as i64,
        episodes: a["episodes"].as_i64().unwrap_or(0),
        year,
        status: s(&a["status"]),
        format: s(&a["type"]),
        season: s(&a["season"]).to_uppercase(),
        season_year: year,
        source: s(&a["source"]),
        start_date: s(&a["aired"]["string"]),
        popularity: a["members"].as_i64().unwrap_or(0),
        favourites: a["favorites"].as_i64().unwrap_or(0),
        synonyms: a["title_synonyms"].as_array().map(|g| g.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect()).unwrap_or_default(),
        studios: names(&a["studios"]),
        producers: names(&a["producers"]),
        ..Default::default()
    })
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct EpisodeInfo {
    pub num: u32,
    pub title: String,
    pub filler: bool,
    pub recap: bool,
}

/// Episode titles + filler/recap flags: Jikan in pages of 100, falling back to
/// AniList streamingEpisodes (titles only).
pub async fn episode_info(mal_id: i64, anilist_id: i64) -> Vec<EpisodeInfo> {
    if mal_id > 0 {
        let mut out = Vec::new();
        for page in 1..=30 {
            let Ok(v) = jikan(&format!("/anime/{mal_id}/episodes?page={page}")).await else { break };
            for e in v["data"].as_array().into_iter().flatten() {
                out.push(EpisodeInfo {
                    num: e["mal_id"].as_u64().unwrap_or(0) as u32,
                    title: e["title"].as_str().unwrap_or_default().to_owned(),
                    filler: e["filler"].as_bool().unwrap_or(false),
                    recap: e["recap"].as_bool().unwrap_or(false),
                });
            }
            if !v["pagination"]["has_next_page"].as_bool().unwrap_or(false) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(400)).await; // Jikan allows ~3 req/s
        }
        if !out.is_empty() {
            return out;
        }
    }
    if anilist_id > 0
        && let Ok(v) = anilist("query ($id: Int) { Media(id: $id) { streamingEpisodes { title } } }", json!({ "id": anilist_id })).await
    {
        static EP_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^episode\s+(\d+)\s*-\s*(.*)$").unwrap());
        return v["data"]["Media"]["streamingEpisodes"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|e| {
                let c = EP_RE.captures(e["title"].as_str()?)?;
                Some(EpisodeInfo { num: c[1].parse().ok()?, title: c[2].to_owned(), ..Default::default() })
            })
            .collect();
    }
    Vec::new()
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SkipTimes {
    pub op: Option<(u32, u32)>,
    pub ed: Option<(u32, u32)>,
}

pub async fn skip_times(mal_id: i64, ep: u32) -> Result<SkipTimes> {
    let url = format!("https://api.aniskip.com/v1/skip-times/{mal_id}/{ep}?types=op&types=ed");
    let v: Value = http::PLAIN.get(url).header("User-Agent", API_UA).timeout(Duration::from_secs(10)).send().await?.json().await?;
    Ok(parse_skip(&v))
}

fn parse_skip(v: &Value) -> SkipTimes {
    let mut out = SkipTimes::default();
    if !v["found"].as_bool().unwrap_or(false) {
        return out;
    }
    for r in v["results"].as_array().into_iter().flatten() {
        let range = Some((r["interval"]["start_time"].as_f64().unwrap_or(0.0).round() as u32, r["interval"]["end_time"].as_f64().unwrap_or(0.0).round() as u32));
        match r["skip_type"].as_str() {
            Some("op") => out.op = range,
            Some("ed") => out.ed = range,
            _ => {}
        }
    }
    out
}

/// TMDB season map (only with an API key, only when AniList had none and the
/// show is long). Returns empty when TMDB also has a single season.
pub async fn tmdb_season_map(mal_id: i64, key: &str) -> Vec<SeasonRange> {
    async fn get(url: String) -> Option<Value> {
        http::PLAIN.get(url).timeout(Duration::from_secs(10)).send().await.ok()?.json().await.ok()
    }
    let k = http::query_escape(key);
    let Some(find) = get(format!("https://api.themoviedb.org/3/find/mal-{mal_id}?api_key={k}&external_source=myanimelist")).await else {
        return Vec::new();
    };
    let Some(tv) = find["tv_results"].get(0).and_then(|t| t["id"].as_i64()) else { return Vec::new() };
    let Some(details) = get(format!("https://api.themoviedb.org/3/tv/{tv}?api_key={k}&language=en-US")).await else {
        return Vec::new();
    };
    let mut out = Vec::new();
    let mut next = 1u32;
    for s in details["seasons"].as_array().into_iter().flatten() {
        let (season, count) = (s["season_number"].as_u64().unwrap_or(0) as u32, s["episode_count"].as_u64().unwrap_or(0) as u32);
        if season >= 1 && count > 0 {
            out.push(SeasonRange { season, start: next, end: next + count - 1 });
            next += count;
        }
    }
    if out.len() > 1 { out } else { Vec::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn season_map_orders_sequels_and_skips_specials() {
        let edges = json!([
            {"relationType":"SEQUEL","node":{"episodes":12,"format":"TV","startDate":{"year":2022,"month":4}}},
            {"relationType":"SEQUEL","node":{"episodes":1,"format":"OVA","startDate":{"year":2020,"month":1}}},
            {"relationType":"SEQUEL","node":{"episodes":11,"format":"TV","startDate":{"year":2021,"month":1}}},
            {"relationType":"PREQUEL","node":{"episodes":5,"format":"TV","startDate":{"year":2010,"month":1}}}
        ]);
        let map = season_map_from_relations(26, &edges);
        assert_eq!(map, [
            SeasonRange { season: 1, start: 1, end: 26 },
            SeasonRange { season: 2, start: 27, end: 37 },
            SeasonRange { season: 3, start: 38, end: 49 },
        ]);
        let m = Meta { season_map: map, ..Default::default() };
        assert_eq!(m.absolute_to_season(30), (2, 4));
        assert_eq!(m.absolute_to_season(60), (3, 23));
        assert_eq!(Meta::default().absolute_to_season(7), (1, 7));
    }

    #[test]
    fn title_cleaning_and_variations() {
        assert_eq!(clean_title("[otakudesu] Kimetsu no Yaiba Episode 5 Subtitle Indonesia"), "Kimetsu no Yaiba");
        let v = variations("Shingeki no Kyojin: The Final Season", "https://otakudesu.blog/anime/snk-final-sub-indo/");
        assert_eq!(v[0], "Shingeki no Kyojin: The Final Season");
        assert!(v.contains(&"snk final".to_owned()));
        assert!(v.contains(&"Shingeki no Kyojin".to_owned()));
        let v = variations("Tantei wa Mou, Shindeiru S2", "");
        assert_eq!(v[1..3], ["Tantei wa Mou, Shindeiru Season 2", "Tantei wa Mou, Shindeiru 2nd Season"]);
    }

    #[test]
    fn skip_parse() {
        let s = parse_skip(&json!({"found":true,"results":[{"interval":{"start_time":89.6,"end_time":179.4},"skip_type":"op"},{"interval":{"start_time":1300.0,"end_time":1390.0},"skip_type":"ed"}]}));
        assert_eq!((s.op, s.ed), (Some((90, 179)), Some((1300, 1390))));
        assert!(parse_skip(&json!({"found":false})).op.is_none());
    }

    #[test]
    fn discover_parse() {
        let show = |id: i64, adult: bool| json!({"id": id, "title": {"romaji": format!("Show {id}")}, "isAdult": adult});
        let d = parse_discover(&json!({
            "aired": {"airingSchedules": [
                {"episode": 5, "airingAt": 200, "media": show(1, false)},
                {"episode": 9, "airingAt": 100, "media": show(2, true)}
            ]},
            "next": {"airingSchedules": [{"episode": 3, "airingAt": 300, "media": show(3, false)}, {"episode": 1, "airingAt": 250, "media": {"id": 0}}]},
            "trending": {"media": [show(4, false)]},
            "comingSoon": null
        }));
        let sched: Vec<(i64, i64)> = d.schedule.iter().map(|a| (a.anime.anilist_id, a.episode)).collect();
        assert_eq!(sched, [(1, 5), (3, 3)], "adult and id-less entries dropped, oldest first");
        assert_eq!(d.trending[0].title_romaji, "Show 4");
        assert!(d.coming_soon.is_empty());
    }

    #[test]
    fn rich_media_parse() {
        let m = parse_media(&json!({
            "id": 154587,
            "idMal": 52991,
            "title": { "romaji": "Sousou no Frieren", "english": "Frieren: Beyond Journey's End", "native": "葬送のフリーレン" },
            "format": "TV",
            "status": "FINISHED",
            "source": "MANGA",
            "season": "FALL",
            "seasonYear": 2023,
            "episodes": 28,
            "duration": 24,
            "averageScore": 93,
            "meanScore": 93,
            "popularity": 320000,
            "favourites": 45000,
            "startDate": { "year": 2023, "month": 9, "day": 29 },
            "endDate": { "year": 2024, "month": 3, "day": 22 },
            "studios": {
                "edges": [
                    { "isMain": true, "node": { "name": "MADHOUSE" } },
                    { "isMain": false, "node": { "name": "TOHO animation" } }
                ]
            },
            "characters": {
                "edges": [
                    {
                        "role": "MAIN",
                        "node": { "id": 1, "name": { "full": "Frieren", "native": "フリーレン" }, "image": { "large": "https://img/frieren.jpg" } },
                        "voiceActors": [
                            { "id": 10, "name": { "full": "Atsumi Tanezaki", "native": "種﨑敦美" }, "image": { "large": "https://img/tanezaki.jpg" }, "languageV2": "Japanese" }
                        ]
                    }
                ]
            },
            "staff": {
                "edges": [
                    {
                        "role": "Director",
                        "node": { "id": 20, "name": { "full": "Keiichirou Saitou", "native": "斎藤圭一郎" }, "image": { "large": "https://img/saitou.jpg" } }
                    }
                ]
            },
            "relations": {
                "edges": [
                    {
                        "relationType": "ADAPTATION",
                        "node": { "id": 118586, "idMal": 126287, "type": "MANGA", "title": { "romaji": "Sousou no Frieren" }, "format": "MANGA", "status": "RELEASING" }
                    }
                ]
            },
            "recommendations": {
                "nodes": [
                    {
                        "rating": 850,
                        "mediaRecommendation": { "id": 161645, "idMal": 54492, "title": { "romaji": "Kusuriya no Hitorigoto", "english": "The Apothecary Diaries" }, "format": "TV", "episodes": 24, "seasonYear": 2023, "averageScore": 88 }
                    }
                ]
            }
        }))
        .unwrap();
        assert_eq!(m.studios, ["MADHOUSE"]);
        assert_eq!(m.producers, ["TOHO animation"]);
        assert_eq!(m.start_date, "Sep 29, 2023");
        assert_eq!(m.end_date, "Mar 22, 2024");
        assert_eq!(m.characters.len(), 1);
        assert_eq!(m.characters[0].name, "Frieren");
        assert_eq!(m.characters[0].va_name, "Atsumi Tanezaki");
        assert_eq!(m.staff.len(), 1);
        assert_eq!(m.staff[0].role, "Director");
        assert_eq!(m.relations.len(), 1);
        assert_eq!(m.recommendations.len(), 1);
    }

    /// `cargo test live_discover -- --ignored --nocapture`
    #[tokio::test]
    #[ignore]
    async fn live_discover() {
        let d = discover().await.unwrap();
        println!("schedule {} trending {} coming soon {}", d.schedule.len(), d.trending.len(), d.coming_soon.len());
        for a in d.schedule.iter().take(3) {
            println!("  ep {} at {}: {}", a.episode, a.airing_at, a.anime.title());
        }
        assert!(!d.schedule.is_empty() && !d.trending.is_empty() && !d.coming_soon.is_empty());
    }

    /// `cargo test live_anilist -- --ignored --nocapture`
    #[tokio::test]
    #[ignore]
    async fn live_anilist() {
        for name in ["Sousou no Frieren", "One Piece", "Toumei na Yoru ni Kakeru"] {
            let m = enrich(name, "").await.unwrap();
            println!("{name} -> {} anilist={} mal={} banner={}", m.title(), m.anilist_id, m.mal_id, !m.banner.is_empty());
            assert!(m.anilist_id > 0, "AniList (not the Jikan fallback) should answer");
        }
    }
}
