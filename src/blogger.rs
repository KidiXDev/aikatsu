//! Blogger `video.g?token=` → googlevideo URL via the batchexecute RPC
//! (WcwnYd), ported from GonimeId internal/player/scraper.go.

use crate::http;
use anyhow::{Result, anyhow, bail};
use regex::Regex;
use serde_json::Value;
use std::sync::LazyLock;

static TOKEN_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"token=([A-Za-z0-9_-]+)").unwrap());
static SID_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""FdrFJe"\s*:\s*"([^"]+)""#).unwrap());
static BUILD_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""cfb2h"\s*:\s*"([^"]+)""#).unwrap());
static AT_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""SNlM0e"\s*:\s*"([^"]+)""#).unwrap());
static GOOGLEVIDEO_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"https://[^"\\]+\.googlevideo\.com/[^"\\]+"#).unwrap());

/// The video was removed or is not accessible: retrying won't help.
#[derive(Debug)]
pub struct Gone(pub String);
impl std::fmt::Display for Gone {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "blogger video unavailable upstream: {}", self.0)
    }
}
impl std::error::Error for Gone {}

pub fn is_blogger(url: &str) -> bool {
    url.contains("blogger.com/video") || url.contains("blogspot.com/video")
}

pub async fn resolve(blogger_url: &str) -> Result<String> {
    let token = TOKEN_RE.captures(blogger_url).ok_or_else(|| anyhow!("no token in Blogger URL"))?[1].to_owned();
    // The Chrome client keeps cookies, which batchexecute needs from the page load.
    let page = http::CHROME.get(blogger_url).send().await?.text().await?;
    let cap = |re: &Regex| re.captures(&page).map(|c| c[1].to_owned());
    let (Some(sid), Some(build)) = (cap(&SID_RE), cap(&BUILD_RE)) else {
        bail!("failed to extract session params (FdrFJe/cfb2h) from Blogger page");
    };
    let inner = serde_json::to_string(&serde_json::json!([token, "", 0]))?;
    let freq = serde_json::to_string(&serde_json::json!([[["WcwnYd", inner, null, "generic"]]]))?;
    let mut body = format!("f.req={}", http::query_escape(&freq));
    if let Some(at) = cap(&AT_RE) {
        body += &format!("&at={}", http::query_escape(&at));
    }
    let url = format!(
        "https://www.blogger.com/_/BloggerVideoPlayerUi/data/batchexecute?rpcids=WcwnYd&source-path=%2Fvideo.g&f.sid={}&bl={}&hl=en-US&_reqid=100001&rt=c",
        http::query_escape(&sid),
        http::query_escape(&build)
    );
    let resp = http::CHROME
        .post(url)
        .header("Content-Type", "application/x-www-form-urlencoded;charset=UTF-8")
        .header("X-Same-Domain", "1")
        .header("Origin", "https://www.blogger.com")
        .header("Referer", blogger_url)
        .body(body)
        .send()
        .await?;
    let status = resp.status().as_u16();
    let text = resp.text().await?;
    anyhow::ensure!(status == 200, "batchexecute returned status {status}");
    parse_batchexecute(&text)
}

/// `wrb.fr` entries of the `)]}'`-prefixed response for rpc WcwnYd.
fn wcwnyd_entries(body: &str) -> impl Iterator<Item = Vec<Value>> + '_ {
    body.lines().filter(|l| l.contains("wrb.fr")).filter_map(|l| serde_json::from_str::<Vec<Value>>(l).ok()).flat_map(|outer| {
        outer.into_iter().filter_map(|e| match e {
            Value::Array(a) if a.len() >= 3 && a[0] == "wrb.fr" && a[1] == "WcwnYd" => Some(a),
            _ => None,
        })
    })
}

fn parse_batchexecute(body: &str) -> Result<String> {
    for entry in wcwnyd_entries(body) {
        let Some(data) = entry[2].as_str().and_then(|s| serde_json::from_str::<Vec<Value>>(s).ok()) else { continue };
        // Find the streams array at any index (resilient to Google moving it).
        let Some(streams) = data.iter().filter_map(Value::as_array).find(|s| s.first().is_some_and(Value::is_array)) else {
            continue;
        };
        let urls: Vec<&str> = streams.iter().filter_map(|s| s.get(0)?.as_str()).collect();
        let mp4: Vec<&str> = urls.iter().copied().filter(|u| u.contains("mime=video%2Fmp4") || u.contains("mime=video/mp4")).collect();
        // Prefer 720p (itag=22) over 360p (itag=18).
        if let Some(u) = mp4.iter().find(|u| u.contains("itag=22")).or(mp4.first()).or(urls.first()) {
            return Ok((*u).to_owned());
        }
    }
    if let Some(m) = GOOGLEVIDEO_RE.find(body) {
        return Ok(m.as_str().to_owned());
    }
    if body.trim().trim_start_matches(")]}'").trim().is_empty() {
        return Err(Gone("empty batchexecute response".into()).into());
    }
    // Error envelope: [ "wrb.fr", "WcwnYd", null, null, null, [code], … ]
    for entry in wcwnyd_entries(body) {
        if entry[2].is_null()
            && let Some(code) = entry.get(5).and_then(|s| s.get(0)).and_then(Value::as_i64)
        {
            return Err(match code {
                3 | 5 | 7 | 9 | 16 => Gone(format!("RPC status {code}")).into(),
                _ => anyhow!("blogger batchexecute returned RPC status {code}"),
            });
        }
    }
    bail!("no video URL found in batchexecute response")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_streams_and_errors() {
        let inner = serde_json::to_string(&serde_json::json!([
            null,
            [["https://r1.googlevideo.com/videoplayback?itag=18&mime=video%2Fmp4", [18]], ["https://r1.googlevideo.com/videoplayback?itag=22&mime=video%2Fmp4", [22]]]
        ]))
        .unwrap();
        let line = serde_json::to_string(&serde_json::json!([["wrb.fr", "WcwnYd", inner, null, null, null, "generic"]])).unwrap();
        let body = format!(")]}}'\n\n123\n{line}\n");
        assert!(parse_batchexecute(&body).unwrap().contains("itag=22"));

        let err = parse_batchexecute(r#")]}'
[["wrb.fr","WcwnYd",null,null,null,[5],"generic"]]"#)
        .unwrap_err();
        assert!(err.downcast_ref::<Gone>().is_some());
        assert!(parse_batchexecute(")]}'").unwrap_err().downcast_ref::<Gone>().is_some());
    }
}
