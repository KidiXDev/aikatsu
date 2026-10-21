import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'library.dart';
import 'player.dart';
import 'search.dart';

void openAnime(BuildContext context, Map<String, dynamic> anime, {int autoplayEpisode = 0}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AnimePage(anime: anime, autoplayEpisode: autoplayEpisode),
    ),
  );
}

/// The anime page's input for a watchlist entry.
Map<String, dynamic> watchedAnime(Map<String, dynamic> w) =>
    {'name': w['title'], 'url': w['series_url'], 'image': w['cover'], 'source': w['source'], 'anilistId': w['anilist_id']};

/// What the anime page knows about a series. The player listens to it too,
/// since details can land after playback has started.
class AnimeData extends ChangeNotifier {
  AnimeData(this.anime);

  /// A series from the offline library: its downloaded episodes, with the
  /// details saved at download time, so nothing needs the network. Progress
  /// saves under the same keys as streaming, so history stays one.
  AnimeData.library(Map<String, dynamic> series)
    : anime = {
        'name': series['series_name'],
        'url': series['series_url'],
        'image': text([series['meta']['cover']]),
        'source': series['source'],
        'anilistId': series['meta']['anilist_id'],
      },
      meta = series['meta'],
      metaLoaded = true,
      loading = false,
      episodes = [
        for (final e in series['episodes']) {'num': e['episode_number'], 'url': e['episode_url'], 'title': ''},
      ],
      localFiles = {for (final e in series['episodes']) e['episode_url'] as String: e['path'] as String};

  final Map<String, dynamic> anime; // {name, url, image, source, anilistId?}
  Map<String, dynamic>? meta; // null until enrich answers, {} if it failed
  bool metaLoaded = false; // progress saves wait for this so the series key stays stable
  List<dynamic> episodes = [];
  Map<int, dynamic> info = {}; // episode number → {title, filler, recap}
  Map<int, dynamic> progress = {}; // episode number → progress row
  Map<String, String> localFiles = {}; // episode URL → downloaded file, played instead of streaming
  Map<String, dynamic>? watchEntry;
  bool loading = true;
  String error = '';
  bool _disposed = false;

  String get title => text([meta?['title_english'], meta?['title_romaji'], anime['name']]);
  String get cover => text([meta?['cover'], anime['image']]);

  Map<String, dynamic> keys(int episode) =>
      Api.get('keys', {'anilistId': toInt(meta?['anilist_id']), 'source': anime['source'], 'url': anime['url'], 'episode': episode});

  String get seriesKey => keys(0)['series'];

  /// The episode last left unfinished, else the first unwatched one.
  int get continueIndex {
    var latest = -1, at = 0;
    for (var i = 0; i < episodes.length; i++) {
      final p = progress[episodes[i]['num']];
      if (p != null && p['completed'] != true && toInt(p['playback_time']) > 0 && toInt(p['last_updated']) > at) {
        latest = i;
        at = toInt(p['last_updated']);
      }
    }
    if (latest >= 0) return latest;
    final unwatched = episodes.indexWhere((e) => progress[e['num']]?['completed'] != true);
    return unwatched >= 0 ? unwatched : 0;
  }

  String episodeTitle(Map<String, dynamic> ep) => text([info[ep['num']]?['title'], ep['title']]);

  /// Downloaded episodes of this series on this source (a quick local lookup).
  void refreshLocal() {
    localFiles = Map<String, String>.from(Api.get('localEpisodes', {'source': anime['source'], 'url': anime['url']}));
    notifyListeners();
  }

  Map<String, Object?> get listEntry => {
    'anilist_id': toInt(meta?['anilist_id']),
    'mal_id': toInt(meta?['mal_id']),
    'title': title,
    'cover': cover,
    'source': anime['source'],
    'series_url': anime['url'],
    'total_episodes': toInt(meta?['episodes']),
  };

  void refreshProgress() {
    watchEntry = metaLoaded ? Api.get('watchEntry', listEntry) : null;
    progress = {
      for (final p in Api.get('seriesProgress', {'key': seriesKey, 'url': anime['url']}) as List) toInt(p['episode_number']): p,
    };
    notifyListeners();
  }

  /// A full row for `saveProgress` / `setCompleted`.
  Map<String, Object?> progressRow(Map<String, dynamic> ep, {num? playbackTime, num? duration, bool completed = false}) => {
    'episode_key': keys(ep['num'])['episode'],
    'anilist_id': toInt(meta?['anilist_id']),
    'mal_id': toInt(meta?['mal_id']),
    'series_key': seriesKey,
    'series_url': anime['url'],
    'series_title': title,
    'source': anime['source'],
    'episode_url': ep['url'],
    'total_episodes': toInt(meta?['episodes']) > 0 ? toInt(meta?['episodes']) : episodes.length,
    'meta_episodes': toInt(meta?['episodes']),
    'episode_number': ep['num'],
    'playback_time': (playbackTime ?? toInt(progress[ep['num']]?['playback_time'])).floor(),
    'duration': (duration ?? toInt(progress[ep['num']]?['duration'])).floor(),
    'title': episodeTitle(ep),
    'cover': cover,
    'completed': completed,
    'last_updated': 0,
  };

  /// Completes once the episode list is in (or failed); details land on their own.
  /// `refresh` skips the page and metadata caches.
  Future<void> load({bool refresh = false}) {
    loading = true;
    error = '';
    notifyListeners();
    Api.call('enrich', {'name': anime['name'], 'url': anime['url'], 'anilistId': anime['anilistId'] ?? 0, 'refresh': refresh}).then(
      (m) {
        meta = m;
        metaLoaded = true;
        refreshProgress();
        if (toInt(m['mal_id']) > 0 || toInt(m['anilist_id']) > 0) {
          Api.call('episodeInfo', {'malId': m['mal_id'], 'anilistId': m['anilist_id'], 'refresh': refresh}).then((list) {
            info = {for (final e in list as List) toInt(e['num']): e};
            notifyListeners();
          }, onError: (_) {});
        }
      },
      onError: (_) {
        meta = {};
        metaLoaded = true;
        refreshProgress();
      },
    );
    return Api.call('episodes', {'source': anime['source'], 'url': anime['url'], 'refresh': refresh}).then(
      (eps) {
        episodes = eps;
        loading = false;
        refreshProgress();
      },
      onError: (e) {
        loading = false;
        error = '$e';
        notifyListeners();
      },
    );
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AnimePage extends StatefulWidget {
  const AnimePage({super.key, required this.anime, this.autoplayEpisode = 0});

  final Map<String, dynamic> anime;

  /// Episode number to start right away.
  final int autoplayEpisode;

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  late final AnimeData _data = AnimeData(widget.anime);
  bool _descending = false;
  bool _synopsisOpen = false;
  String _jump = '';
  String _section = 'episodes'; // episodes | cast | details
  String _role = 'all'; // all | MAIN | SUPPORTING
  late final StreamSubscription<(String, dynamic)> _downloads;

  @override
  void initState() {
    super.initState();
    _data.addListener(_changed);
    Api.historyRevision.addListener(_data.refreshProgress);
    Api.libraryRevision.addListener(_data.refreshLocal);
    _downloads = Api.pushed.listen((e) {
      if (e.$1 == 'download' && e.$2['state'] == 'done') _data.refreshLocal();
    });
    _data.refreshLocal();
    _data.load().then((_) {
      if (!mounted || widget.autoplayEpisode == 0 || _data.episodes.isEmpty) return;
      final i = _data.episodes.indexWhere((e) => e['num'] == widget.autoplayEpisode);
      _play(i >= 0 ? i : _data.continueIndex);
    });
  }

  @override
  void dispose() {
    Api.historyRevision.removeListener(_data.refreshProgress);
    Api.libraryRevision.removeListener(_data.refreshLocal);
    _downloads.cancel();
    _data.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _play(int index) {
    if (index < 0 || index >= _data.episodes.length) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(data: _data, index: index),
      ),
    );
  }

  bool get _local => widget.anime['source'] == 'local';

  Future<void> _chooseAnime() async {
    final m = await chooseAnime(context, widget.anime['url'], widget.anime['name']);
    if (m == null || !mounted) return;
    widget.anime['anilistId'] = m['anilist_id'];
    _data.load(refresh: true);
  }

  Future<void> _episodeMenu(Map<String, dynamic> ep) async {
    final watched = _data.progress[ep['num']]?['completed'] == true;
    final file = _data.localFiles[ep['url']];
    final choice = await pickFrom(context, 'Episode ${ep['num']}', [
      (file != null ? 'Play downloaded' : 'Play', 'play', false),
      (watched ? 'Mark as unwatched' : 'Mark as watched', 'toggle', false),
      if (!_local && file == null) ('Download episode', 'download', false),
      if (!_local && file != null) ('Delete download', 'delete', false),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'play':
        _play(_data.episodes.indexWhere((e) => e['url'] == ep['url']));
      case 'toggle':
        Api.get('setCompleted', {'progress': _data.progressRow(ep), 'completed': !watched});
        Api.historyRevision.value++;
      case 'download':
        showDownloadSheet(context, _data, single: ep);
      case 'delete':
        if (file != null &&
            await confirm(context, 'Delete episode ${ep['num']}?', 'You can still stream it.', 'Delete')) {
          Api.deleteDownloads([file]);
        }
    }
  }

  Future<void> _watchMenu() async {
    final current = _data.watchEntry?['status'];
    final choice = await pickFrom(context, 'Watchlist', [
      for (final (value, label, _) in watchStatuses) (label, value, value == current),
      if (current != null) ('Remove from list', '', false),
    ]);
    if (choice == null || !mounted) return;
    Api.get('setWatchStatus', {'entry': _data.listEntry, 'status': choice});
    Api.historyRevision.value++;
  }

  static const _spinner = SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  void _openUrl(String url) => const MethodChannel('io.github.kidixdev.aikatsu/update').invokeMethod('open', {'url': url}).ignore();

  /// A manga opens on AniList; an anime is looked up on the sources, which mostly use romaji names.
  void _openRelated(Map<String, dynamic> m) {
    if (m['media_type'] == 'MANGA' && toInt(m['anilist_id']) > 0) return _openUrl('https://anilist.co/manga/${m['anilist_id']}');
    SearchPage.requested.value = text([m['title_romaji'], m['title_english']]);
  }

  List<Widget> _castSlivers(BuildContext context, List<dynamic> characters) {
    final staff = (_data.meta?['staff'] as List?) ?? const [];
    if (!_data.metaLoaded) return [_spinner];
    if (characters.isEmpty && staff.isEmpty) return [const SliverToBoxAdapter(child: EmptyState(face: '(・・ )?', title: 'No cast or staff'))];
    return [
      if (characters.isNotEmpty) ...[
        sectionHeader(context, 'Characters', Icons.groups_rounded, subtitle: '${characters.length}'),
        _tiles(characters.length, 480, 92, (i) => _CharacterTile(characters[i])),
      ],
      if (staff.isNotEmpty) ...[
        sectionHeader(context, 'Staff', Icons.movie_rounded, subtitle: '${staff.length}'),
        _tiles(staff.length, 360, 92, (i) => _StaffTile(staff[i])),
      ],
    ];
  }

  List<Widget> _detailSlivers(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final m = _data.meta ?? const {};
    if (!_data.metaLoaded) return [_spinner];
    if (m.isEmpty) return [const SliverToBoxAdapter(child: EmptyState(face: '(・・ )?', title: 'No details'))];
    final year = toInt(m['season_year']) > 0 ? toInt(m['season_year']) : toInt(m['year']);
    final start = text([m['start_date']]), end = text([m['end_date']]);
    final score = toInt(m['score']), mean = toInt(m['mean_score']);
    List<String> list(Object? v) => [for (final x in (v as List?) ?? const []) '$x'];
    final facts = [
      ('Format', prettyEnum(text([m['format']]))),
      ('Episodes', toInt(m['episodes']) > 0 ? '${m['episodes']}' : (_data.episodes.isNotEmpty ? '${_data.episodes.length}' : '')),
      ('Duration', toInt(m['duration']) > 0 ? '${m['duration']} mins' : ''),
      ('Status', prettyEnum(text([m['status']]))),
      ('Season', [prettyEnum(text([m['season']])), if (year > 0) '$year'].where((s) => s.isNotEmpty).join(' ')),
      ('Aired', start.isNotEmpty && end.isNotEmpty && start != end ? '$start → $end' : text([start, end])),
      ('Source', prettyEnum(text([m['source']]))),
      ('Studio', list(m['studios']).join(', ')),
      ('Producers', list(m['producers']).take(4).join(', ')),
      ('Score', score <= 0 ? '' : '${(score / 10).toStringAsFixed(1)} / 10  (${mean > 0 && mean != score ? 'Mean $mean' : score}%)'),
      ('Popularity', toInt(m['popularity']) > 0 ? '${formatCount(toInt(m['popularity']))} members' : ''),
      ('Favorites', toInt(m['favourites']) > 0 ? formatCount(toInt(m['favourites'])) : ''),
      ('Romaji', text([m['title_romaji']])),
      ('English', text([m['title_english']])),
      ('Native', text([m['title_native']])),
      ('Synonyms', list(m['synonyms']).take(5).join('  ·  ')),
    ].where((f) => f.$2.isNotEmpty).toList();
    final tags = (m['tags'] as List?) ?? const [];
    final relations = (m['relations'] as List?) ?? const [];
    final recommendations = (m['recommendations'] as List?) ?? const [];

    return [
      sectionHeader(
        context,
        'Information',
        Icons.info_rounded,
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (toInt(m['anilist_id']) > 0)
              TextButton(onPressed: () => _openUrl('https://anilist.co/anime/${m['anilist_id']}'), child: const Text('AniList')),
            if (toInt(m['mal_id']) > 0)
              TextButton(onPressed: () => _openUrl('https://myanimelist.net/anime/${m['mal_id']}'), child: const Text('MAL')),
          ],
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: _card(c),
            child: Column(
              children: [
                for (final (i, (label, value)) in facts.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.outlineVariant.withValues(alpha: 0.35)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(label, style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                        ),
                        Expanded(
                          child: Text(value, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      if (tags.isNotEmpty) ...[
        sectionHeader(context, 'Tags', Icons.sell_rounded, subtitle: '${tags.length}'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags) PillBadge(label: toInt(tag['rank']) > 0 ? '${tag['name']}  ·  ${tag['rank']}%' : '${tag['name']}'),
              ],
            ),
          ),
        ),
      ],
      if (relations.isNotEmpty) ...[
        sectionHeader(context, 'Related', Icons.link_rounded, subtitle: '${relations.length}'),
        _tiles(relations.length, 480, 108, (i) => _RelationTile(relations[i], onTap: () => _openRelated(relations[i]))),
      ],
      if (recommendations.isNotEmpty) ...[
        sectionHeader(context, 'Recommendations', Icons.auto_awesome_rounded, subtitle: '${recommendations.length}'),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.builder(
            gridDelegate: posterGrid(),
            itemCount: recommendations.length,
            itemBuilder: (_, i) {
              final r = recommendations[i];
              return PosterCard(
                title: text([r['title_english'], r['title_romaji']]),
                image: text([r['cover']]),
                badge: toInt(r['score']) > 0 ? '★ ${(toInt(r['score']) / 10).toStringAsFixed(1)}' : '',
                subtitle: _mediaLine(r),
                onTap: () => _openRelated(r),
              );
            },
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final aikatsu = context.aikatsu;
    final d = _data, meta = d.meta;
    var eps = d.episodes.where((e) => _jump.isEmpty || '${e['num']}'.startsWith(_jump)).toList();
    if (_descending) eps = eps.reversed.toList();
    final current = d.progress.isNotEmpty && d.episodes.isNotEmpty ? d.episodes[d.continueIndex]['num'] : null;
    final banner = text([meta?['banner'], meta?['cover'], widget.anime['image']]);
    final blur = text([meta?['banner']]).isEmpty ? 24.0 : 3.0;
    final subtitles = [
      meta?['title_romaji'],
      meta?['title_native'],
    ].where((s) => text([s]).isNotEmpty && s != text([meta?['title_english']]));
    final year = toInt(meta?['season_year']) > 0 ? toInt(meta?['season_year']) : toInt(meta?['year']);
    final season = [prettyEnum(text([meta?['season']])), if (year > 0) '$year'].where((s) => s.isNotEmpty).join(' ');
    final total = toInt(meta?['episodes']), duration = toInt(meta?['duration']);
    final next = meta?['next_airing'];
    final airsAfter = next == null ? '' : airsIn(toInt(next['airing_at']), DateTime.now());
    final watched = d.episodes.where((e) => d.progress[e['num']]?['completed'] == true).length;
    final characters = (meta?['characters'] as List?) ?? const [];
    final roles = {for (final ch in characters) ch['role']};
    final splitRoles = roles.contains('MAIN') && roles.contains('SUPPORTING');
    final role = splitRoles ? _role : 'all';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            title: Text(
              d.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                icon: Icon(watchStatuses.where((s) => s.$1 == d.watchEntry?['status']).firstOrNull?.$3 ?? Icons.bookmark_add_outlined),
                tooltip: 'Watchlist',
                onPressed: d.metaLoaded ? _watchMenu : null,
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => d.load(refresh: true)),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: BlurredArt(
                banner,
                sigma: blur,
                overlay: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.surface.withValues(alpha: 0.2), c.surface.withValues(alpha: 0.75), c.surface, c.surface],
                  stops: const [0.0, 0.5, 0.85, 1.0],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverList.list(
              children: [
                // Anime Header Block
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, height: 160, child: Cover(d.cover, radius: 18)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                          ),
                          if (subtitles.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitles.join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, fontSize: 13),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              PillBadge(label: Api.sourceName(widget.anime['source']), icon: _local ? Icons.folder_rounded : Icons.public_rounded),
                              if (toInt(meta?['score']) > 0)
                                PillBadge(label: '★ ${(toInt(meta?['score']) / 10).toStringAsFixed(1)}', color: const Color(0xffffb84d)),
                              if (text([meta?['format']]).isNotEmpty) PillBadge(label: prettyEnum(meta?['format']), icon: Icons.tv_rounded),
                              if (season.isNotEmpty) PillBadge(label: season, icon: Icons.calendar_month_rounded),
                              if (d.episodes.isNotEmpty || total > 0)
                                PillBadge(
                                  label: [
                                    d.episodes.isEmpty ? '$total eps' : '${d.episodes.length} eps${total > d.episodes.length ? ' / $total' : ''}',
                                    if (duration > 0) '${duration}m',
                                  ].join(' · '),
                                  icon: Icons.video_library_rounded,
                                ),
                              if (text([meta?['status']]).isNotEmpty)
                                PillBadge(label: prettyEnum(meta?['status']), icon: Icons.radio_button_checked_rounded),
                              for (final g in (meta?['genres'] as List?) ?? []) PillBadge(label: '$g'),
                            ],
                          ),
                          if (next != null) ...[
                            const SizedBox(height: 8),
                            PillBadge(
                              label: airsAfter.isEmpty ? 'Ep ${next['episode']} airing now' : 'Ep ${next['episode']} airs in $airsAfter',
                              icon: Icons.schedule_rounded,
                              color: c.onPrimaryContainer,
                              backgroundColor: c.primaryContainer,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Primary Action Bar
                Row(
                  children: [
                    Expanded(
                      child: BouncyTap(
                        borderRadius: BorderRadius.circular(999),
                        onTap: d.episodes.isEmpty ? null : () => _play(d.continueIndex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
                          decoration: BoxDecoration(
                            color: d.episodes.isEmpty ? c.surfaceContainerHighest : c.primary,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: d.episodes.isEmpty ? null : aikatsu.softShadow,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                d.loading ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
                                color: d.episodes.isEmpty ? c.onSurfaceVariant : c.onPrimary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  d.episodes.isEmpty
                                      ? (d.loading ? 'Loading episodes…' : 'Play')
                                      : d.progress.isNotEmpty
                                      ? 'Continue  ·  Ep ${d.episodes[d.continueIndex]['num']}'
                                      : 'Play  ·  Ep ${d.episodes.first['num']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'GoogleSansFlex',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: d.episodes.isEmpty ? c.onSurfaceVariant : c.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    BouncyTap(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _local ? _chooseAnime : (d.episodes.isEmpty ? null : () => showDownloadSheet(context, d)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
                        decoration: BoxDecoration(
                          color: c.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_local ? Icons.link_rounded : Icons.download_rounded, color: c.onSurface, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              _local ? 'Choose anime…' : 'Download…',
                              style: TextStyle(
                                fontFamily: 'GoogleSansFlex',
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: c.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Synopsis Card
                if (text([meta?['description']]).isNotEmpty) ...[
                  const SizedBox(height: 18),
                  BouncyTap(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _synopsisOpen = !_synopsisOpen),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'SYNOPSIS',
                                style: TextStyle(
                                  fontFamily: 'GoogleSansFlex',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: c.primary,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _synopsisOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: c.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            meta!['description'],
                            maxLines: _synopsisOpen ? null : 4,
                            overflow: _synopsisOpen ? null : TextOverflow.ellipsis,
                            style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'episodes', icon: Icon(Icons.video_library_rounded), label: Text('Episodes')),
                    ButtonSegment(value: 'cast', icon: Icon(Icons.groups_rounded), label: Text('Cast')),
                    ButtonSegment(value: 'details', icon: Icon(Icons.info_outline_rounded), label: Text('Details')),
                  ],
                  selected: {_section},
                  onSelectionChanged: (v) => setState(() {
                    _section = v.first;
                    _jump = '';
                  }),
                ),
                if (_section == 'cast' && splitRoles) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (value, label) in [('all', 'All'), ('MAIN', 'Main'), ('SUPPORTING', 'Supporting')])
                        ChoiceChip(
                          label: Text('$label  ${value == 'all' ? characters.length : characters.where((ch) => ch['role'] == value).length}'),
                          selected: value == role,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _role = value),
                        ),
                    ],
                  ),
                ],
                if (_section == 'episodes') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (d.episodes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            watched > 0 ? '$watched / ${d.episodes.length} watched' : '${d.episodes.length} episodes',
                            style: TextStyle(
                              fontFamily: 'GoogleSansFlex',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const Spacer(),
                      SizedBox(
                        width: 125,
                        height: 38,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            prefixIcon: const Icon(Icons.tag_rounded, size: 16),
                            hintText: 'Jump to…',
                            hintStyle: TextStyle(fontSize: 12, color: c.onSurfaceVariant.withValues(alpha: 0.6)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(color: c.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(color: c.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide(color: c.primary, width: 1.2),
                            ),
                          ),
                          onChanged: (v) => setState(() => _jump = v),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: Icon(_descending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20),
                        onPressed: () => setState(() => _descending = !_descending),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_section == 'cast') ..._castSlivers(context, role == 'all' ? characters : characters.where((ch) => ch['role'] == role).toList()),
          if (_section == 'details') ..._detailSlivers(context),
          if (_section != 'episodes')
            const SliverToBoxAdapter(child: SizedBox(height: 40))
          else if (d.loading && d.episodes.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (d.episodes.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                face: '(×﹏×)',
                error: true,
                title: d.error.isNotEmpty ? "Couldn't load episodes from ${Api.sourceName(widget.anime['source'])}" : 'No episodes yet',
                message: d.error.isNotEmpty ? Api.describe(d.error) : '',
                details: d.error,
                action: FilledButton.tonalIcon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                  onPressed: () => d.load(refresh: true),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 480,
                  mainAxisExtent: 78,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: eps.length,
                itemBuilder: (context, i) {
                  final ep = eps[i] as Map<String, dynamic>;
                  return EpisodeTile(
                    num: ep['num'],
                    title: d.episodeTitle(ep),
                    filler: d.info[ep['num']]?['filler'] == true,
                    recap: d.info[ep['num']]?['recap'] == true,
                    record: d.progress[ep['num']],
                    current: ep['num'] == current,
                    downloaded: d.localFiles.containsKey(ep['url']),
                    onTap: () => _play(d.episodes.indexWhere((e) => e['url'] == ep['url'])),
                    onLongPress: () => _episodeMenu(ep),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _card(ColorScheme c) => BoxDecoration(
  color: c.surfaceContainerLow,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: c.outlineVariant.withValues(alpha: 0.45)),
);

Widget _tiles(int count, double maxWidth, double height, Widget Function(int) item) => SliverPadding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  sliver: SliverGrid.builder(
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxWidth,
      mainAxisExtent: height,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: count,
    itemBuilder: (_, i) => item(i),
  ),
);

/// "TV · 24 ep · 2023", from a related or recommended entry.
String _mediaLine(Map<String, dynamic> m) => [
  prettyEnum(text([m['format']])),
  if (toInt(m['episodes']) > 0) '${m['episodes']} ep',
  if (toInt(m['year']) > 0) '${m['year']}',
].where((s) => s.isNotEmpty).join(' · ');

/// A name over its native spelling, then [below].
Widget _names(BuildContext context, Object? name, Object? native, Widget below, {bool end = false}) {
  final t = Theme.of(context);
  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    spacing: 2,
    children: [
      Text(
        text([name]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
      ),
      if (text([native]).isNotEmpty)
        Text(
          text([native]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant, fontSize: 11.5),
        ),
      const SizedBox(height: 2),
      below,
    ],
  );
}

/// A character beside their voice actor.
class _CharacterTile extends StatelessWidget {
  const _CharacterTile(this.ch);

  final Map<String, dynamic> ch;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final label = t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
    final va = text([ch['va_name']]).isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: _card(c),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(width: 48, height: 70, child: Cover(text([ch['image']]), radius: 12, showBorder: false)),
          Expanded(
            child: _names(
              context,
              ch['name'],
              ch['native_name'],
              Text(
                prettyEnum(text([ch['role']])),
                style: label?.copyWith(color: ch['role'] == 'MAIN' ? c.secondary : c.onSurfaceVariant),
              ),
            ),
          ),
          if (va) ...[
            Expanded(
              child: _names(
                context,
                ch['va_name'],
                ch['va_native_name'],
                Text(text([ch['va_language'], 'Japanese']), style: label?.copyWith(color: c.primary)),
                end: true,
              ),
            ),
            SizedBox(width: 48, height: 70, child: Cover(text([ch['va_image']]), radius: 12, showBorder: false)),
          ],
        ],
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile(this.person);

  final Map<String, dynamic> person;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: _card(t.colorScheme),
      child: Row(
        spacing: 12,
        children: [
          SizedBox(width: 48, height: 70, child: Cover(text([person['image']]), radius: 12, showBorder: false)),
          Expanded(
            child: _names(
              context,
              person['name'],
              person['native_name'],
              Text(
                text([person['role']]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A prequel, sequel, adaptation…: a manga opens on AniList, an anime searches the sources.
class _RelationTile extends StatelessWidget {
  const _RelationTile(this.m, {required this.onTap});

  final Map<String, dynamic> m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final line = [_mediaLine(m), prettyEnum(text([m['status']]))].where((s) => s.isNotEmpty).join(' · ');
    return BouncyTap(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: _card(c),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(width: 60, height: 84, child: Cover(text([m['cover']]), radius: 12, showBorder: false)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      PillBadge(
                        label: prettyEnum(text([m['relation']])),
                        color: c.onSecondaryContainer,
                        backgroundColor: c.secondaryContainer,
                      ),
                      if (toInt(m['score']) > 0)
                        Text(
                          '★ ${(toInt(m['score']) / 10).toStringAsFixed(1)}',
                          style: t.textTheme.labelMedium?.copyWith(color: c.tertiary, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  Text(
                    text([m['title_english'], m['title_romaji']]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                  ),
                  if (line.isNotEmpty)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(m['media_type'] == 'MANGA' ? Icons.open_in_new_rounded : Icons.search_rounded, size: 18, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The desktop's Download dialog: one episode, a range, or all, at a quality.
Future<void> showDownloadSheet(BuildContext context, AnimeData data, {Map<String, dynamic>? single}) {
  final eps = data.episodes;
  final from = TextEditingController(text: eps.isEmpty ? '1' : '${eps.first['num']}');
  final to = TextEditingController(text: eps.isEmpty ? '1' : '${eps.last['num']}');
  var mode = single != null ? 'single' : 'range';
  var quality = text([Api.setting('quality'), 'best']);

  List<dynamic> selection() {
    if (mode == 'single') return [?single];
    if (mode == 'all') return eps;
    final a = int.tryParse(from.text) ?? 0, b = int.tryParse(to.text) ?? 0;
    final (lo, hi) = a < b ? (a, b) : (b, a);
    return eps.where((e) => e['num'] >= lo && e['num'] <= hi).toList();
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final t = Theme.of(context);
        final c = t.colorScheme;
        final picked = selection();
        final chosen = picked.where((e) => !data.localFiles.containsKey(e['url'])).toList(); // already-downloaded ones are skipped

        ChoiceChip choice(String label, String value) =>
            ChoiceChip(label: Text(label), selected: mode == value, onSelected: (_) => setState(() => mode = value));

        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 28 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('Download episodes', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                children: [
                  if (single != null) choice('Episode ${single['num']}', 'single'),
                  choice('Range', 'range'),
                  choice('All ${eps.length}', 'all'),
                ],
              ),
              if (mode == 'range')
                Row(
                  spacing: 12,
                  children: [
                    for (final (field, label) in [(from, 'From'), (to, 'To')])
                      Expanded(
                        child: TextField(
                          controller: field,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: label),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                ),
              Text('Quality', style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              Wrap(
                spacing: 8,
                children: [
                  for (final q in ['best', '1080p', '720p', '480p', '360p'])
                    ChoiceChip(
                      label: Text(q == 'best' ? 'Auto' : q),
                      selected: quality == q,
                      onSelected: (_) => setState(() => quality = q),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: BouncyTap(
                  borderRadius: BorderRadius.circular(999),
                  onTap: chosen.isEmpty
                      ? null
                      : () {
                          Api.get('download', {
                            'source': data.anime['source'],
                            'name': data.anime['name'],
                            'url': data.anime['url'],
                            'quality': quality,
                            'meta': data.meta?.containsKey('anilist_id') == true ? data.meta : null,
                            'episodes': [
                              for (final e in chosen) {'num': e['num'], 'url': e['url']},
                            ],
                          });
                          Navigator.pop(context);
                          toast(chosen.length > 1 ? 'Downloading ${chosen.length} episodes' : 'Download started');
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: chosen.isEmpty ? c.surfaceContainerHighest : c.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      picked.isNotEmpty && chosen.isEmpty
                          ? 'Already downloaded'
                          : chosen.length > 1
                          ? 'Download ${chosen.length} episodes'
                          : 'Download',
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w700,
                        color: chosen.isEmpty ? c.onSurfaceVariant : c.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
