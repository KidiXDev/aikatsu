# The four functions Aikatsu calls

Every source script needs these functions with exactly these argument counts:

```rust
fn search(query) { /* one argument */ }
fn episodes(anime_url) { /* one argument */ }
fn heights(episode_url) { /* one argument */ }
fn stream(episode_url, quality) { /* two arguments */ }
```

The host checks that they're present when it compiles the script. The inputs and outputs below are the actual API contract. Example URLs are placeholders.

## `search(query)`

Return an array of anime maps:

```rust
[
    #{
        name: "Example Show",
        url: "https://example.org/anime/example-show",
        image: "https://example.org/covers/example-show.jpg"
    }
]
```

`name` and `url` are required strings. `image` is optional and defaults to an empty string. Results with an empty name or URL are discarded. Return `[]` for a successful search with no matches.

The host normalizes hyphens and underscores to spaces before calling the script. It fills in the result's `source` field itself, using the plugin's stable ID. You don't need to supply that field.

## `episodes(anime_url)`

Return an array of episode maps:

```rust
[
    #{ num: 1, url: "https://example.org/watch/1", title: "A new beginning" },
    #{ num: 2, url: "https://example.org/watch/2" }
]
```

`num` must be a nonnegative integer that fits in a `u32`. `url` is a required string. `title` is optional. The host sorts by `num`; it treats an empty episode list as an error.

Use real episode numbers where possible. Avoid assigning the same number to unrelated entries such as trailers or download mirrors. The rest of the app uses those numbers for progress and episode matching.

## `heights(episode_url)`

Return an array of integer heights:

```rust
[360, 480, 720, 1080]
```

Return numbers, not strings like `"720p"`. The host removes zeroes and duplicates, sorts highest first, and turns them into display labels.

If a site's options are called `"HD 720p"`, the `height_of` helper can extract `720`. This function should describe resolutions the source can actually resolve.

## `stream(episode_url, quality)`

Return a map containing the final playable URL:

```rust
#{
    url: "https://cdn.example.org/video/episode-1.mp4",
    referer: "https://example.org/"
}
```

`url` is required and must use HTTP or HTTPS. `referer` is optional and defaults to an empty string. It can matter when a host expects the video request to come from the source site.

`quality` is `"best"`, an empty string, or a label such as `"720p"`. Use `sort_by_height` to try the preferred resolution first, then alternatives. `playable` can check whether a candidate serves video bytes before you return it.

Don't return the episode's HTML page or a browser-only embed. Resolve the media URL first. The app can handle supported direct streams and routes certain hosts through its own local relay.

## Errors and logs

Throw a readable string when the source can't complete a request:

```rust
throw "Example: no playable mirror for this episode";
```

Use `[]` for an ordinary empty search. Use an error for a broken response, missing player data, or a network failure. Otherwise the user gets “nothing found” when the source is actually broken.

`print` writes to the app log. `debug` writes debug-level output. Don't log cookies, private tokens, or full signed URLs unless you really need them while debugging, and remove those logs before publishing.

## Time and size limits

Search has a 12-second per-source budget, with a 15-second limit for a whole multi-source search. Episode, quality, and stream calls get a 60-second script budget. Network requests also have their own timeouts and retries, so avoid unnecessary requests and unbounded loops.

The engine caps strings at 16 MiB, arrays and maps at 100,000 entries, and HTTP responses at 8 MiB. Build a small parser for the data you need rather than collecting an entire site.

## Rhai details that are easy to miss

A function reads a top-level constant through `global::NAME`:

```rust
const BASE = "https://example.org";
fn home() { global::BASE + "/" }
```

Methods such as `trim`, `replace`, and `sort` mutate their value. Don't assume they return the changed value. `()` is Rhai's unit value, which helpers also use for missing data.

For the language itself, see the [Rhai book](https://rhai.rs/book/). For Aikatsu's registered functions, use the [host API reference](./host-api.md).
