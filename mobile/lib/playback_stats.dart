import 'dart:async';

import 'package:flutter/material.dart';

/// The Android libmpv build has no Lua stats script, so read its properties directly.
class PlaybackStats extends StatefulWidget {
  const PlaybackStats({super.key, required this.readProperty});

  final Future<String> Function(String) readProperty;

  @override
  State<PlaybackStats> createState() => _PlaybackStatsState();
}

class _PlaybackStatsState extends State<PlaybackStats> {
  static const _properties = {
    'video-format': 'Video codec',
    'video-params/w': 'Width',
    'video-params/h': 'Height',
    'container-fps': 'Source FPS',
    'estimated-vf-fps': 'Output FPS',
    'hwdec-current': 'Hardware decoder',
    'decoder-frame-drop-count': 'Decoder drops',
    'frame-drop-count': 'Output drops',
    'avsync': 'A/V sync (s)',
    'audio-codec-name': 'Audio codec',
    'audio-params/samplerate': 'Audio sample rate',
    'demuxer-cache-duration': 'Cache (s)',
  };
  Timer? _timer;
  String _text = 'Loading playback information…';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final lines = await Future.wait(_properties.entries.map((entry) async {
      String value;
      try {
        value = await widget.readProperty(entry.key);
      } catch (_) {
        value = '';
      }
      return '${entry.value}: ${value.isEmpty ? '—' : value}';
    }));
    if (!mounted) return;
    setState(() => _text = lines.join('\n'));
    _timer = Timer(const Duration(seconds: 1), _refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(8)),
      child: Text(_text, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11)),
    ),
  );
}
