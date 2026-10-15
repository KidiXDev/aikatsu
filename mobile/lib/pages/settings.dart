import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _s = Api.get('settings');
  final List<dynamic> _sources = Api.get('sources');
  final List<dynamic> _modes = Api.get('anime4kModes');
  bool _shadersInstalled = Api.get('anime4kInstalled');
  bool _installingShaders = false;

  List<String> get _disabled => '${_s['disabledSources']}'.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  void _set(String key, Object value) {
    Api.setSetting(key, value);
    setState(() => _s = Api.get('settings'));
  }

  void _toggleSource(String key, bool on) => _set('disabledSources', [..._disabled.where((k) => k != key), if (!on) key].join(','));

  Future<void> _installShaders() async {
    setState(() => _installingShaders = true);
    try {
      await Api.call('installShaders', {'gan': false});
      _shadersInstalled = true;
    } catch (e) {
      toast('$e');
    }
    if (mounted) setState(() => _installingShaders = false);
  }

  void _showLogs() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: SingleChildScrollView(
        reverse: true, // newest lines at the bottom, in view
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SelectableText(Api.get('logTail'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final a4k = '${_s['anime4k']}';
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Settings', style: t.textTheme.headlineSmall),
        ),
        _header(context, 'Appearance', Icons.palette_rounded),
        ListTile(
          title: const Text('Theme'),
          subtitle: Wrap(
            spacing: 8,
            children: [
              for (final (key, label) in [('system', 'System'), ('dark', 'Dark'), ('light', 'Light')])
                ChoiceChip(label: Text(label), selected: _s['theme'] == key, onSelected: (_) => _set('theme', key)),
            ],
          ),
        ),
        _header(context, 'Playback', Icons.play_circle_rounded),
        SwitchListTile(
          title: const Text('Autoplay next episode'),
          subtitle: const Text('Starts the next episode after a 5 second countdown.'),
          value: _s['autoplay'] == 'true',
          onChanged: (v) => _set('autoplay', v),
        ),
        SwitchListTile(
          title: const Text('Skip intro & outro automatically'),
          subtitle: const Text('Jumps past openings and endings when their timing is known.'),
          value: _s['autoSkip'] == 'true',
          onChanged: (v) => _set('autoSkip', v),
        ),
        ListTile(
          title: const Text('Preferred quality'),
          subtitle: Wrap(
            spacing: 8,
            children: [
              for (final q in ['best', '1080p', '720p', '480p'])
                ChoiceChip(label: Text(q == 'best' ? 'Auto' : q), selected: _s['quality'] == q, onSelected: (_) => _set('quality', q)),
            ],
          ),
        ),
        ListTile(
          title: const Text('Sharpen video (Anime4K)'),
          subtitle: Text(
            "Makes lower-quality video look crisper. Runs on your phone's graphics chip, so heavier modes can stutter or drain the battery. "
            'You can also change it from the player.${_shadersInstalled ? '' : ' A small add-on downloads the first time you use it.'}',
          ),
          trailing: _shadersInstalled
              ? null
              : FilledButton.tonal(
                  onPressed: _installingShaders ? null : _installShaders,
                  child: Text(_installingShaders ? 'Downloading…' : 'Download now'),
                ),
        ),
        for (final (key, name, description) in [
          ('off', 'Off', ''),
          for (final m in _modes) (m['key'] as String, m['name'] as String, m['description'] as String),
        ])
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            dense: true,
            title: Text(name),
            subtitle: description.isEmpty ? null : Text(description),
            trailing: (key == 'off' ? a4k.isEmpty || a4k == 'off' : a4k == key)
                ? Icon(Icons.check_rounded, color: t.colorScheme.primary)
                : null,
            onTap: () => _set('anime4k', key),
          ),
        _header(context, 'Sources', Icons.public_rounded),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Search looks through every site that's turned on. A site that keeps failing is skipped for 10 minutes.",
            style: t.textTheme.bodySmall,
          ),
        ),
        for (final s in _sources)
          SwitchListTile(title: Text(s['name']), value: !_disabled.contains(s['key']), onChanged: (v) => _toggleSource(s['key'], v)),
        _header(context, 'Downloads', Icons.download_rounded),
        ListTile(title: const Text('Download folder'), subtitle: Text('${Api.get('downloadDir')}')),
        const ListTile(
          title: Text('HLS episodes are saved as .ts'),
          subtitle: Text("There's no ffmpeg on Android to turn them into .mp4. They play fine here and in most players."),
        ),
        ListTile(
          title: const Text('TMDB API key (optional)'),
          subtitle: TextFormField(
            initialValue: '${_s['tmdbKey']}',
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'API key',
              helperText: 'Helps sort long-running shows into the right season folders.',
            ),
            onChanged: (v) => Api.setSetting('tmdbKey', v.trim()),
          ),
        ),
        _header(context, 'Other', Icons.tune_rounded),
        SwitchListTile(
          title: const Text('Debug logging'),
          subtitle: const Text('Extra detail for troubleshooting, after a restart.'),
          value: _s['debug'] == 'true',
          onChanged: (v) => _set('debug', v),
        ),
        ListTile(title: const Text('Logs'), subtitle: const Text('What the app has been doing, for bug reports.'), onTap: _showLogs),
        ListTile(
          title: const Text('Cached data'),
          subtitle: const Text('Anime details are kept for a few days so pages open faster, even when the info site is down.'),
          trailing: TextButton(
            onPressed: () {
              Api.get('clearCache');
              toast('Cache cleared');
            },
            child: const Text('Clear'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Aikatsu ${Api.get('version')}  ·  GPL-3.0  ·  (ﾉ´ヮ`)ﾉ*: ･ﾟ',
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
          ),
        ),
      ],
    );
  }

  static Widget _header(BuildContext context, String title, IconData icon) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 20, color: c.primary),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.primary)),
        ],
      ),
    );
  }
}
