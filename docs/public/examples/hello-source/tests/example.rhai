fn test_search_cards() {
    let html = `<article class="anime-card"><a class="title" href="/anime/test">Test Show Subtitle Indonesia</a><img src="/cover.jpg"></article>`;
    let results = parse_search(html);
    assert_eq(results.len(), 1);
    assert_eq(results[0].name, "Test Show");
    assert_eq(results[0].url, "https://example.org/anime/test");
    assert_eq(results[0].image, "https://example.org/cover.jpg");
}

fn test_empty_search() {
    assert_eq(parse_search("<p>No matches</p>"), []);
}

fn test_episode_numbers() {
    let html = `<a class="episode" href="/watch/2">Episode 2</a><a class="episode" href="/watch/1">Episode 1</a><a class="episode" href="/about">About</a>`;
    let episodes = parse_episodes(html);
    assert_eq(episodes.len(), 2);
    assert_eq(episodes[0].num, 2);
    assert_eq(episodes[1].url, "https://example.org/watch/1");
}

fn test_video_sources() {
    let html = `<video><source src="/video-480.mp4" data-quality="480p"><source src="/video-720.mp4" data-quality="720p"></video>`;
    let sources = parse_sources(html);
    assert_eq(sources.len(), 2);
    assert_eq(sort_by_height(sources, "720p")[0].height, 720);
    assert_eq(sort_by_height(sources, "best")[0].url, "https://example.org/video-720.mp4");
}

fn test_missing_links_and_video_urls() {
    assert_eq(parse_search(`<article class="anime-card"><a class="title">No link</a></article>`), []);
    assert_eq(parse_episodes(`<a class="episode">Episode 1</a>`), []);
    assert_eq(parse_sources(`<video><source data-quality="720p"><source src="javascript:alert(1)" data-quality="720p"></video>`), []);
}
