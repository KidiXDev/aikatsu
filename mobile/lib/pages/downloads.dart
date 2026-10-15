import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';
import 'player.dart';

const _active = {'queued', 'resolving', 'downloading', 'remuxing'};

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  Map<int, dynamic> _jobs = {}; // id → job
  late final StreamSubscription<(String, dynamic)> _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = Api.pushed.listen((event) {
      final (kind, job) = event;
      if (kind == 'download') setState(() => _jobs[job['id']] = job);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _reload() => setState(() => _jobs = {for (final j in Api.get('downloads') as List) j['id'] as int: j});

  static String _bytes(num n) => n > 1073741824 ? '${(n / 1073741824).toStringAsFixed(2)} GB' : '${(n / 1048576).toStringAsFixed(1)} MB';

  void _play(Map<String, dynamic> job) {
    final data = AnimeData.local(title: job['title'], episode: job['episode'], path: job['path']);
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(data: data, index: 0)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final jobs = _jobs.values.toList()..sort((a, b) => b['id'] - a['id']);
    final hasFinished = jobs.any((j) => j['state'] == 'done' || j['state'] == 'failed' || j['state'] == 'cancelled');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Downloads', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (hasFinished)
                BouncyTap(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Api.get('clearDownloads');
                    _reload();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all_rounded, size: 16, color: c.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Clear finished',
                          style: TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 12.5, fontWeight: FontWeight.w600, color: c.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: jobs.isEmpty
              ? const SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: 110),
                  child: EmptyState(
                    face: '( ˘▽˘)っ♨',
                    title: 'No downloads yet',
                    message: 'Open an anime and use Download… to save single episodes, a range, or the whole series for offline watching.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), // clearance for bottom nav
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _tile(context, jobs[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> j) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final aikatsu = context.aikatsu;
    final state = j['state'] as String;
    final active = _active.contains(state);
    final downloading = state == 'downloading' && toInt(j['total']) > 0;

    final detail = switch (state) {
      'failed' => Api.describe(j['error']),
      'downloading' => '${_bytes(j['bytes'])} of ${_bytes(j['total'])}  ·  ${_bytes(j['speed'])}/s',
      'done' => 'Ready to watch · Tap to play',
      'queued' => 'Waiting in queue…',
      'resolving' => 'Finding the video stream…',
      'remuxing' => 'Finishing and packing file…',
      'cancelled' => 'Download cancelled',
      _ => '',
    };

    final icon = switch (state) {
      'done' => Icons.play_arrow_rounded,
      'failed' => Icons.error_outline_rounded,
      'cancelled' => Icons.block_rounded,
      'queued' => Icons.schedule_rounded,
      'resolving' => Icons.travel_explore_rounded,
      'remuxing' => Icons.movie_edit,
      _ => Icons.download_rounded,
    };

    final statusColor = switch (state) {
      'done' => c.primary,
      'failed' => c.error,
      'cancelled' => c.outline,
      _ => c.primary,
    };

    final r = BorderRadius.circular(18);

    return BouncyTap(
      borderRadius: r,
      onTap: state == 'done' ? () => _play(j) : (state == 'failed' ? () => toast('${j['error']}') : null),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: r,
          border: Border.all(color: state == 'done' ? c.primary.withValues(alpha: 0.4) : c.outlineVariant.withValues(alpha: 0.5), width: 1),
          boxShadow: state == 'done' ? aikatsu.softShadow : null,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Status avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: statusColor, size: 22),
            ),
            const SizedBox(width: 14),
            // Info & Progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${j['title']}  ·  Episode ${j['episode']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: state == 'failed' ? c.error : c.onSurfaceVariant, fontSize: 12),
                  ),
                  if (active) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: downloading ? toDouble(j['progress']) : null,
                        minHeight: 5,
                        backgroundColor: c.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(aikatsu.sakuraGlow),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 10),
              IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => Api.get('cancelDownload', {'id': j['id']})),
            ],
          ],
        ),
      ),
    );
  }
}
