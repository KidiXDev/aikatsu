import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'anime.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onFindSomething});

  final VoidCallback onFindSomething;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> _series = [];
  bool _recent = false; // the Recent chip instead of Continue
  bool _autoplay = Api.setting('autoplay') == 'true';
  Map<String, dynamic>? _heroMeta;
  String _heroKey = '';

  List<dynamic> get _continuing => _series.where((s) => s['finished'] != true).toList();
  Map<String, dynamic>? get _hero => _continuing.isEmpty ? null : _continuing.first;

  @override
  void initState() {
    super.initState();
    _refresh();
    Api.historyRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    Api.historyRevision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _series = Api.get('history');
      _autoplay = Api.setting('autoplay') == 'true';
    });
    final hero = _hero;
    if (hero == null || hero['key'] == _heroKey) return;
    _heroKey = hero['key'];
    _heroMeta = null;
    if (toInt(hero['anilist_id']) > 0) {
      Api.call('enrich', {'anilistId': hero['anilist_id']}).then((m) {
        if (mounted && _heroKey == hero['key']) setState(() => _heroMeta = m);
      }, onError: (_) {});
    }
  }

  static Map<String, dynamic> _animeOf(Map<String, dynamic> s) => {
    'name': s['title'],
    'url': s['url'],
    'image': s['cover'],
    'source': s['source'],
    'anilistId': s['anilist_id'],
  };

  static double _progressOf(Map<String, dynamic> s) {
    final ep = (s['episodes'] as List).firstWhere((e) => e['episode_number'] == s['continue_episode'], orElse: () => null);
    final duration = toInt(ep?['duration']);
    return duration > 0 ? toInt(ep['playback_time']) / duration : 0;
  }

  static String _episodeOf(Map<String, dynamic> s, String sep) {
    final cont = toInt(s['continue_episode']), total = toInt(s['total_episodes']);
    return 'Episode $cont${total >= cont ? '$sep$total' : ''}';
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _menu(Map<String, dynamic> s) async {
    final choice = await pickFrom(context, s['title'], [
      ('Open', 'open', false),
      ('Continue episode', 'play', false),
      ('Remove from history', 'delete', false),
    ]);
    if (!mounted) return;
    switch (choice) {
      case 'open':
        openAnime(context, _animeOf(s));
      case 'play':
        openAnime(context, _animeOf(s), autoplayEpisode: toInt(s['continue_episode']));
      case 'delete':
        if (await _confirm('Remove from history?', 'All saved progress for “${s['title']}” will be deleted.', 'Remove')) {
          Api.get('deleteSeries', {'key': s['key']});
          _refresh();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _recent ? _series : _continuing;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _heroBanner(context)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.play_circle_outline_rounded),
                  label: Text('Continue  ${_continuing.length}'),
                  selected: !_recent,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _recent = false),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.history_rounded),
                  label: Text('Recent  ${_series.length}'),
                  selected: _recent,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _recent = true),
                ),
                FilterChip(
                  label: const Text('Autoplay'),
                  selected: _autoplay,
                  onSelected: (v) {
                    Api.setSetting('autoplay', v);
                    setState(() => _autoplay = v);
                  },
                ),
                if (_series.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('Clear all'),
                    onPressed: () async {
                      if (await _confirm(
                        'Clear all history?',
                        "Every series and its progress will be removed. This can't be undone.",
                        'Clear all',
                      )) {
                        Api.get('clearHistory');
                        _refresh();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        if (shown.isEmpty)
          SliverToBoxAdapter(
            child: _series.isEmpty
                ? const EmptyState(
                    face: '(っ˘ω˘ς )',
                    title: 'Nothing watched yet',
                    message: 'Your watch history shows up here. Search for an anime to begin.',
                  )
                : const EmptyState(
                    face: '٩(◕‿◕｡)۶',
                    title: 'All caught up!',
                    message: "You've finished everything you started. Check Recent to rewatch.",
                  ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: posterGrid(),
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final s = shown[i] as Map<String, dynamic>;
                final finished = s['finished'] == true;
                return PosterCard(
                  title: s['title'],
                  subtitle: finished ? 'Finished ✓' : _episodeOf(s, ' / '),
                  image: s['cover'],
                  badge: s['source'],
                  progress: finished ? -1 : _progressOf(s),
                  onTap: () => openAnime(context, _animeOf(s)),
                  onLongPress: () => _menu(s),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _heroBanner(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final hero = _hero, meta = _heroMeta;
    final banner = text([meta?['banner'], meta?['cover'], hero?['cover']]);
    final genres = (meta?['genres'] as List?)?.take(3).join(' · ') ?? '';
    final blur = text([meta?['banner']]).isEmpty ? 20.0 : 3.0; // covers stretched to a banner need more
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (banner.isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c.secondaryContainer, c.surfaceContainer])),
            )
          else
            BlurredArt(banner, sigma: blur),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.surface.withValues(alpha: 0.15), c.surface.withValues(alpha: 0.6), c.surface],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hero != null) ...[
                  SizedBox(width: 110, height: 160, child: Cover(text([meta?['cover'], hero['cover']]))),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hero != null ? 'CONTINUE WATCHING' : 'おかえり · WELCOME',
                        style: t.textTheme.labelLarge?.copyWith(color: c.primary),
                      ),
                      Text(
                        hero != null ? text([meta?['title_english'], hero['title']]) : 'Aikatsu',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.headlineSmall,
                      ),
                      Text(
                        hero != null
                            ? _episodeOf(hero, ' of ') + (genres.isEmpty ? '' : '  ·  $genres')
                            : 'Watch anime with Indonesian subtitles and pick up right where you left off.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            icon: Icon(hero != null ? Icons.play_arrow_rounded : Icons.search_rounded),
                            label: Text(hero != null ? 'Continue  ·  Ep ${hero['continue_episode']}' : 'Find something to watch'),
                            onPressed: hero != null
                                ? () => openAnime(context, _animeOf(hero), autoplayEpisode: toInt(hero['continue_episode']))
                                : widget.onFindSomething,
                          ),
                          if (hero != null)
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.info_outline_rounded),
                              label: const Text('Details'),
                              onPressed: () => openAnime(context, _animeOf(hero)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
