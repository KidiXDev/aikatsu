import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'pages/account.dart';
import 'pages/anime.dart';
import 'widgets.dart';

/// Watch together (core party.rs): links handed over by Android, joining, and the player's sheet.
abstract final class PartyLinks {
  static const _channel = MethodChannel('io.github.kidixdev.aikatsu/link');

  /// A link to join: the one that opened the app, or one opened while it runs.
  static final opened = ValueNotifier<String?>(null);

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') opened.value = call.arguments as String?;
    });
    opened.value = await _channel.invokeMethod<String>('initial');
  }

  static Future<void> share(String text) => _channel.invokeMethod('share', {'text': text});
}

/// Joins, then plays the party's episode in place of whatever was open. The old
/// player goes first: it leaves its own party when it closes.
Future<void> joinParty(BuildContext context, String link) async {
  Navigator.popUntil(context, (route) => route.isFirst);
  try {
    final p = Map<String, dynamic>.from(await Api.call('partyJoin', {'link': link}));
    Api.party.value = p;
    if (context.mounted) openAnime(context, Map<String, dynamic>.from(p['state']['anime']), autoplayEpisode: toInt(p['state']['episode']));
  } catch (e) {
    toast('$e');
  }
}

/// Asks for a link, with one already copied filled in.
Future<void> askToJoin(BuildContext context) async {
  final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
  if (!context.mounted) return;
  var link = copied.contains('/party/') || copied.startsWith('aikatsu://') ? copied : '';
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Join a party'),
      content: TextFormField(
        initialValue: link,
        autofocus: link.isEmpty,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Party link'),
        onChanged: (v) => link = v.trim(),
        onFieldSubmitted: (_) => Navigator.pop(context, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join')),
      ],
    ),
  );
  if (go == true && link.isNotEmpty && context.mounted) await joinParty(context, link);
}

/// `playback` is the player's `{anime, episode, position, paused, speed}`, for starting a party.
Future<void> showPartySheet(BuildContext context, {required Map<String, Object?> Function() playback}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PartySheet(playback: playback),
    );

class _PartySheet extends StatefulWidget {
  const _PartySheet({required this.playback});

  final Map<String, Object?> Function() playback;

  @override
  State<_PartySheet> createState() => _PartySheetState();
}

class _PartySheetState extends State<_PartySheet> {
  bool _signedIn = Api.get('syncStatus')['signedIn'] == true;
  bool _busy = false;
  String _error = '';

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      Api.party.value = Map<String, dynamic>.from(await Api.call('partyCreate', widget.playback()));
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signIn() async {
    await signIn(context, create: false);
    if (mounted) setState(() => _signedIn = Api.get('syncStatus')['signedIn'] == true);
  }

  void _leave() {
    Api.get('partyLeave');
    Api.party.value = Map<String, dynamic>.from(Api.get('party'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ValueListenableBuilder(
          valueListenable: Api.party,
          builder: (context, p, _) {
            final active = p['active'] == true;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Watch together', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (!_signedIn) ...[
                  const Text('Sign in to sync first.'),
                  const SizedBox(height: 16),
                  Align(alignment: Alignment.centerRight, child: FilledButton.tonal(onPressed: _signIn, child: const Text('Sign in'))),
                ] else if (!active) ...[
                  const Text('Anyone signed in to your sync server can join with the link.'),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _busy ? null : _start, child: Text(_busy ? 'Starting…' : 'Start')),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p['qr'] is Map) QrCode(Map<String, dynamic>.from(p['qr'])),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText('${p['link']}', style: t.textTheme.bodyMedium),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.share_rounded),
                                  label: const Text('Share'),
                                  onPressed: () => PartyLinks.share('${p['link']}'),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.content_copy_rounded),
                                  label: const Text('Copy'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: '${p['link']}'));
                                    toast('Link copied');
                                  },
                                ),
                                TextButton(onPressed: _leave, child: const Text('Leave')),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final m in (p['members'] as List? ?? []))
                                  Chip(
                                    avatar: Icon(m['device'] == 'android' ? Icons.smartphone_rounded : Icons.computer_rounded, size: 16),
                                    label: Text(m['username'] == p['me'] ? 'You' : '${m['username']}'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_error, style: TextStyle(color: t.colorScheme.error)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// `qr` is the core's `{size, modules}`: one '1' per dark module, row by row.
class QrCode extends StatelessWidget {
  const QrCode(this.qr, {super.key, this.size = 168});

  final Map<String, dynamic> qr;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(12), // the quiet zone scanners look for
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: CustomPaint(painter: _QrPainter(toInt(qr['size']), '${qr['modules']}')),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.n, this.modules);

  final int n;
  final String modules;

  @override
  void paint(Canvas canvas, Size size) {
    if (n == 0) return;
    final cell = size.width / n;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (modules.codeUnitAt(y * n + x) == 0x31) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.modules != modules;
}
