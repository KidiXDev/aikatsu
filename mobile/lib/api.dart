import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'src/rust/api.dart' as rust;

/// The Rust core, the twin of desktop/qml/Api.qml: `call` runs an async core
/// method (throws the error message as a String), `get` a quick local one,
/// `pushed` streams events (search results per source, download progress, …).
abstract final class Api {
  static final _pushed = StreamController<(String, dynamic)>.broadcast();
  static final _settingChanged = StreamController<(String, String)>.broadcast();

  static Stream<(String kind, dynamic data)> get pushed => _pushed.stream;
  static Stream<(String key, String value)> get settingChanged => _settingChanged.stream;

  /// Bumped whenever watch history changes so pages can refresh.
  static final historyRevision = ValueNotifier(0);

  /// Bumped when downloaded episodes are deleted (finished ones arrive as `download` pushes).
  static final libraryRevision = ValueNotifier(0);

  /// Watch together (core party.rs); `ended` holds why a party closed under us.
  static final party = ValueNotifier<Map<String, dynamic>>(const {'active': false});

  static Future<void> init(String dataDir, String videosDir) {
    final ready = Completer<void>();
    rust.init(dataDir: dataDir, videosDir: videosDir).listen((e) {
      final data = jsonDecode(e.json);
      if (e.kind == 'ready') {
        ready.complete();
        return;
      }
      if (e.kind == 'startupError') {
        ready.completeError(data as String);
        return;
      }
      _pushed.add((e.kind, data));
      if (e.kind == 'sync' && data['history'] == true) historyRevision.value++;
      if (e.kind == 'party') party.value = Map<String, dynamic>.from(data);
    }, onError: (Object error, StackTrace stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    });
    return ready.future;
  }

  static Future<dynamic> call(String method, [Map<String, Object?> args = const {}]) async =>
      jsonDecode(await rust.call(method: method, args: jsonEncode(args)));

  static dynamic get(String method, [Map<String, Object?> args = const {}]) =>
      jsonDecode(rust.get_(method: method, args: jsonEncode(args)));

  /// Deletes downloaded episode files (only ones the core recorded).
  static void deleteDownloads(List<String> paths) {
    get('deleteDownloads', {'paths': paths});
    libraryRevision.value++;
  }

  /// The plugin's name for a source key; just the key's own part ("kyoko/x" → "x") when not installed.
  static String sourceName(Object? key) => key == 'local'
      ? 'Local files'
      : (get('sources') as List).firstWhere((s) => s['key'] == key, orElse: () => null)?['name'] ?? '${key ?? ''}'.split('/').last;

  static String setting(String key) => (get('settings') as Map)[key] as String? ?? '';

  static void setSetting(String key, Object value) {
    get('setSetting', {'key': key, 'value': '$value'});
    _settingChanged.add((key, '$value'));
  }

  /// One plain sentence for a backend/mpv error; show the raw text as details.
  static String describe(Object? err) {
    final offline = RegExp(r'^(.+?) is offline\b').firstMatch('${err ?? ''}');
    if (offline != null) return '${offline[1]} is offline. Open Aikatsu there and try again.';
    final unreachable = RegExp(r"^(.+?) can't be reached\b").firstMatch('${err ?? ''}');
    if (unreachable != null) return "Can't reach ${unreachable[1]}. Check its firewall and that you're on the same network.";
    final e = '${err ?? ''}'.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(e);
    if (has(r'video chain')) return "This video's format can't play on this device.";
    if (has(r'timed? ?out|timeout')) return 'The site took too long to answer.';
    if (has(r'dns|lookup address|connect|network|unreachable|connection|offline')) {
      return "Couldn't reach the site. Check your internet connection.";
    }
    if (has(r'403|forbidden|429|too many requests|cloudflare|blocked')) {
      return 'The site refused the request. Try again in a minute.';
    }
    if (has(r'no playable|no .*(server|stream|media|player)|404|not found|unrecognized|layout changed')) {
      return 'No working stream was found for this episode.';
    }
    return 'Something went wrong.';
  }
}

/// The first non-empty string, like JS `a || b || c` over the core's JSON.
String text(Iterable<Object?> values) => values.firstWhere((v) => v is String && v.isNotEmpty, orElse: () => '') as String;

/// A JSON number as an int (the core sends ints, mpv-derived values may be doubles).
int toInt(Object? v) => v is num ? v.toInt() : 0;

double toDouble(Object? v) => v is num ? v.toDouble() : 0;
