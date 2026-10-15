import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';
import 'player.dart';

String _titleOf(Map<String, dynamic> s) => text([s['meta']['title_english'], s['meta']['title_romaji'], s['series_name']]);

String _removedNote(int count) =>
    count == 1 ? 'The downloaded episode is removed from this phone.' : 'All $count downloaded episodes are removed from this phone.';

String _sourceName(String key) => (Api.get('sources') as List).firstWhere((s) => s['key'] == key, orElse: () => null)?['name'] ?? key;

/// Downloaded anime, one poster per series. Everything here plays offline.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<dynamic> _series = [];
  late final StreamSubscription<(String, dynamic)> _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    Api.libraryRevision.addListener(_reload);
    _sub = Api.pushed.listen((e) {
      if (e.$1 == 'download' && e.$2['state'] == 'done') _reload();
    });
  }

  @override
  void dispose() {
    Api.libraryRevision.removeListener(_reload);
    _sub.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _series = Api.get('library'));

  Future<void> _menu(Map<String, dynamic> s) async {
    final choice = await pickFrom(context, _titleOf(s), [('Open', 'open', false), ('Delete all episodes', 'delete', false)]);
    if (!mounted) return;
    if (choice == 'open') {
      openLibrarySeries(context, s);
    } else if (choice == 'delete' &&
        await confirm(context, 'Delete “${_titleOf(s)}”?', _removedNote((s['episodes'] as List).length), 'Delete')) {
      Api.deleteDownloads([for (final e in s['episodes']) e['path'] as String]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final total = _series.fold<num>(0, (sum, s) => sum + toInt(s['size']));
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Library', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (_series.isNotEmpty)
                  Text(
                    '${_series.length} anime  ·  ${formatBytes(total)} on this phone',
                    style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        if (_series.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              face: '( ˘▽˘)っ♨',
              title: 'Nothing downloaded yet',
              message: 'Downloaded episodes show up here and play without internet. Open an anime and use Download… to save some.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverGrid.builder(
              gridDelegate: posterGrid(),
              itemCount: _series.length,
              itemBuilder: (context, i) {
                final s = _series[i] as Map<String, dynamic>;
                final count = (s['episodes'] as List).length;
                return PosterCard(
                  title: _titleOf(s),
                  image: text([s['meta']['cover']]),
                  badge: count == 1 ? '1 episode' : '$count episodes',
                  subtitle: formatBytes(toInt(s['size'])),
                  onTap: () => openLibrarySeries(context, s),
                  onLongPress: () => _menu(s),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 110)), // clearance for the nav capsule
      ],
    );
  }
}

void openLibrarySeries(BuildContext context, Map<String, dynamic> series) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => LibrarySeriesPage(series: series)));
}

/// Plays a finished download from the Downloads history; false when the file is gone.
bool playDownloaded(BuildContext context, String path) {
  for (final s in Api.get('library') as List) {
    final i = (s['episodes'] as List).indexWhere((e) => e['path'] == path);
    if (i < 0) continue;
    final data = AnimeData.library(s)..refreshProgress();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(data: data, index: i),
      ),
    );
    return true;
  }
  return false;
}

/// One downloaded series: its episodes on this phone, resume, delete, and a way
/// to the source for the rest.
class LibrarySeriesPage extends StatefulWidget {
  const LibrarySeriesPage({super.key, required this.series});

  final Map<String, dynamic> series;

  @override
  State<LibrarySeriesPage> createState() => _LibrarySeriesPageState();
}

class _LibrarySeriesPageState extends State<LibrarySeriesPage> {
  late Map<String, dynamic> _series = widget.series;
  late AnimeData _data;

  /// Progress first, then the listener: notifying while building would rebuild mid-build.
  AnimeData _open(Map<String, dynamic> s) => AnimeData.library(s)
    ..refreshProgress()
    ..addListener(_changed);

  @override
  void initState() {
    super.initState();
    _data = _open(_series);
    Api.historyRevision.addListener(_refreshProgress);
    Api.libraryRevision.addListener(_reload);
  }

  @override
  void dispose() {
    Api.historyRevision.removeListener(_refreshProgress);
    Api.libraryRevision.removeListener(_reload);
    _data.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});
  void _refreshProgress() => _data.refreshProgress();

  bool _same(Map<String, dynamic> s) =>
      s['source'] == _series['source'] &&
      (_series['series_url'] != '' ? s['series_url'] == _series['series_url'] : s['series_name'] == _series['series_name']);

  /// After a delete: fewer episodes, or none left and the page goes.
  void _reload() {
    final s = (Api.get('library') as List).cast<Map<String, dynamic>>().where(_same).firstOrNull;
    if (s == null) {
      final route = ModalRoute.of(context);
      if (route != null) Navigator.removeRoute(context, route); // may not be on top (the anime page can be)
      return;
    }
    final old = _data;
    setState(() {
      _series = s;
      _data = _open(s);
    });
    old.dispose();
  }

  void _play(int index) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerPage(data: _data, index: index),
    ),
  );

  Future<void> _deleteAll() async {
    final eps = _series['episodes'] as List;
    if (await confirm(context, 'Delete “${_titleOf(_series)}”?', _removedNote(eps.length), 'Delete')) {
      Api.deleteDownloads([for (final e in eps) e['path'] as String]);
    }
  }

  Future<void> _episodeMenu(int index) async {
    final ep = _data.episodes[index] as Map<String, dynamic>;
    final watched = _data.progress[ep['num']]?['completed'] == true;
    final choice = await pickFrom(context, 'Episode ${ep['num']}', [
      ('Play', 'play', false),
      (watched ? 'Mark as unwatched' : 'Mark as watched', 'toggle', false),
      ('Delete download', 'delete', false),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'play':
        _play(index);
      case 'toggle':
        Api.get('setCompleted', {'progress': _data.progressRow(ep), 'completed': !watched});
        Api.historyRevision.value++;
      case 'delete':
        if (await confirm(context, 'Delete episode ${ep['num']}?', 'The downloaded file is removed from this phone.', 'Delete')) {
          Api.deleteDownloads([_data.localFiles[ep['url']]!]);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = _data;
    final eps = d.episodes;
    final next = d.continueIndex;
    final started = d.progress.isNotEmpty;
    final source = _sourceName(_series['source']);
    return Scaffold(
      appBar: AppBar(
        title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Delete all', icon: const Icon(Icons.delete_sweep_rounded), onPressed: _deleteAll)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 104, height: 152, child: Cover(d.cover, radius: 16)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Text(
                      d.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PillBadge(label: source, icon: Icons.public_rounded),
                        PillBadge(label: eps.length == 1 ? '1 episode' : '${eps.length} episodes', icon: Icons.download_done_rounded),
                        PillBadge(label: formatBytes(toInt(_series['size']))),
                      ],
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('${started ? 'Continue' : 'Play'}  ·  Ep ${eps[next]['num']}'),
                      onPressed: () => _play(next),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_series['series_url'] != '')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.travel_explore_rounded),
                label: Text('More episodes on $source'),
                onPressed: () => openAnime(context, d.anime),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < eps.length; i++) ...[
            EpisodeTile(
              num: eps[i]['num'],
              title: d.episodeTitle(eps[i]),
              record: d.progress[eps[i]['num']],
              current: started && i == next,
              downloaded: true,
              onTap: () => _play(i),
              onLongPress: () => _episodeMenu(i),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
