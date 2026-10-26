import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';
import 'anime.dart';
import 'home.dart';

/// This week's AniList airings, a day at a time. Opened from Home's "Up next".
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.onSearch});

  /// Switches to Search; a non-empty query also runs it.
  final ValueChanged<String> onSearch;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Monday first: the app has no Flutter localizations, so MaterialLocalizations would always say Sunday.
  late final List<DateTime> _bounds = () {
    final now = DateTime.now();
    return [for (var i = 0; i <= 7; i++) DateTime(now.year, now.month, now.day - now.weekday + 1 + i)];
  }();
  late final int _today = DateTime.now().weekday - 1;
  late int _day = _today;
  List<Map<String, dynamic>>? _week; // meta::schedule
  bool _failed = false;
  bool _mine = false;
  final _watchlist = (Api.get('watchlist') as List).cast<Map<String, dynamic>>();
  late final _mineIds = {
    for (final w in _watchlist)
      if (toInt(w['anilist_id']) > 0 && (w['status'] == 'watching' || w['status'] == 'planning')) toInt(w['anilist_id']),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final week = await Api.call('schedule', {'from': _bounds.first.millisecondsSinceEpoch ~/ 1000, 'refresh': refresh});
      if (!mounted) return;
      setState(() {
        _week = (week as List).cast<Map<String, dynamic>>();
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<Map<String, dynamic>> _on(int day) {
    final from = _bounds[day].millisecondsSinceEpoch ~/ 1000, to = _bounds[day + 1].millisecondsSinceEpoch ~/ 1000;
    return [
      for (final a in _week ?? const <Map<String, dynamic>>[])
        if (toInt(a['airing_at']) >= from && toInt(a['airing_at']) < to && (!_mine || _mineIds.contains(toInt(a['anime']['anilist_id'])))) a,
    ];
  }

  String _hhmm(DateTime t) => '${'${t.hour}'.padLeft(2, '0')}:${'${t.minute}'.padLeft(2, '0')}';

  void _open(Map<String, dynamic> a) {
    final id = toInt(a['anime']['anilist_id']);
    final w = _watchlist.where((w) => toInt(w['anilist_id']) == id).firstOrNull;
    if (w != null) return openAnime(context, watchedAnime(w));
    final at = DateTime.fromMillisecondsSinceEpoch(toInt(a['airing_at']) * 1000);
    final when = '${_weekdays[at.weekday - 1]} ${_hhmm(at)}';
    showDiscoverInfo(
      context,
      (
        meta: a['anime'],
        badge: '',
        subtitle: '',
        note: 'Episode ${a['episode']} · ${at.isBefore(DateTime.now()) ? 'aired' : 'airs'} $when',
      ),
      (query) {
        Navigator.pop(context);
        widget.onSearch(query);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _on(_day);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilterChip(
              avatar: const Icon(Icons.bookmark_rounded, size: 16),
              label: const Text('My shows'),
              selected: _mine,
              showCheckmark: false,
              onSelected: (v) => setState(() => _mine = v),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              spacing: 8,
              children: [
                for (var i = 0; i < 7; i++)
                  ChoiceChip(
                    avatar: i == _today ? const Icon(Icons.today_rounded, size: 18) : null,
                    label: Text('${_weekdays[i]} ${_bounds[i].day}${_week == null ? '' : '  ${_on(i).length}'}'),
                    selected: i == _day,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _day = i),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: shown.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: _week == null && !_failed
                              ? const Center(child: CircularProgressIndicator())
                              : _failed
                              ? const EmptyState(face: '(×﹏×)', title: "Couldn't load the schedule", message: 'Pull down to try again.')
                              : const EmptyState(face: '(・・ )?', title: 'Nothing airs this day'),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      gridDelegate: posterGrid(),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final a = shown[i];
                        final m = a['anime'] as Map<String, dynamic>;
                        return PosterCard(
                          title: text([m['title_english'], m['title_romaji']]),
                          image: text([m['cover']]),
                          badge: 'Ep ${a['episode']}',
                          subtitle: _hhmm(DateTime.fromMillisecondsSinceEpoch(toInt(a['airing_at']) * 1000)),
                          onTap: () => _open(a),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
