// A teaching example for a made-up site. Replace the URL and selectors.
const BASE = "https://example.org";

fn absolute(path) { url_join(global::BASE + "/", path) }

fn parse_search(html) {
    let results = [];
    for card in select(html, ".anime-card") {
        let links = select(card.html, "a.title");
        if links.is_empty() { continue; }
        let link = links[0];
        let href = attr(link, "href");
        if href == "" || link.text == "" { continue; }
        let images = select(card.html, "img");
        results.push(#{
            name: clean_sub_indo(link.text),
            url: absolute(href),
            image: if images.is_empty() { "" } else { absolute(attr(images[0], "src")) }
        });
    }
    results
}

fn parse_episodes(html) {
    let episodes = [];
    for link in select(html, "a.episode") {
        let number = regex_match(link.text, #"(?i)episode\s+(\d+)"#);
        let href = attr(link, "href");
        if number == () || href == "" { continue; }
        episodes.push(#{
            num: parse_int(number[1]),
            url: absolute(href),
            title: link.text
        });
    }
    episodes
}

fn parse_sources(html) {
    let sources = [];
    for item in select(html, "video source") {
        let height = height_of(attr(item, "data-quality"));
        let src = attr(item, "src");
        if src == "" || height <= 0 { continue; }
        let url = absolute(src);
        let parsed = url_parse(url);
        if parsed != () && (parsed.scheme == "https" || parsed.scheme == "http") {
            sources.push(#{ height: height, url: url });
        }
    }
    sources
}

fn search(query) {
    parse_search(page(global::BASE + "/?s=" + url_encode(query)))
}

fn episodes(url) { parse_episodes(page(url)) }

fn heights(url) {
    parse_sources(page(url)).map(|source| source.height)
}

fn stream(url, quality) {
    let candidates = sort_by_height(parse_sources(page(url)), quality);
    for candidate in candidates {
        if playable(candidate.url, global::BASE + "/") {
            return #{ url: candidate.url, referer: global::BASE + "/" };
        }
    }
    throw "Example: no playable video for this episode";
}
