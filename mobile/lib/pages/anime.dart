import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../widgets.dart';
import 'player.dart';

void openAnime(BuildContext context, Map<String, dynamic> anime, {int autoplayEpisode = 0}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AnimePage(anime: anime, autoplayEpisode: autoplayEpisode),
    ),
  );
}

/// What the anime page knows about a series. The player listens to it too,
/// since details can land after playback has started.
class AnimeData extends ChangeNotifier {
  AnimeData(this.anime) : local = false;

  /// A downloaded episode: plays the file, no source lookups or history.
  AnimeData.local({required String title, required int episode, required String path})
    : anime = {'name': title, 'url': path, 'image': '', 'source': 'local'},
      local = true,
      meta = {},
      metaLoaded = true,
      loading = false,
      episodes = [
        {'num': episode, 'url': path, 'title': ''},
      ];

  final Map<String, dynamic> anime; // {name, url, image, source, anilistId?}
  final bool local;
  Map<String, dynamic>? meta; // null until enrich answers, {} if it failed
  bool metaLoaded = false; // progress saves wait for this so the series key stays stable
  List<dynamic> episodes = [];
  Map<int, dynamic> info = {}; // episode number → {title, filler, recap}
  Map<int, dynamic> progress = {}; // episode number → progress row
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

  void refreshProgress() {
    if (local) return;
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
        notifyListeners();
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

  @override
  void initState() {
    super.initState();
    _data.addListener(_changed);
    Api.historyRevision.addListener(_data.refreshProgress);
    _data.load().then((_) {
      if (!mounted || widget.autoplayEpisode == 0 || _data.episodes.isEmpty) return;
      final i = _data.episodes.indexWhere((e) => e['num'] == widget.autoplayEpisode);
      _play(i >= 0 ? i : _data.continueIndex);
    });
  }

  @override
  void dispose() {
    Api.historyRevision.removeListener(_data.refreshProgress);
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

  Future<void> _episodeMenu(Map<String, dynamic> ep) async {
    final watched = _data.progress[ep['num']]?['completed'] == true;
    final choice = await pickFrom(context, 'Episode ${ep['num']}', [
      ('Play', 'play', false),
      (watched ? 'Mark as unwatched' : 'Mark as watched', 'toggle', false),
      ('Download episode', 'download', false),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final d = _data, meta = d.meta;
    var eps = d.episodes.where((e) => _jump.isEmpty || '${e['num']}'.startsWith(_jump)).toList();
    if (_descending) eps = eps.reversed.toList();
    final current = d.progress.isNotEmpty && d.episodes.isNotEmpty ? d.episodes[d.continueIndex]['num'] : null;
    final banner = text([meta?['banner'], meta?['cover'], widget.anime['image']]);
    final blur = text([meta?['banner']]).isEmpty ? 24.0 : 2.0;
    final subtitles = [
      meta?['title_romaji'],
      meta?['title_native'],
    ].where((s) => text([s]).isNotEmpty && s != text([meta?['title_english']]));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => d.load(refresh: true))],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: Cover(banner, radius: 0),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [c.surface.withValues(alpha: 0.2), c.surface],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, height: 160, child: Cover(d.cover)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.textTheme.titleLarge),
                          if (subtitles.isNotEmpty)
                            Text(
                              subtitles.join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip(context, widget.anime['source'], Icons.public_rounded),
                              if (toInt(meta?['score']) > 0) _chip(context, '★ ${(toInt(meta?['score']) / 10).toStringAsFixed(1)}', null),
                              if (toInt(meta?['year']) > 0) _chip(context, '${meta?['year']}', Icons.calendar_month_rounded),
                              if (d.episodes.isNotEmpty)
                                _chip(
                                  context,
                                  '${d.episodes.length} episodes${toInt(meta?['episodes']) > d.episodes.length ? ' of ${meta?['episodes']}' : ''}',
                                  Icons.video_library_rounded,
                                ),
                              if (text([meta?['status']]).isNotEmpty)
                                _chip(context, '${meta?['status']}'.replaceAll('_', ' ').toLowerCase(), Icons.radio_button_checked_rounded),
                              for (final g in (meta?['genres'] as List?) ?? []) _chip(context, '$g', null),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: Icon(d.loading ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
                        label: Text(
                          d.episodes.isEmpty
                              ? (d.loading ? 'Loading episodes…' : 'Play')
                              : d.progress.isNotEmpty
                              ? 'Continue  ·  Ep ${d.episodes[d.continueIndex]['num']}'
                              : 'Play  ·  Ep ${d.episodes.first['num']}',
                        ),
                        onPressed: d.episodes.isEmpty ? null : () => _play(d.continueIndex),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download…'),
                      onPressed: d.episodes.isEmpty ? null : () => showDownloadSheet(context, d),
                    ),
                  ],
                ),
                if (text([meta?['description']]).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _synopsisOpen = !_synopsisOpen),
                    child: Text(
                      meta!['description'],
                      maxLines: _synopsisOpen ? null : 4,
                      overflow: _synopsisOpen ? null : TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Episodes', style: t.textTheme.titleLarge)),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.tag_rounded, size: 18),
                          hintText: 'Jump to…',
                        ),
                        onChanged: (v) => setState(() => _jump = v),
                      ),
                    ),
                    IconButton(
                      icon: Icon(_descending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                      onPressed: () => setState(() => _descending = !_descending),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (d.loading && d.episodes.isEmpty)
            const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))
          else if (d.episodes.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                face: '(×﹏×)',
                error: true,
                title: d.error.isNotEmpty ? "Couldn't load episodes from ${widget.anime['source']}" : 'No episodes yet',
                message: d.error.isNotEmpty ? Api.describe(d.error) : "This source hasn't listed any episodes for this series.",
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 480,
                  mainAxisExtent: 76,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
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

  static Widget _chip(BuildContext context, String label, IconData? icon) =>
      Chip(avatar: icon == null ? null : Icon(icon, size: 16), label: Text(label), visualDensity: VisualDensity.compact);
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
        final chosen = selection();
        ChoiceChip choice(String label, String value) =>
            ChoiceChip(label: Text(label), selected: mode == value, onSelected: (_) => setState(() => mode = value));
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text('Download episodes', style: t.textTheme.titleLarge),
              Text('Episodes are saved to ${Api.get('downloadDir')}', style: t.textTheme.bodySmall),
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
              Text('Quality', style: t.textTheme.labelLarge),
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
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () {
                          Api.get('download', {
                            'source': data.anime['source'],
                            'name': data.anime['name'],
                            'quality': quality,
                            'meta': data.meta?.containsKey('anilist_id') == true ? data.meta : null,
                            'episodes': [
                              for (final e in chosen) {'num': e['num'], 'url': e['url']},
                            ],
                          });
                          Navigator.pop(context);
                          toast(chosen.length > 1 ? 'Downloading ${chosen.length} episodes' : 'Download started');
                        },
                  child: Text(chosen.length > 1 ? 'Download ${chosen.length} episodes' : 'Download'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
