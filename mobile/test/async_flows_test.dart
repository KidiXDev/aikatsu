import 'dart:async';
import 'dart:convert';

import 'package:aikatsu/api.dart';
import 'package:aikatsu/download_notifications.dart';
import 'package:aikatsu/pages/search.dart';
import 'package:aikatsu/src/rust/api.dart';
import 'package:aikatsu/theme.dart';
import 'package:aikatsu/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class _Backend extends Fake implements RustLibApi {
  final events = StreamController<Event>();
  final searches = <(int, Completer<String>)>[];

  @override
  Stream<Event> crateApiInit({required String dataDir, required String videosDir}) => events.stream;

  @override
  String crateApiGet({required String method, required String args}) => jsonEncode(switch (method) {
    'settings' => {'disabledSources': ''},
    'sources' => [{'key': 'test/source', 'name': 'Test source'}],
    _ => throw StateError(method),
  });

  @override
  Future<String> crateApiCall({required String method, required String args}) {
    if (method != 'search') throw StateError(method);
    final result = Completer<String>();
    searches.add((jsonDecode(args)['requestId'] as int, result));
    return result.future;
  }

  void emit(String kind, Object? data) => events.add(Event(kind: kind, json: jsonEncode(data)));

  Future<void> ready() async {
    final starting = Api.init('/data', '/videos');
    emit('ready', null);
    await starting;
  }

  void result(int request, String name) => emit('searchResult', {
    'requestId': request,
    'source': 'test/source',
    'name': 'Test source',
    'items': [{'source': 'test/source', 'name': name, 'image': '', 'url': 'https://test/$name'}],
  });
}

void main() {
  late _Backend backend;
  setUp(() {
    backend = _Backend();
    RustLib.initMock(api: backend);
  });
  tearDown(() async {
    await backend.events.close();
    RustLib.dispose();
  });

  test('storage startup waits for ready and propagates errors', () async {
    final starting = Api.init('/data', '/videos');
    final failure = expectLater(starting, throwsA('storage unavailable'));
    backend.emit('startupError', 'storage unavailable');
    await failure;
  });

  testWidgets('overlapping searches ignore old results and completion, including repeated queries', (tester) async {
    await backend.ready();
    final key = GlobalKey<SearchPageState>();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SearchPage(key: key))));
    key.currentState!.search('Naruto');
    key.currentState!.search('Bleach');
    key.currentState!.search('Naruto');
    final first = backend.searches[0], second = backend.searches[1], current = backend.searches[2];
    backend.result(first.$1, 'Old Naruto');
    backend.result(second.$1, 'Bleach');
    first.$2.complete('{}');
    second.$2.complete('{}');
    await tester.pump();
    expect(find.text('Old Naruto'), findsNothing);
    expect(find.text('Bleach'), findsNothing);
    expect(find.text('Searching across sources…'), findsOneWidget);
    backend.result(current.$1, 'Current Naruto');
    await tester.pump();
    current.$2.complete('{}');
    await tester.pumpAndSettle();
    expect(find.text('Current Naruto'), findsOneWidget);
    backend.result(first.$1, 'Very late Naruto');
    await tester.pump();
    expect(find.text('Very late Naruto'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('notification service skips cancelled jobs and serializes start and stop', (tester) async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final calls = <String>[];
    final permission = Completer<bool>();
    final start = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'requestNotificationsPermission') return permission.future;
      if (call.method == 'startForegroundService') {
        await start.future;
        return null;
      }
      if (call.method == 'initialize') return true;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await backend.ready();
    await DownloadNotifications.init();
    void job(String state) => backend.emit('download', {'id': 1, 'state': state, 'title': 'Test', 'episode': 1});
    job('queued');
    await tester.pump();
    expect(calls, contains('requestNotificationsPermission'));
    job('cancelled');
    await tester.pump();
    permission.complete(true);
    await tester.pump();
    expect(calls, isNot(contains('startForegroundService')));
    job('queued');
    await tester.pump();
    expect(calls.where((c) => c == 'startForegroundService'), hasLength(1));
    job('cancelled');
    await tester.pump();
    expect(calls, isNot(contains('stopForegroundService')), reason: 'start must finish before stopping');
    start.complete();
    await tester.pump();
    expect(calls.last, 'stopForegroundService');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));
}
