import 'dart:async';

import 'package:aikatsu/playback_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stats refresh, tolerate unavailable properties, and stop after closing', (tester) async {
    int reads = 0;
    String codec = 'h264';
    await tester.pumpWidget(MaterialApp(home: PlaybackStats(readProperty: (name) async {
      reads++;
      if (name == 'video-format') return codec;
      if (name == 'video-params/w') return '1920';
      throw StateError('unavailable');
    })));
    await tester.pump();
    expect(find.textContaining('Video codec: h264'), findsOneWidget);
    expect(find.textContaining('Width: 1920'), findsOneWidget);
    expect(find.textContaining('Cache (s): —'), findsOneWidget);
    codec = 'hevc';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.textContaining('Video codec: hevc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final before = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
  });

  testWidgets('closing while a property read is pending is safe', (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(MaterialApp(home: PlaybackStats(readProperty: (_) => pending.future)));
    await tester.pumpWidget(const SizedBox());
    pending.complete('');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
