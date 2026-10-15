import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onSearch});

  /// Switches to Search; a non-empty query also runs it.
  final ValueChanged<String> onSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> _series = [];
  bool _recent = false; // the Recent chip instead of Continue
  bool _autoplay = Api.setting('autoplay') == 'true';
  Map<String, dynamic>? _heroMeta;
  String _heroKey = '';
  Map<String, dynamic>? _discover; // AniList schedule, trending and upcoming (see core meta::discover)
  bool _discoverFailed = false;

  List<dynamic> get _continuing => _series.where((s) => s['finished'] != true).toList();
  Map<String, dynamic>? get _hero => _continuing.isEmpty ? null : _continuing.first;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadDiscover();
    Api.historyRevision.addListener(_refresh);
  }

  Future<void> _loadDiscover({bool refresh = false}) async {
    try {
      final d = await Api.call('discover', {'refresh': refresh});
      if (!mounted) return;
      setState(() {
        _discover = d;
        _discoverFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _discoverFailed = true);
    }
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
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await _loadDiscover(refresh: true);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                      showCheckmark: false,
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
          // A fresh install has no history: the sections below fill Home instead.
          if (shown.isEmpty && _series.isNotEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                face: '٩(◕‿◕｡)۶',
                title: 'All caught up!',
                message: "You've finished everything you started. Check Recent to rewatch.",
              ),
            )
          else if (shown.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
          ..._discoverSections(context),
          const SliverToBoxAdapter(child: SizedBox(height: 110)), // clearance for the nav capsule
        ],
      ),
    );
  }

  List<Widget> _discoverSections(BuildContext context) {
    final d = _discover;
    if (d == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: _discoverFailed
                  ? Text(
                      "Couldn't load what's airing. Pull down to try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      ];
    }
    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final schedule = (d['schedule'] as List).cast<Map<String, dynamic>>();
    final aired = schedule.where((a) => toInt(a['airing_at']) <= nowSec).toList().reversed.toList(); // newest first
    final next = schedule.where((a) => toInt(a['airing_at']) > nowSec).toList();
    String genre(Map<String, dynamic> m) => (m['genres'] as List).take(2).join(' · ');
    String score(Map<String, dynamic> m) => toInt(m['score']) > 0 ? '★ ${(toInt(m['score']) / 10).toStringAsFixed(1)}' : '';

    _DiscoverItem airing(Map<String, dynamic> a) {
      final label = airingLabel(toInt(a['airing_at']), now);
      return (
        meta: a['anime'],
        badge: 'Ep ${a['episode']}',
        subtitle: label,
        note: 'Episode ${a['episode']} · ${label.endsWith('ago') ? 'aired $label' : 'airs $label'}',
      );
    }

    return [
      _DiscoverRow(title: 'Out today', icon: Icons.new_releases_rounded, items: aired.map(airing).toList(), onOpen: _showInfo),
      _DiscoverRow(title: 'Up next', icon: Icons.schedule_rounded, items: next.map(airing).toList(), onOpen: _showInfo),
      _DiscoverRow(
        title: 'Trending now',
        icon: Icons.local_fire_department_rounded,
        items: [
          for (final m in (d['trending'] as List).cast<Map<String, dynamic>>()) (meta: m, badge: score(m), subtitle: genre(m), note: ''),
        ],
        onOpen: _showInfo,
      ),
      _DiscoverRow(
        title: 'Coming soon',
        icon: Icons.event_rounded,
        items: [
          for (final m in (d['coming_soon'] as List).cast<Map<String, dynamic>>())
            (meta: m, badge: toInt(m['year']) > 0 ? '${m['year']}' : '', subtitle: genre(m), note: 'Not out yet'),
        ],
        onOpen: _showInfo,
      ),
    ];
  }

  /// Details only: Aikatsu can't stream from AniList, so the way on is a source search.
  Future<void> _showInfo(_DiscoverItem item) async {
    final m = item.meta;
    final title = text([m['title_english'], m['title_romaji']]);
    final query = text([m['title_romaji'], m['title_english']]); // the sources mostly use romaji names
    final search = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final t = Theme.of(context);
        final c = t.colorScheme;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 100, height: 146, child: Cover(text([m['cover']]), radius: 16)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (text([m['title_romaji']]) != title || text([m['title_native']]).isNotEmpty)
                            Text(
                              [m['title_romaji'], m['title_native']].where((s) => text([s]).isNotEmpty && s != title).join('  ·  '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                            ),
                          if (item.note.isNotEmpty)
                            Text(
                              item.note,
                              style: t.textTheme.labelLarge?.copyWith(color: c.primary, fontWeight: FontWeight.w700),
                            ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (toInt(m['score']) > 0)
                                PillBadge(label: '★ ${(toInt(m['score']) / 10).toStringAsFixed(1)}', color: c.tertiary),
                              if (toInt(m['year']) > 0) PillBadge(label: '${m['year']}', icon: Icons.calendar_month_rounded),
                              if (toInt(m['episodes']) > 0) PillBadge(label: '${m['episodes']} eps', icon: Icons.video_library_rounded),
                              if (text([m['status']]).isNotEmpty) PillBadge(label: '${m['status']}'.replaceAll('_', ' ').toLowerCase()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((m['genres'] as List).isNotEmpty)
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final g in m['genres'] as List) PillBadge(label: '$g')]),
                if (text([m['description']]).isNotEmpty)
                  Text(m['description'], style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.4)),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.search_rounded),
                    label: Text('Search sources for “$query”', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (search == true) widget.onSearch(query);
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
                  colors: [
                    c.surfaceContainer.withValues(alpha: 0.25),
                    c.surfaceContainer.withValues(alpha: 0.85),
                    c.surfaceContainer,
                    c.surfaceContainer,
                  ],
                  stops: const [0.0, 0.5, 0.9, 1.0],
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
                                : () => widget.onSearch(''),
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

typedef _DiscoverItem = ({Map<String, dynamic> meta, String badge, String subtitle, String note});

/// A titled horizontal shelf of posters; hidden when empty.
class _DiscoverRow extends StatelessWidget {
  const _DiscoverRow({required this.title, required this.icon, required this.items, required this.onOpen});

  final String title;
  final IconData icon;
  final List<_DiscoverItem> items;
  final ValueChanged<_DiscoverItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SliverToBoxAdapter();
    final t = Theme.of(context);
    final c = t.colorScheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              spacing: 8,
              children: [
                Icon(icon, size: 20, color: c.primary),
                Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final item = items[i];
                return SizedBox(
                  width: 128,
                  child: PosterCard(
                    title: text([item.meta['title_english'], item.meta['title_romaji']]),
                    image: text([item.meta['cover']]),
                    badge: item.badge,
                    subtitle: item.subtitle,
                    onTap: () => onOpen(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
