import 'dart:async';
import 'dart:convert';

import 'package:aikatsu/api.dart';
import 'package:aikatsu/src/rust/api.dart';
import 'package:aikatsu/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend extends Fake implements RustLibApi {
  final events = StreamController<Event>();

  @override
  Stream<Event> crateApiInit({required String dataDir, required String videosDir}) => events.stream;

  void emit(String kind, Object? data) => events.add(Event(kind: kind, json: jsonEncode(data)));
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
}
