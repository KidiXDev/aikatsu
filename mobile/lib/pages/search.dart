import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'anime.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  late final StreamSubscription<(String, dynamic)> _sub;
  String _query = '';
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
      if (kind != 'searchResult' || !_status.containsKey(data['source'])) return;
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

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.length < 2) return;
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
      await Api.call('search', {'query': q});
    } catch (_) {}
    if (!mounted || _query != q) return;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchBar(
            controller: _field,
            hintText: 'Search anime… (e.g. Frieren)',
            leading: const Icon(Icons.search_rounded),
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            trailing: [
              if (_searching) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: () => _search(_field.text)),
            ],
          ),
        ),
        if (_status.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('All  ${_results.length}'),
                  selected: _filter.isEmpty,
                  onSelected: (_) => setState(() => _filter = ''),
                ),
                for (final MapEntry(:key, value: s) in _status.entries)
                  ChoiceChip(
                    avatar: switch (s['state']) {
                      'error' => Icon(Icons.error_outline_rounded, color: t.colorScheme.error),
                      'loading' => const Icon(Icons.hourglass_top_rounded),
                      _ => null,
                    },
                    label: Text(switch (s['state']) {
                      'loading' => '${s['name']}  …',
                      'error' => '${s['name']}  !',
                      _ => '${s['name']}  ${s['count']}',
                    }),
                    selected: _filter == key,
                    onSelected: s['state'] == 'error'
                        ? (_) =>
                              toast('${Api.describe(s['error'])}\n${s['error']}') // the desktop shows it as a tooltip
                        : s['count'] > 0
                        ? (_) => setState(() => _filter = key)
                        : null,
                  ),
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
        padding: const EdgeInsets.all(16),
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
    if (_searching) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      child: _allFailed
          ? EmptyState(
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
          : _query.isNotEmpty
          ? EmptyState(
              face: '(╥﹏╥)',
              title: 'Nothing found for “$_query”',
              message: 'Try another spelling, or the Japanese title (e.g. Shingeki no Kyojin).',
            )
          : const EmptyState(
              face: '(◕‿◕✿)',
              title: 'What do you want to watch?',
              message: 'Type a title and search. Results show up as each site answers.',
            ),
    );
  }
}
