import 'dart:convert';

import 'package:aikatsu/pages/anime.dart';
import 'package:aikatsu/pages/search.dart';
import 'package:aikatsu/src/rust/frb_generated.dart';
import 'package:aikatsu/theme.dart';
import 'package:aikatsu/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = 'An Extremely Long Character Name That Wraps';

final _meta = {
  'anilist_id': 154587,
  'mal_id': 52991,
  'title_romaji': 'Sousou no Frieren',
  'title_english': "Frieren: Beyond Journey's End",
  'title_native': '葬送のフリーレン',
  'cover': '',
  'banner': '',
  'description': 'An elf mage outlives her party.',
  'genres': ['Adventure', 'Drama', 'Fantasy'],
  'score': 93,
  'mean_score': 92,
  'episodes': 28,
  'duration': 24,
  'year': 2023,
  'season': 'FALL',
  'season_year': 2023,
  'status': 'RELEASING',
  'format': 'TV',
  'source': 'MANGA',
  'start_date': 'Sep 29, 2023',
  'end_date': 'Mar 22, 2024',
  'popularity': 320000,
  'favourites': 45000,
  'synonyms': ['Frieren at the Funeral'],
  'studios': ['MADHOUSE'],
  'producers': ['TOHO animation', 'Shogakukan'],
  'next_airing': {'episode': 12, 'airing_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90000},
  'tags': [
    {'name': 'Elf', 'rank': 95},
    {'name': 'Travel', 'rank': 90},
  ],
  'characters': [
    {'id': 1, 'name': 'Frieren', 'native_name': 'フリーレン', 'image': '', 'role': 'MAIN', 'va_name': 'Atsumi Tanezaki', 'va_native_name': '種﨑敦美', 'va_image': '', 'va_language': 'Japanese'},
    {'id': 2, 'name': _long, 'native_name': 'とても長い名前', 'image': '', 'role': 'SUPPORTING', 'va_name': _long, 'va_native_name': '', 'va_image': '', 'va_language': ''},
    {'id': 3, 'name': 'Himmel', 'native_name': '', 'image': '', 'role': 'SUPPORTING', 'va_name': '', 'va_native_name': '', 'va_image': '', 'va_language': ''},
  ],
  'staff': [
    {'id': 20, 'name': 'Keiichirou Saitou', 'native_name': '斎藤圭一郎', 'image': '', 'role': 'Director'},
    {'id': 21, 'name': 'Yuusuke Yamamoto', 'native_name': '山本雄介', 'image': '', 'role': 'Director of Photography'},
  ],
  'relations': [
    {'anilist_id': 170068, 'mal_id': 0, 'media_type': 'ANIME', 'relation': 'SIDE_STORY', 'title_romaji': 'Sousou no Frieren: Marumaru no Mahou', 'title_english': "Frieren: Beyond Journey's End Mini Anime Special Side Story", 'cover': '', 'format': 'ONA', 'status': 'FINISHED', 'episodes': 10, 'year': 2023, 'score': 72},
    {'anilist_id': 118586, 'mal_id': 126287, 'media_type': 'MANGA', 'relation': 'ADAPTATION', 'title_romaji': 'Sousou no Frieren', 'title_english': '', 'cover': '', 'format': 'MANGA', 'status': 'RELEASING', 'episodes': 0, 'year': 2020, 'score': 89},
  ],
  'recommendations': [
    {'anilist_id': 161645, 'mal_id': 54492, 'title_romaji': 'Kusuriya no Hitorigoto', 'title_english': 'The Apothecary Diaries', 'cover': '', 'format': 'TV', 'episodes': 24, 'year': 2023, 'score': 88, 'rating': 850},
  ],
};

class _Backend extends Fake implements RustLibApi {
  @override
  Future<String> crateApiCall({required String method, required String args}) async => jsonEncode(switch (method) {
    'enrich' => _meta,
    'episodes' => [for (var i = 1; i <= 12; i++) {'num': i, 'url': 'ep$i', 'title': ''}],
    'episodeInfo' => [],
    _ => throw StateError('Unexpected call: $method'),
  });

  @override
  String crateApiGet({required String method, required String args}) => jsonEncode(switch (method) {
    'keys' => {'series': 'anilist:154587', 'episode': 'anilist:154587:1'},
    'seriesProgress' => [],
    'watchEntry' => null,
    'localEpisodes' => {},
    'sources' => [],
    _ => throw StateError('Unexpected get: $method'),
  });
}

void main() {
  // Real glyph widths: the test font draws every character as a full square.
  setUpAll(() => (FontLoader('GoogleSansFlex')..addFont(rootBundle.load('assets/fonts/GoogleSansFlex.ttf'))).load());
  setUp(() => RustLib.initMock(api: _Backend()));
  tearDown(RustLib.dispose);

  for (final size in [const Size(360, 720), const Size(412, 860), const Size(800, 600)]) {
    testWidgets('cast and details lay out at ${size.width.toInt()} wide', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const AnimePage(anime: {'name': 'Frieren', 'url': 'frieren', 'image': '', 'source': 'test/x'}),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ep 12 airs in 1d'), findsOneWidget);

      Future<void> reveal(String label) => tester.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);

      await tester.tap(find.text('Cast'));
      await tester.pumpAndSettle();
      await reveal('Atsumi Tanezaki');
      await reveal('Director');
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      // Taps can miss: scrolling to a widget parks it under the pinned app bar.
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Main  1', skipOffstage: false)).onSelected!(true);
      await tester.pumpAndSettle();
      expect(find.text('Himmel', skipOffstage: false), findsNothing);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await reveal('320,000 members');
      await reveal('The Apothecary Diaries');
      tester.widget<PosterCard>(find.widgetWithText(PosterCard, 'The Apothecary Diaries')).onTap!();
      expect(SearchPage.requested.value, 'Kusuriya no Hitorigoto');
      expect(tester.takeException(), isNull);
    });
  }
}
