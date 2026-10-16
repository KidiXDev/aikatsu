import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../widgets.dart';

/// Called once the app's first frame is ready; checks never install plugins.
Future<void> checkPluginUpdatesOnOpen(BuildContext context) async {
  if (Api.setting('autoCheckPluginUpdates') != 'true') return;
  try {
    final repos = await Api.call('checkPluginUpdates') as List;
    final count = repos.fold<int>(0, (n, r) => n + toInt(r['updates']));
    if (!context.mounted || count == 0) return;
    final review = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$count plugin update${count == 1 ? '' : 's'} available'),
        content: const Text('Open Plugins to review and download updates.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('View updates')),
        ],
      ),
    );
    if (review == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const _PluginsPage()));
    }
  } catch (_) {
    // An offline launch should still open normally; Plugins shows the check error.
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _s = Api.get('settings');
  Map<String, dynamic> _account = Api.get('syncStatus');
  StreamSubscription<(String, dynamic)>? _pushSub;
  final List<dynamic> _modes = Api.get('anime4kModes');
  bool _shadersInstalled = Api.get('anime4kInstalled');
  bool _installingShaders = false;

  @override
  void initState() {
    super.initState();
    _pushSub = Api.pushed.listen((e) {
      if (!mounted) return;
      if (e.$1 == 'plugins') setState(() {});
      if (e.$1 == 'sync') {
        setState(() {
          _account = Map<String, dynamic>.from(e.$2);
          if (e.$2['settings'] == true) _s = Api.get('settings');
        });
      }
    });
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    super.dispose();
  }

  bool get _signedIn => _account['signedIn'] == true;

  String get _syncedLabel {
    final at = toInt(_account['lastSync']);
    if (at == 0) return 'Not synced yet';
    final mins = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at * 1000)).inMinutes;
    if (mins < 1) return 'Synced just now';
    if (mins < 60) return 'Synced $mins min ago';
    return mins < 1440
        ? 'Synced ${mins ~/ 60} h ago'
        : 'Synced ${MaterialLocalizations.of(context).formatShortDate(DateTime.fromMillisecondsSinceEpoch(at * 1000))}';
  }

  Future<void> _syncNow() async {
    setState(() => _account = {..._account, 'syncing': true});
    try {
      final status = await Api.call('syncNow');
      if (mounted) setState(() => _account = Map<String, dynamic>.from(status));
    } catch (e) {
      toast('$e');
    }
  }

  String get _host => '${_account['server']}'.replaceFirst(RegExp(r'^https?://'), '');

  Future<void> _changeServer() async {
    String url = '${_account['server']}', error = '';
    final status = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save(String value) async {
            try {
              final st = await Api.call('syncSetServer', {'server': value});
              if (context.mounted) Navigator.pop(context, Map<String, dynamic>.from(st));
            } catch (e) {
              if (context.mounted) setDialogState(() => error = '$e');
            }
          }

          return AlertDialog(
            title: const Text('Server'),
            content: TextFormField(
              initialValue: url,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Custom server',
                hintText: 'Empty uses the default',
                errorText: error.isEmpty ? null : error,
                errorMaxLines: 3,
              ),
              onChanged: (v) => setDialogState(() => url = v),
              onFieldSubmitted: (_) => save(url),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: () => save(url), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (status != null && mounted) setState(() => _account = status);
  }

  /// `fields` are (label, secret). The error from `run` shows under the last field.
  Future<bool> _form(
    String title,
    String actionLabel,
    List<(String, bool)> fields,
    Future<void> Function(List<String>) run, {
    String? message,
  }) async {
    final values = List.filled(fields.length, '');
    String error = '';
    bool busy = false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              final ready = !busy && values.every((v) => v.trim().isNotEmpty);
              Future<void> submit() async {
                if (!ready) return;
                setDialogState(() {
                  busy = true;
                  error = '';
                });
                try {
                  await run(values);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) {
                    setDialogState(() {
                      busy = false;
                      error = '$e';
                    });
                  }
                }
              }

              return AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 16,
                    children: [
                      if (message != null) Text(message),
                      for (final (i, (label, secret)) in fields.indexed)
                        TextField(
                          autofocus: i == 0,
                          autocorrect: false,
                          obscureText: secret,
                          textInputAction: i < fields.length - 1 ? TextInputAction.next : TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: label,
                            errorText: i == fields.length - 1 && error.isNotEmpty ? error : null,
                            errorMaxLines: 3,
                          ),
                          onChanged: (v) => setDialogState(() => values[i] = v),
                          onSubmitted: (_) => submit(),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  TextButton(onPressed: ready ? submit : null, child: Text(busy ? 'Please wait…' : actionLabel)),
                ],
              );
            },
          ),
        ) ??
        false;
  }

  Future<void> _signIn({required bool create}) async {
    final done = await _form(create ? 'Create account' : 'Sign in', create ? 'Create' : 'Sign in', [
      ('Username', false),
      ('Password', true),
    ], (v) => Api.call('syncSignIn', {'username': v[0].trim(), 'password': v[1], 'create': create}));
    if (!done || !mounted) return;
    setState(() => _account = Api.get('syncStatus'));
    toast(create ? 'Account created' : 'Signed in');
  }

  Future<void> _accountAction(String action) async {
    switch (action) {
      case 'password':
        final done = await _form(
          'Change password',
          'Change',
          [('Current password', true), ('New password', true)],
          (v) => Api.call('syncChangePassword', {'current': v[0], 'password': v[1]}),
          message: 'Other devices will be signed out.',
        );
        if (done) toast('Password changed');
      case 'signOut':
        if (!await confirm(context, 'Sign out?', 'Your history stays on this device.', 'Sign out')) return;
        final status = await Api.call('syncSignOut');
        if (mounted) setState(() => _account = Map<String, dynamic>.from(status));
      case 'delete':
        final done = await _form(
          'Delete account?',
          'Delete',
          [('Password', true)],
          (v) => Api.call('syncDeleteAccount', {'password': v[0]}),
          message: 'Your synced data will be deleted from the server.',
        );
        if (done && mounted) {
          setState(() => _account = Api.get('syncStatus'));
          toast('Account deleted');
        }
    }
  }

  List<String> get _disabled => '${_s['disabledSources']}'.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  String get _sourcesSummary {
    final all = Api.get('sources') as List;
    final on = all.where((p) => !_disabled.contains(p['key'])).length;
    final noun = all.length == 1 ? 'source' : 'sources';
    return all.isEmpty ? 'None installed' : (on == all.length ? '${all.length} $noun' : '$on of ${all.length} $noun on');
  }

  void _set(String key, Object value) {
    Api.setSetting(key, value);
    setState(() => _s = Api.get('settings'));
  }

  String get _anime4kName => (_modes.firstWhere((m) => m['key'] == _s['anime4k'], orElse: () => null)?['name'] as String?) ?? 'Off';

  Future<void> _pickAnime4k() async {
    final current = '${_s['anime4k']}';
    final key = await pickFrom(context, 'Sharpen video', [
      ('Off', 'off', current.isEmpty || current == 'off'),
      for (final m in _modes) (m['name'] as String, m['key'] as String, current == m['key']),
    ]);
    if (key != null) _set('anime4k', key);
  }

  /// One of a few values, splitting the row evenly so it fits exactly.
  Widget _segments(String key, List<(String, String)> options) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: SegmentedButton<String>(
      expandedInsets: EdgeInsets.zero,
      showSelectedIcon: false,
      segments: [for (final (value, label) in options) ButtonSegment(value: value, label: Text(label))],
      selected: {'${_s[key]}'},
      onSelectionChanged: (v) => _set(key, v.first),
    ),
  );

  Future<void> _openPlugins() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const _PluginsPage()));
    if (mounted) setState(() => _s = Api.get('settings'));
  }

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

  void _showLogs() {
    String logs = '', error = '';
    bool exporting = false;
    void load() {
      try {
        logs = Api.get('logTail') as String;
        error = '';
      } catch (e) {
        error = '$e';
      }
    }

    load();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text('Logs', style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                        tooltip: 'Export log',
                        icon: const Icon(Icons.save_alt_rounded),
                        onPressed: exporting
                            ? null
                            : () async {
                                setSheetState(() => exporting = true);
                                try {
                                  final saved = await const MethodChannel('io.github.kidixdev.aikatsu/logs')
                                      .invokeMethod<bool>('exportLog', {'contents': Api.get('logReport')});
                                  if (context.mounted && saved == true) toast('Log saved. Attach the .txt file to your GitHub issue.');
                                } catch (e) {
                                  if (context.mounted) toast("Couldn't export log: $e");
                                } finally {
                                  if (context.mounted) setSheetState(() => exporting = false);
                                }
                              },
                      ),
                      IconButton(tooltip: 'Refresh logs', icon: const Icon(Icons.refresh_rounded), onPressed: () => setSheetState(load)),
                      IconButton(tooltip: 'Close logs', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: error.isNotEmpty || logs.trim().isEmpty
                      ? SingleChildScrollView(
                          child: EmptyState(
                            face: error.isNotEmpty ? '(×﹏×)' : '(˘▾˘)',
                            error: error.isNotEmpty,
                            title: error.isNotEmpty ? "Couldn't load logs" : 'No log entries yet',
                            message: error.isNotEmpty
                                ? 'Try refreshing. If this continues, restart the app.'
                                : 'Nothing has been recorded this session. Use the app, then refresh to check again.',
                            details: error,
                          ),
                        )
                      : SingleChildScrollView(
                          reverse: true, // newest lines at the bottom, in view
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(logs, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110), // clearance for bottom nav
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Settings', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),

        _SettingsGroup(
          title: 'Sync',
          icon: Icons.sync_rounded,
          children: [
            if (_signedIn)
              ListTile(
                title: Text('Signed in as ${_account['username']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(text([_account['error'], _syncedLabel])),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _account['syncing'] == true
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(icon: const Icon(Icons.sync_rounded), tooltip: 'Sync now', onPressed: _syncNow),
                    PopupMenuButton<String>(
                      onSelected: _accountAction,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'password', child: Text('Change password')),
                        PopupMenuItem(value: 'signOut', child: Text('Sign out')),
                        PopupMenuItem(value: 'delete', child: Text('Delete account')),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              ListTile(
                title: const Text('Not signed in', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: '${_account['error']}'.isEmpty ? null : Text('${_account['error']}'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(onPressed: () => _signIn(create: true), child: const Text('Create account')),
                    FilledButton.tonal(onPressed: () => _signIn(create: false), child: const Text('Sign in')),
                  ],
                ),
              ),
            ],
            ListTile(
              title: const Text('Server', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_host.isEmpty ? 'Default' : _host),
              trailing: TextButton(onPressed: _signedIn ? null : _changeServer, child: const Text('Change')),
            ),
          ],
        ),

        // Appearance Group
        _SettingsGroup(
          title: 'Appearance',
          icon: Icons.palette_rounded,
          children: [
            ListTile(
              title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _segments('theme', const [('system', 'System'), ('dark', 'Dark'), ('light', 'Light')]),
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
              value: _s['autoplay'] == 'true',
              onChanged: (v) => _set('autoplay', v),
            ),
            SwitchListTile(
              title: const Text('Skip intro & outro', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _s['autoSkip'] == 'true',
              onChanged: (v) => _set('autoSkip', v),
            ),
            ListTile(
              title: const Text('Preferred quality', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: _segments('quality', const [('best', 'Auto'), ('1080p', '1080p'), ('720p', '720p'), ('480p', '480p')]),
            ),
            ListTile(
              title: const Text('Sharpen video (Anime4K)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_anime4kName),
              trailing: _shadersInstalled
                  ? const Icon(Icons.arrow_forward_ios_rounded, size: 16)
                  : FilledButton.tonal(
                      onPressed: _installingShaders ? null : _installShaders,
                      child: Text(_installingShaders ? 'Downloading…' : 'Download'),
                    ),
              onTap: _pickAnime4k,
            ),
          ],
        ),

        // Sources Group
        _SettingsGroup(
          title: 'Sources',
          icon: Icons.public_rounded,
          children: [
            ListTile(
              title: const Text('Plugins', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_sourcesSummary),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: _openPlugins,
            ),
            SwitchListTile(
              title: const Text('Check for plugin updates on startup', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Updates are downloaded only when you choose.'),
              value: _s['autoCheckPluginUpdates'] == 'true',
              onChanged: (v) => _set('autoCheckPluginUpdates', v),
            ),
          ],
        ),

        // Downloads Group
        _SettingsGroup(
          title: 'Downloads',
          icon: Icons.download_rounded,
          children: [
            ListTile(
              title: const Text('TMDB API key', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextFormField(
                  initialValue: '${_s['tmdbKey']}',
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'Optional'),
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
              subtitle: const Text('Applies after a restart.'),
              value: _s['debug'] == 'true',
              onChanged: (v) => _set('debug', v),
            ),
            ListTile(
              title: const Text('Logs', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: _showLogs,
            ),
            ListTile(
              title: const Text('Cache', style: TextStyle(fontWeight: FontWeight.w600)),
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

/// Plugin repos and the sources each brings, opened from Settings.
class _PluginsPage extends StatefulWidget {
  const _PluginsPage();

  @override
  State<_PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<_PluginsPage> {
  List<dynamic> _repos = Api.get('repos');
  bool _syncing = false;
  StreamSubscription<(String, dynamic)>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Api.pushed.listen((e) {
      if (e.$1 == 'plugins' && mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() => _repos = Api.get('repos'));

  List<String> get _disabled => Api.setting('disabledSources').split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  int get _updates => _repos.fold<int>(0, (n, r) => n + toInt(r['updates']));

  void _toggle(String key, bool on) {
    Api.setSetting('disabledSources', [..._disabled.where((k) => k != key), if (!on) key].join(','));
    setState(() {});
  }

  Future<void> _checkUpdates({bool download = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await Api.call(download ? 'syncPlugins' : 'checkPluginUpdates');
      if (!mounted) return;
      setState(() => _repos = (download ? result['repos'] : result) as List);
      String message = 'Plugins are up to date';
      if (_repos.any((r) => r['error'] != null)) {
        message = download ? "Some repos couldn't update" : "Some repos couldn't be checked";
      } else if (download && result['updated'] == true) {
        message = 'Plugins updated';
      } else if (_updates > 0) {
        message = '$_updates plugin update${_updates == 1 ? '' : 's'} available';
      }
      toast(message);
    } catch (e) {
      toast('$e');
    }
    if (mounted) setState(() => _syncing = false);
  }

  /// Asks for a GitHub link and returns what that repo holds; nothing is added yet.
  Future<Map<String, dynamic>?> _askRepo() {
    String url = '', error = '';
    bool busy = false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> check() async {
            if (url.trim().isEmpty || busy) return;
            setDialogState(() {
              busy = true;
              error = '';
            });
            try {
              final preview = await Api.call('previewRepo', {'url': url.trim()});
              if (context.mounted) Navigator.pop(context, Map<String, dynamic>.from(preview));
            } catch (e) {
              if (context.mounted) {
                setDialogState(() {
                  busy = false;
                  error = '$e';
                });
              }
            }
          }

          return AlertDialog(
            title: const Text('Add plugins'),
            content: TextField(
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://github.com/user/repo',
                errorText: error.isEmpty ? null : error,
                errorMaxLines: 3,
              ),
              onChanged: (v) => url = v,
              onSubmitted: (_) => check(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(onPressed: busy ? null : check, child: Text(busy ? 'Checking…' : 'Add')),
            ],
          );
        },
      ),
    );
  }

  /// Kyoko goes straight in; any other repo asks for trust first.
  Future<void> _add() async {
    final preview = await _askRepo();
    if (preview == null || !mounted) return;
    if (preview['official'] != true) {
      final names = [for (final p in preview['plugins'] as List) p['name']].join(', ');
      final ok = await confirm(
        context,
        'Trust this repo?',
        '${preview['short']} can see what you search and watch, open any website, and choose the videos you play. '
            'Only add repos you trust.${names.isEmpty ? '' : '\n\nAdds $names'}',
        'Trust and add',
      );
      if (!ok) return;
    }
    await _install(preview['url'] as String, preview['name'] as String);
  }

  Future<void> _install(String url, String name) async {
    if (!mounted || _syncing) return;
    setState(() => _syncing = true);
    try {
      final list = await Api.call('addRepo', {'url': url}) as List;
      if (!mounted) return;
      setState(() => _repos = list);
      toast(list.any((r) => r['url'] == url && r['error'] != null) ? 'Added $name; some plugins could not load' : 'Added $name');
    } catch (e) {
      toast('$e');
    }
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _remove(Map<String, dynamic> repo) async {
    if (!await confirm(context, 'Remove ${repo['name']}?', 'Its sources will be removed from search.', 'Remove')) return;
    if (!mounted || _syncing) return;
    setState(() => _syncing = true);
    try {
      final list = await Api.call('removeRepo', {'url': repo['url']}) as List;
      if (mounted) setState(() => _repos = list);
    } catch (e) {
      toast('$e');
    }
    if (mounted) setState(() => _syncing = false);
  }

  void _addKyoko() => _install(Api.get('officialRepo') as String, 'Kyoko');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    const bold = TextStyle(fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          if (_updates > 0)
            IconButton(
              tooltip: 'Download $_updates plugin update${_updates == 1 ? '' : 's'}',
              onPressed: _syncing ? null : () => _checkUpdates(download: true),
              icon: const Icon(Icons.download_rounded),
            ),
          IconButton(
            tooltip: 'Check for updates',
            onPressed: _syncing ? null : () => _checkUpdates(),
            icon: _syncing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
          if (_updates > 0 && MediaQuery.sizeOf(context).width < 400)
            IconButton(tooltip: 'Add plugins', onPressed: _syncing ? null : _add, icon: const Icon(Icons.add_rounded))
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.tonalIcon(
                onPressed: _syncing ? null : _add,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ),
        ],
      ),
      body: _repos.isEmpty
          ? EmptyState(
              face: '(・・ )?',
              title: 'No plugins',
              message: 'Search needs at least one.',
              action: FilledButton.tonal(onPressed: _syncing ? null : _addKyoko, child: const Text('Add Kyoko')),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final repo in _repos)
                  _SettingsGroup(
                    title: repo['name'] as String,
                    icon: repo['official'] == true ? Icons.verified_rounded : Icons.extension_rounded,
                    children: [
                      for (final p in repo['plugins'] as List)
                        p['loaded'] == true
                            ? SwitchListTile(
                                title: Text(p['name'] as String, style: bold),
                                value: !_disabled.contains(p['key']),
                                onChanged: (v) => _toggle(p['key'] as String, v),
                              )
                            : ListTile(
                                title: Text(p['name'] as String, style: bold),
                                subtitle: Text(
                                  p['compatible'] == true
                                      ? p['updateAvailable'] == true
                                            ? 'Download to enable'
                                            : "Couldn't load"
                                      : 'Needs a newer Aikatsu',
                                ),
                              ),
                      ListTile(
                        title: Text(
                          repo['error'] != null
                              ? "Couldn't check or update"
                              : '${repo['short']}${repo['official'] == true ? '' : '  ·  Third-party'}',
                          style: t.textTheme.bodySmall?.copyWith(color: repo['error'] != null ? c.error : c.onSurfaceVariant),
                        ),
                        subtitle: repo['error'] != null
                            ? Text('${repo['error']}', maxLines: 2, overflow: TextOverflow.ellipsis)
                            : toInt(repo['updates']) > 0
                            ? Text('${repo['updates']} plugin update${repo['updates'] == 1 ? '' : 's'} available')
                            : null,
                        trailing: TextButton(
                          style: TextButton.styleFrom(foregroundColor: c.error),
                          onPressed: _syncing ? null : () => _remove(Map<String, dynamic>.from(repo)),
                          child: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                if (!_repos.any((r) => r['official'] == true))
                  Center(
                    child: TextButton(onPressed: _syncing ? null : _addKyoko, child: const Text('Add Kyoko')),
                  ),
              ],
            ),
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
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w700, fontSize: 14, color: c.primary),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: c.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: r,
              side: BorderSide(color: c.outlineVariant.withValues(alpha: 0.5), width: 1),
            ),
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
