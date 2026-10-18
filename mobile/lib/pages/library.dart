import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../history.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';
import 'player.dart';

String _titleOf(Map<String, dynamic> s) => text([s['meta']['title_english'], s['meta']['title_romaji'], s['series_name']]);

String _removedNote(int count) =>
    count == 1 ? 'Deletes it from this phone.' : 'Deletes all $count episodes from this phone.';


String _localTitle(Map<String, dynamic> s) => text([s['meta']?['title_english'], s['meta']?['title_romaji'], s['name']]);

const _files = MethodChannel('io.github.kidixdev.aikatsu/files');

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<dynamic> _series = [];
  List<dynamic> _history = [];
  Map<String, dynamic> _local = {'folders': [], 'series': []};
  bool _recent = false;
  late final StreamSubscription<(String, dynamic)> _sub;

  List<dynamic> get _continuing => _history.where((s) => s['finished'] != true).toList();

  @override
  void initState() {
    super.initState();
    _reload();
    _loadLocal();
    Api.libraryRevision.addListener(_reload);
    Api.historyRevision.addListener(_refreshAll);
    _sub = Api.pushed.listen((e) {
      if (e.$1 == 'download' && e.$2['state'] == 'done') _reload();
      if (e.$1 == 'local') _loadLocal();
    });
  }

  @override
  void dispose() {
    Api.libraryRevision.removeListener(_reload);
    Api.historyRevision.removeListener(_refreshAll);
    _sub.cancel();
    super.dispose();
  }

  void _reload() => setState(() {
    _series = Api.get('library');
    _history = Api.get('history');
  });

  void _refreshAll() {
    _reload();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final lib = await Api.call('localLibrary') as Map<String, dynamic>;
    if (!mounted) return;
    setState(() => _local = lib);
    if ((lib['series'] as List).any((s) => s['available'] == true && s['meta'] == null)) Api.call('matchLocal').ignore();
  }

  Future<void> _addFolder() async {
    try {
      final path = await _files.invokeMethod<String>('pickFolder');
      if (path == null) return;
      Api.get('addLocalFolder', {'path': path});
      _loadLocal();
    } on PlatformException catch (e) {
      toast(e.message ?? "Couldn't open the folder picker");
    } catch (e) {
      toast('$e');
    }
  }

  void _removeFolder(String path) {
    Api.get('removeLocalFolder', {'path': path});
    _loadLocal();
  }

  void _openLocal(Map<String, dynamic> s) {
    if (s['available'] != true) {
      toast('Connect the storage with “${s['path']}” first');
      return;
    }
    openAnime(context, {
      'name': s['name'],
      'url': s['path'],
      'image': text([s['meta']?['cover']]),
      'source': 'local',
      'anilistId': toInt(s['meta']?['anilist_id']),
    });
  }

  Future<void> _localMenu(Map<String, dynamic> s) async {
    final choice = await pickFrom(context, _localTitle(s), [('Open', 'open', false), ('Choose anime…', 'match', false)]);
    if (!mounted) return;
    if (choice == 'open') _openLocal(s);
    if (choice == 'match') chooseAnime(context, s['path'], s['name']);
  }

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
    final shown = _recent ? _history : _continuing;
    final folders = _local['folders'] as List;
    final local = _local['series'] as List;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(child: Text('Library', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
                FilledButton.tonalIcon(icon: const Icon(Icons.create_new_folder_rounded), label: const Text('Add folder'), onPressed: _addFolder),
              ],
            ),
          ),
        ),
        if (_history.isNotEmpty) ...[
          _section(context, 'Continue watching', Icons.history_rounded),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerLeft,
                child: HistorySegmentedControl(
                  recent: _recent,
                  continueCount: _continuing.length,
                  recentCount: _history.length,
                  onChanged: (isRecent) => setState(() => _recent = isRecent),
                ),
              ),
            ),
          ),
          if (shown.isEmpty)
            const SliverToBoxAdapter(child: EmptyState(face: '٩(◕‿◕｡)۶', title: 'All caught up!', message: 'Check Recent to rewatch.'))
          else
            _grid(shown.length, (i) => HistoryCard(shown[i] as Map<String, dynamic>)),
        ],
        _section(context, 'Your folders', Icons.folder_rounded),
        if (folders.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in folders)
                    InputChip(
                      avatar: Icon(
                        f['available'] == true ? Icons.folder_rounded : Icons.folder_off_rounded,
                        size: 18,
                        color: f['available'] == true ? c.onSurfaceVariant : c.error,
                      ),
                      label: Text(f['available'] == true ? f['path'] : '${f['path']}  ·  not connected', overflow: TextOverflow.ellipsis),
                      onDeleted: () => _removeFolder(f['path']),
                    ),
                ],
              ),
            ),
          ),
        if (folders.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              face: '( ˘▽˘)っ♨',
              title: 'Bring your own anime',
              message: 'Add a folder of videos and pick which anime it is. Episodes play here with your progress saved.',
            ),
          )
        else if (local.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(face: '(・_・ヾ', title: 'No videos found', message: 'Aikatsu looks in each folder and two levels of subfolders.'),
          )
        else
          _grid(local.length, (i) {
            final s = local[i] as Map<String, dynamic>;
            final available = s['available'] == true;
            final count = toInt(s['episodes']);
            return Opacity(
              opacity: available ? 1 : 0.5,
              child: PosterCard(
                title: _localTitle(s),
                image: text([s['meta']?['cover']]),
                subtitle: !available
                    ? 'Storage not connected'
                    : s['meta'] == null
                    ? 'Choose anime'
                    : count == 1
                    ? '1 episode'
                    : '$count episodes',
                onTap: () => _openLocal(s),
                onLongPress: () => _localMenu(s),
              ),
            );
          }),
        if (_series.isNotEmpty) ...[
          _section(context, 'Downloaded', Icons.download_done_rounded, subtitle: '${_series.length} anime  ·  ${formatBytes(total)}'),
          _grid(_series.length, (i) {
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
          }),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 110)), // clearance for the nav capsule
      ],
    );
  }
}

Widget _section(BuildContext context, String title, IconData icon, {String subtitle = ''}) {
  final t = Theme.of(context);
  return SliverPadding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
    sliver: SliverToBoxAdapter(
      child: Row(
        children: [
          Icon(icon, size: 20, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _grid(int count, Widget Function(int) item) => SliverPadding(
  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
  sliver: SliverGrid.builder(gridDelegate: posterGrid(), itemCount: count, itemBuilder: (_, i) => item(i)),
);

Future<Map<String, dynamic>?> chooseAnime(BuildContext context, String path, String query) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _MatchSheet(path: path, query: query),
);

class _MatchSheet extends StatefulWidget {
  const _MatchSheet({required this.path, required this.query});

  final String path, query;

  @override
  State<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends State<_MatchSheet> {
  late final _field = TextEditingController(text: widget.query);
  List<dynamic> _results = [];
  bool _searching = false;
  String _error = '';
  Timer? _typing;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _field.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = ++_request;
    setState(() {
      _searching = true;
      _error = '';
    });
    try {
      final list = await Api.call('searchAnime', {'query': _field.text}) as List;
      if (mounted && id == _request) {
        setState(() {
          _results = list;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted && id == _request) {
        setState(() {
          _error = Api.describe(e);
          _searching = false;
        });
      }
    }
  }

  Future<void> _pick(Map<String, dynamic> m) async {
    try {
      final meta = await Api.call('linkLocal', {'path': widget.path, 'anilistId': m['anilist_id']}) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context, meta);
    } catch (e) {
      toast("Couldn't link it: ${Api.describe(e)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('Choose anime', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _field,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search AniList'),
                onChanged: (_) {
                  _typing?.cancel();
                  _typing = Timer(const Duration(milliseconds: 400), _search);
                },
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: _searching
                          ? const CircularProgressIndicator()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error.isNotEmpty ? _error : 'No matches. Try the English or Japanese title.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.onSurfaceVariant),
                              ),
                            ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final m = _results[i] as Map<String, dynamic>;
                        final details = [
                          if (toInt(m['year']) > 0) '${m['year']}',
                          if (toInt(m['episodes']) > 0) '${m['episodes']} episodes',
                          if (text([m['title_english']]).isNotEmpty) text([m['title_romaji']]),
                        ];
                        return ListTile(
                          leading: SizedBox(width: 40, height: 58, child: Cover(text([m['cover']]), radius: 8)),
                          title: Text(text([m['title_english'], m['title_romaji']]), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(details.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _pick(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
    final source = Api.sourceName(_series['source']);
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
