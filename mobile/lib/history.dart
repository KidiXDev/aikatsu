import 'package:flutter/material.dart';

import 'api.dart';
import 'pages/anime.dart';
import 'widgets.dart';

Map<String, dynamic> historyAnime(Map<String, dynamic> s) => {
  'name': s['title'],
  'url': s['url'],
  'image': s['cover'],
  'source': s['source'],
  'anilistId': s['anilist_id'],
};

double historyProgress(Map<String, dynamic> s) {
  final ep = (s['episodes'] as List).firstWhere((e) => e['episode_number'] == s['continue_episode'], orElse: () => null);
  final duration = toInt(ep?['duration']);
  return duration > 0 ? toInt(ep['playback_time']) / duration : 0;
}

String historyEpisode(Map<String, dynamic> s, String sep) {
  final cont = toInt(s['continue_episode']), total = toInt(s['total_episodes']);
  return 'Episode $cont${total >= cont ? '$sep$total' : ''}';
}

class HistoryCard extends StatelessWidget {
  const HistoryCard(this.series, {super.key});

  final Map<String, dynamic> series;

  Future<void> _menu(BuildContext context) async {
    final s = series;
    final choice = await pickFrom(context, s['title'], [
      ('Open details', 'open', false),
      ('Continue episode', 'play', false),
      ('Remove from history', 'delete', false),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'open':
        openAnime(context, historyAnime(s));
      case 'play':
        openAnime(context, historyAnime(s), autoplayEpisode: toInt(s['continue_episode']));
      case 'delete':
        if (await confirm(context, 'Remove from history?', 'All saved progress for “${s['title']}” will be deleted.', 'Remove')) {
          Api.get('deleteSeries', {'key': s['key']});
          Api.historyRevision.value++;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = series['finished'] == true;
    return PosterCard(
      title: series['title'],
      subtitle: finished ? 'Finished ✓' : historyEpisode(series, ' / '),
      image: series['cover'],
      badge: Api.sourceName(series['source']),
      progress: finished ? -1 : historyProgress(series),
      onTap: () => openAnime(context, historyAnime(series)),
      onLongPress: () => _menu(context),
    );
  }
}

class HistorySegmentedControl extends StatelessWidget {
  const HistorySegmentedControl({super.key, required this.recent, required this.continueCount, required this.recentCount, required this.onChanged});

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
