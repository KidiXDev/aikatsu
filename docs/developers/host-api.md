# Host API reference

This is the API that Aikatsu exposes to source scripts at **API 1**. Rhai's normal language features are available too, but the host helpers below are what connect a plugin to websites and the player.

## Network

### `page(url)` and `page(url, referer)`

GET a page through the Chrome-like HTTP client and return its body as a string. Successful, challenge-free responses are cached for 10 minutes. Cloudflare-style challenge pages are rejected rather than passed to your parser as normal HTML.

```rust
let html = page("https://example.org/anime/test", "https://example.org/");
```

Use this for HTML that `heights` and `stream` might both need. Use `fetch` when a request needs custom options or shouldn't use that page cache.

### `fetch(url)` and `fetch(url, opts)`

Make a request and return:

```rust
#{ status: 200, headers: #{}, body: "response body", url: "https://example.org/final" }
```

Header names are lowercase. `url` is the final URL after redirects. Status codes from 400 throw an error. A 3xx can be returned when redirect following is disabled.

| Option | What it does |
| --- | --- |
| `method` | HTTP method, such as `"GET"` or `"POST"` |
| `referer` | Set the Referer header |
| `headers: #{}` | Add request headers |
| `form: #{}` | Send form fields |
| `json` | Send a JSON value |
| `client` | `"chrome"` by default, or `"plain"` for hosts that need it |
| `redirect: false` | Return the redirect response itself |

The method defaults to GET, or POST when `form` or `json` is present. Pick the body format the endpoint expects rather than supplying both.

```rust
let response = fetch("https://example.org/player", #{
    method: "POST",
    referer: "https://example.org/watch/1",
    headers: #{ "X-Requested-With": "XMLHttpRequest" },
    form: #{ id: "episode-1" }
});
let player = json_parse(response.body);
```

The shared HTTP helper retries server errors and dropped connections up to twice. It doesn't retry ordinary 4xx responses. Keep this in mind for requests that have side effects: source requests should generally just read data.

### `fetch_all(urls)` and `fetch_all(urls, opts)`

Make the same kind of request to several URLs, with up to four requests running at once. Responses come back in the input order. A failed request makes the call fail; this isn't a list of mixed success and error values.

```rust
let responses = fetch_all([
    "https://example.org/player/one",
    "https://example.org/player/two"
], #{ referer: "https://example.org/" });
```

### `playable(url)` and `playable(url, referer)`

Ask the host for one byte. Return `true` for a 200 or 206 response, otherwise `false`. This is a useful availability probe, not a full video-decoding test.

## HTML and text

| Function | Result |
| --- | --- |
| `select(html, css)` | Array of matched elements as `#{ text, html, attrs }` |
| `attr(element, name)` | Attribute value, or `""` if it's missing |
| `regex_match(text, pattern)` | First match as `[whole, group1, ...]`, or `()` |
| `regex_replace(text, pattern, replacement)` | Replace every match; `$1` refers to a capture group |
| `json_parse(text)` | Rhai maps, arrays, and other values; JSON null becomes `()` |
| `base64_decode(text)` | Decode standard Base64 to text |
| `html_decode(text)` | Decode HTML entities |
| `clean_sub_indo(title)` | Remove a trailing “Subtitle Indonesia” or “Sub Indo” label |

`select` trims the result's text and attribute values. Its `html` field is the element's **inner HTML**, so it doesn't include the selected element's outer tag. Use `attr` for attributes on that selected element, or call `select(element.html, selector)` to search inside it.

```rust
for link in select(html, "a.episode") {
    let match = regex_match(link.text, #"(?i)episode\s+(\d+)"#);
    if match != () {
        let number = parse_int(match[1]);
        let href = attr(link, "href");
        print(`Episode ${number}: ${href}`);
    }
}
```

Regexes use Rust's regex engine, so don't rely on lookaround or backreferences inside a pattern. Raw Rhai strings such as `#"\d+"#` keep regex escapes readable.

## URLs

| Function | Result |
| --- | --- |
| `url_encode(text)` | Query-string-safe text |
| `url_join(base, relative)` | An absolute URL, or `""` if parsing fails |
| `url_parse(url)` | `#{ scheme, host, origin, path, query: #{} }`, or `()` |
| `url_set_param(url, key, value)` | URL with that query parameter replaced |

`url_parse` lowercases the host and decodes query parameters. `url_set_param` removes existing copies of the key, then adds the new value. If its input URL isn't valid, it returns the input unchanged.

```rust
let url = url_join("https://example.org/anime/", "../watch/1");
let selected = url_set_param(url, "quality", "720p");
let parsed = url_parse(selected);
```

## Resolutions

`height_of(label)` extracts a numeric height from a label. For example, `height_of("MKV 1080p")` returns `1080`; `height_of("best")` returns `0`.

`sort_by_height(items, quality)` returns a sorted array. Items can be strings with a height in them or maps with a numeric `height` field.

- For `"best"` or `""`, higher resolutions come first.
- For a requested height, the exact match comes first, then the nearest higher options, then the nearest lower options.

```rust
let options = [#{ height: 480, url: "a" }, #{ height: 1080, url: "b" }, #{ height: 720, url: "c" }];
let preferred = sort_by_height(options, "720p");
```

## Temporary cache

`cache_set(key, value, seconds)` stores a value. `cache_get(key)` returns it, or `()` if it expired or wasn't there.

Keys are namespaced by plugin, so one source's `"player"` entry doesn't collide with another's. Entries live in memory for at most one hour. The host limits the combined cache to 128 entries and may evict entries before their requested lifetime. Plugin reloads clear it too.

```rust
cache_set("player:" + episode_url, player_data, 120);
let cached = cache_get("player:" + episode_url);
if cached == () {
    // Fetch it again. A cache hit is never guaranteed.
}
```

Don't use the cache as permanent storage, and don't assume `heights` always runs before `stream`. A stream call should be able to fetch whatever it needs after a cache miss.

## What isn't in this API

There are no host functions for reading watch history, changing settings, or reading arbitrary local files. Plugins also don't get a browser DOM or a JavaScript runtime for the target site.

Network access is still a trust boundary. A plugin can contact websites and return video URLs, so users need to trust the repo that supplies it.
