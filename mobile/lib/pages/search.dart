import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  /// A search asked for from a page pushed over the tabs; the shell runs it on the Search tab.
  static final requested = ValueNotifier<String?>(null);

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  late final StreamSubscription<(String, dynamic)> _sub;
  String _query = '';
  int _request = 0;
  bool _searching = false;
  List<dynamic> _results = [];

  /// Source key → {name, state: loading|ok|error, count, error}.
  Map<String, Map<String, dynamic>> _status = {};
  String _filter = ''; // source key or ''

  List<dynamic> get _shown => _filter.isEmpty ? _results : _results.where((r) => r['source'] == _filter).toList();
  List<Map<String, dynamic>> get _failures => _status.values.where((s) => s['state'] == 'error').toList();
  bool get _allFailed => !_searching && _failures.isNotEmpty && _failures.length == _status.length;

  @override
  void initState() {
    super.initState();
    _sub = Api.pushed.listen((event) {
      final (kind, data) = event;
      // Any source while searching: on first launch the plugins arrive during the search.
      if (kind != 'searchResult' || !_searching || data['requestId'] != _request) return;
      setState(() {
        if (data['error'] != null) {
          _status[data['source']] = {'name': data['name'], 'state': 'error', 'count': 0, 'error': data['error']};
        } else {
          _status[data['source']] = {'name': data['name'], 'state': 'ok', 'count': (data['items'] as List).length};
          _results = [..._results, ...data['items']];
        }
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _field.dispose();
    super.dispose();
  }

  /// From Home's info sheets: fills the field and searches every source.
  void search(String q) => _search(q);

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.length < 2) return;
    final request = ++_request;
    _field.text = q;
    final disabled = Api.setting('disabledSources').split(',').map((x) => x.trim());
    setState(() {
      _query = q;
      _results = [];
      _filter = '';
      _searching = true;
      _status = {
        for (final s in Api.get('sources') as List)
          if (!disabled.contains(s['key'])) s['key'] as String: {'name': s['name'], 'state': 'loading', 'count': 0},
      };
    });
    try {
      await Api.call('search', {'query': q, 'requestId': request});
    } catch (_) {}
    if (!mounted || _request != request) return;
    setState(() {
      _searching = false;
      for (final s in _status.values) {
        if (s['state'] == 'loading') s['state'] = 'error';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final aikatsu = context.aikatsu;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Custom Warm Search Bar Capsule
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: c.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.outlineVariant.withValues(alpha: 0.55), width: 1),
              boxShadow: aikatsu.softShadow,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: c.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _field,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    style: const TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 15, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Search anime',
                      hintStyle: TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 14.5, color: c.onSurfaceVariant.withValues(alpha: 0.65)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation<Color>(c.primary)),
                    ),
                  )
                else if (_field.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _field.clear();
                      setState(() {
                        _query = '';
                        _results = [];
                        _status = {};
                      });
                    },
                  ),
                BouncyTap(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _search(_field.text),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                    child: Icon(Icons.arrow_forward_rounded, size: 18, color: c.onPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Live Source Filter Chips with status dots
        if (_status.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _SourceFilterChip(
                  label: 'All  ${_results.length}',
                  selected: _filter.isEmpty,
                  onSelected: () => setState(() => _filter = ''),
                ),
                const SizedBox(width: 8),
                for (final MapEntry(:key, value: s) in _status.entries) ...[
                  _SourceFilterChip(
                    label: switch (s['state']) {
                      'loading' => '${s['name']}  …',
                      'error' => '${s['name']}  !',
                      _ => '${s['name']}  ${s['count']}',
                    },
                    state: s['state'] as String,
                    selected: _filter == key,
                    onSelected: s['state'] == 'error'
                        ? () => toast('${Api.describe(s['error'])}\n${s['error']}')
                        : s['count'] > 0
                        ? () => setState(() => _filter = key)
                        : null,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),

        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    final shown = _shown;
    if (shown.isNotEmpty) {
      return GridView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), // clearance for bottom nav
        gridDelegate: posterGrid(),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final a = shown[i] as Map<String, dynamic>;
          return PosterCard(
            title: a['name'],
            image: a['image'],
            badge: _status[a['source']]?['name'] ?? a['source'],
            onTap: () => openAnime(context, a),
          );
        },
      );
    }
    if (_searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SakuraBlossom(size: 48, petalColor: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              'Searching across sources…',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 110),
      child: Column(
        children: [
          if (_allFailed)
            EmptyState(
              face: '(×﹏×)',
              error: true,
              title: "Couldn't reach any source",
              message: Api.describe(_failures.first['error']),
              action: FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                onPressed: () => _search(_query),
              ),
            )
          else if (_query.isNotEmpty)
            EmptyState(
              face: '(╥﹏╥)',
              title: 'Nothing found for “$_query”',
              message: 'Try another spelling or the Japanese title.',
            )
          else
            const EmptyState(
              face: '(◕‿◕✿)',
              title: 'What do you want to watch?',
            ),
        ],
      ),
    );
  }
}

class _SourceFilterChip extends StatelessWidget {
  const _SourceFilterChip({required this.label, required this.selected, this.state = 'ok', this.onSelected});

  final String label;
  final bool selected;
  final String state;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    final dotColor = switch (state) {
      'error' => c.error,
      'loading' => c.primary,
      _ => const Color(0xff7fdc9b), // soft green success
    };

    return BouncyTap(
      borderRadius: BorderRadius.circular(999),
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.primaryContainer : c.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.primary.withValues(alpha: 0.6) : c.outlineVariant.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'GoogleSansFlex',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12.5,
                color: selected ? c.onPrimaryContainer : c.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
