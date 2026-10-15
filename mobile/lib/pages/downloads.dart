import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
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
    final jobs = _jobs.values.toList()..sort((a, b) => b['id'] - a['id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text('Downloads', style: t.textTheme.headlineSmall)),
              TextButton.icon(
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear finished'),
                onPressed: () {
                  Api.get('clearDownloads');
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: jobs.isEmpty
              ? const SingleChildScrollView(
                  child: EmptyState(
                    face: '( ˘▽˘)っ♨',
                    title: 'No downloads yet',
                    message: 'Open an anime and use Download… to save single episodes, a range, or the whole series.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _tile(context, jobs[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> j) {
    final t = Theme.of(context);
    final state = j['state'] as String;
    final active = _active.contains(state);
    final downloading = state == 'downloading' && toInt(j['total']) > 0;
    final detail = switch (state) {
      'failed' => Api.describe(j['error']),
      'downloading' => '${_bytes(j['bytes'])} of ${_bytes(j['total'])}  ·  ${_bytes(j['speed'])}/s',
      'done' => 'Tap to play',
      'queued' => 'Waiting…',
      'resolving' => 'Finding the video…',
      'remuxing' => 'Finishing up…',
      'cancelled' => 'Cancelled',
      _ => '',
    };
    final icon = switch (state) {
      'done' => Icons.check_rounded,
      'failed' => Icons.error_outline_rounded,
      'cancelled' => Icons.block_rounded,
      'queued' => Icons.schedule_rounded,
      'resolving' => Icons.travel_explore_rounded,
      'remuxing' => Icons.movie_edit,
      _ => Icons.download_rounded,
    };
    return Material(
      color: t.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: state == 'failed' ? t.colorScheme.error : t.colorScheme.primary),
        title: Text('${j['title']}  ·  Episode ${j['episode']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (active) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: downloading ? toDouble(j['progress']) : null, borderRadius: BorderRadius.circular(4)),
            ],
          ],
        ),
        trailing: active
            ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Api.get('cancelDownload', {'id': j['id']}))
            : null,
        onTap: state == 'done' ? () => _play(j) : (state == 'failed' ? () => toast('${j['error']}') : null),
      ),
    );
  }
}
