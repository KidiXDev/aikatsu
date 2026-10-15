import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
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
      ('Open details', 'open', false),
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
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          sliver: SliverToBoxAdapter(child: _heroBanner(context)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Animated pill segment for Continue / Recent
                  _HistorySegmentedControl(
                    recent: _recent,
                    continueCount: _continuing.length,
                    recentCount: _series.length,
                    onChanged: (isRecent) => setState(() => _recent = isRecent),
                  ),
                  const SizedBox(width: 10),
                  // Autoplay pill switch
                  FilterChip(
                    avatar: Icon(_autoplay ? Icons.bolt_rounded : Icons.pause_circle_outline_rounded, size: 16),
                    label: const Text('Autoplay'),
                    selected: _autoplay,
                    onSelected: (v) {
                      Api.setSetting('autoplay', v);
                      setState(() => _autoplay = v);
                    },
                  ),
                  if (_series.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
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
                ],
              ),
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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), // comfortable bottom clearance for nav capsule
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
    final aikatsu = context.aikatsu;
    final hero = _hero, meta = _heroMeta;
    final banner = text([meta?['banner'], meta?['cover'], hero?['cover']]);
    final genres = (meta?['genres'] as List?)?.take(3).join(' · ') ?? '';
    final r = BorderRadius.circular(24);

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: r,
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5), width: 1),
        boxShadow: aikatsu.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background artwork
          if (banner.isNotEmpty) Positioned.fill(child: BlurredArt(banner, sigma: text([meta?['banner']]).isEmpty ? 22.0 : 4.0)),
          // Warm solid gradient overlay to maintain absolute readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.surfaceContainer.withValues(alpha: 0.3), c.surfaceContainer.withValues(alpha: 0.85), c.surfaceContainer],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hero != null) ...[
                  SizedBox(width: 104, height: 154, child: Cover(text([meta?['cover'], hero['cover']]), radius: 16)),
                  const SizedBox(width: 18),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tag header with mini sakura blossom
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SakuraBlossom(size: 16, petalColor: c.primary, centerColor: c.secondary),
                          const SizedBox(width: 6),
                          Text(
                            hero != null ? 'CONTINUE WATCHING' : 'おかえり · WELCOME',
                            style: t.textTheme.labelMedium?.copyWith(color: c.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hero != null ? text([meta?['title_english'], hero['title']]) : 'Aikatsu',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hero != null
                            ? _episodeOf(hero, ' of ') + (genres.isEmpty ? '' : '  ·  $genres')
                            : 'Watch anime with Indonesian subtitles and pick up right where you left off.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          BouncyTap(
                            borderRadius: BorderRadius.circular(999),
                            onTap: hero != null
                                ? () => openAnime(context, _animeOf(hero), autoplayEpisode: toInt(hero['continue_episode']))
                                : widget.onFindSomething,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              decoration: BoxDecoration(
                                color: c.primary,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: aikatsu.softShadow,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(hero != null ? Icons.play_arrow_rounded : Icons.search_rounded, size: 18, color: c.onPrimary),
                                  const SizedBox(width: 6),
                                  Text(
                                    hero != null ? 'Continue  ·  Ep ${hero['continue_episode']}' : 'Find something to watch',
                                    style: TextStyle(
                                      fontFamily: 'GoogleSansFlex',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: c.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (hero != null)
                            BouncyTap(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => openAnime(context, _animeOf(hero)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                decoration: BoxDecoration(
                                  color: c.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.info_outline_rounded, size: 18, color: c.onSurface),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Details',
                                      style: TextStyle(
                                        fontFamily: 'GoogleSansFlex',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: c.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

/// Custom segmented pill control for switching between Continue and Recent history.
class _HistorySegmentedControl extends StatelessWidget {
  const _HistorySegmentedControl({required this.recent, required this.continueCount, required this.recentCount, required this.onChanged});

  final bool recent;
  final int continueCount;
  final int recentCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(
            label: 'Continue  $continueCount',
            icon: Icons.play_circle_outline_rounded,
            selected: !recent,
            onTap: () => onChanged(false),
          ),
          _Tab(label: 'Recent  $recentCount', icon: Icons.history_rounded, selected: recent, onTap: () => onChanged(true)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return BouncyTap(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: selected ? c.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? c.onPrimaryContainer : c.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
                color: selected ? c.onPrimaryContainer : c.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
