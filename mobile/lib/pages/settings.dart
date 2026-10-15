import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
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
    final c = t.colorScheme;
    final a4k = '${_s['anime4k']}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110), // clearance for bottom nav
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Settings', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),

        // Appearance Group
        _SettingsGroup(
          title: 'Appearance',
          icon: Icons.palette_rounded,
          children: [
            ListTile(
              title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (key, label) in [('system', 'System'), ('dark', 'Dark'), ('light', 'Light')])
                      ChoiceChip(label: Text(label), selected: _s['theme'] == key, onSelected: (_) => _set('theme', key)),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Playback Group
        _SettingsGroup(
          title: 'Playback',
          icon: Icons.play_circle_rounded,
          children: [
            SwitchListTile(
              title: const Text('Autoplay next episode', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Starts the next episode after a 5 second countdown.'),
              value: _s['autoplay'] == 'true',
              onChanged: (v) => _set('autoplay', v),
            ),
            SwitchListTile(
              title: const Text('Skip intro & outro automatically', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Jumps past openings and endings when their timing is known.'),
              value: _s['autoSkip'] == 'true',
              onChanged: (v) => _set('autoSkip', v),
            ),
            ListTile(
              title: const Text('Preferred quality', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final q in ['best', '1080p', '720p', '480p'])
                      ChoiceChip(
                        label: Text(q == 'best' ? 'Auto' : q),
                        selected: _s['quality'] == q,
                        onSelected: (_) => _set('quality', q),
                      ),
                  ],
                ),
              ),
            ),
            ListTile(
              title: const Text('Sharpen video (Anime4K)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                "Makes lower-quality video look crisper on your phone's GPU."
                '${_shadersInstalled ? '' : ' A small add-on downloads the first time you use it.'}',
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
                trailing: (key == 'off' ? a4k.isEmpty || a4k == 'off' : a4k == key) ? Icon(Icons.check_rounded, color: c.primary) : null,
                onTap: () => _set('anime4k', key),
              ),
          ],
        ),

        // Sources Group
        _SettingsGroup(
          title: 'Sources',
          icon: Icons.public_rounded,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                "Search looks through every site that's turned on. A site that keeps failing is skipped for 10 minutes.",
                style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ),
            for (final s in _sources)
              SwitchListTile(
                title: Text(s['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                value: !_disabled.contains(s['key']),
                onChanged: (v) => _toggleSource(s['key'] as String, v),
              ),
          ],
        ),

        // Downloads Group
        _SettingsGroup(
          title: 'Downloads',
          icon: Icons.download_rounded,
          children: [
            ListTile(
              title: const Text('Download folder', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${Api.get('downloadDir')}'),
            ),
            const ListTile(
              title: Text('HLS episodes are saved as .ts', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text("Plays fine here and in most media players."),
            ),
            ListTile(
              title: const Text('TMDB API key (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextFormField(
                  initialValue: '${_s['tmdbKey']}',
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'API key',
                    helperText: 'Helps sort long-running shows into the right season folders.',
                  ),
                  onChanged: (v) => Api.setSetting('tmdbKey', v.trim()),
                ),
              ),
            ),
          ],
        ),

        // Other Group
        _SettingsGroup(
          title: 'Other',
          icon: Icons.tune_rounded,
          children: [
            SwitchListTile(
              title: const Text('Debug logging', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Extra detail for troubleshooting, after a restart.'),
              value: _s['debug'] == 'true',
              onChanged: (v) => _set('debug', v),
            ),
            ListTile(
              title: const Text('Logs', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('What the app has been doing, for bug reports.'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: _showLogs,
            ),
            ListTile(
              title: const Text('Cached data', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Kept for a few days so pages open faster.'),
              trailing: TextButton(
                onPressed: () {
                  Api.get('clearCache');
                  toast('Cache cleared');
                },
                child: const Text('Clear'),
              ),
            ),
          ],
        ),

        // Brand & Version Footer
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              SakuraBlossom(size: 32, petalColor: c.primary, centerColor: c.secondary),
              const SizedBox(height: 10),
              Text(
                'Aikatsu ${Api.get('version')}',
                style: const TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text('GPL-3.0 License  ·  (ﾉ´ヮ`)ﾉ*: ･ﾟ', style: t.textTheme.bodySmall?.copyWith(color: c.outline)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A cozy grouped card for settings sections with an icon badge header.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final aikatsu = context.aikatsu;
    final r = BorderRadius.circular(22);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(icon, size: 16, color: c.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w700, fontSize: 14, color: c.primary),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceContainer,
              borderRadius: r,
              border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5), width: 1),
              boxShadow: aikatsu.cardShadow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: c.outlineVariant.withValues(alpha: 0.35)),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
