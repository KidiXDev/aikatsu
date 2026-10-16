import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:aikatsu/pages/settings.dart';
import 'package:aikatsu/src/rust/frb_generated.dart';
import 'package:aikatsu/theme.dart';
import 'package:aikatsu/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend extends Fake implements RustLibApi {
  String logs = '';
  bool fail = false;

  @override
  String crateApiGet({required String method, required String args}) {
    if ((method == 'logTail' || method == 'logReport') && fail) throw 'Permission denied reading the log';
    return jsonEncode(switch (method) {
      'settings' => {'theme': 'system', 'anime4k': 'off', 'debug': 'false', 'tmdbKey': '', 'disabledSources': ''},
      'sources' || 'anime4kModes' => [],
      'anime4kInstalled' => true,
      'downloadDir' => '/downloads',
      'version' => 'test',
      'logTail' => logs,
      'logReport' => 'Aikatsu test\nPlatform: android\n\n$logs\n',
      _ => throw StateError('Unexpected method: $method'),
    });
  }
}

void main() {
  late _Backend backend;
  setUp(() {
    backend = _Backend();
    RustLib.initMock(api: backend);
  });
  tearDown(RustLib.dispose);

  for (final size in [const Size(320, 700), const Size(800, 500)]) {
    testWidgets('logs stay wide and refresh empty, error, and populated states at $size', (tester) async {
      const channel = MethodChannel('io.github.kidixdev.aikatsu/logs');
      final exported = <String>[];
      Completer<bool>? pendingExport;
      bool failExport = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'exportLog');
        exported.add((call.arguments as Map)['contents'] as String);
        if (failExport) throw PlatformException(code: 'EXPORT_FAILED', message: 'Disk full');
        return pendingExport == null ? true : await pendingExport.future;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(size.width == 320 ? Brightness.light : Brightness.dark),
          scaffoldMessengerKey: messenger,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(size.width == 320 ? 1 : 2)),
            child: child!,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      );
      await tester.scrollUntilVisible(find.text('Logs'), 300, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();

      void checkWidth() {
        final content = find.descendant(of: find.byType(BottomSheet), matching: find.byType(Column)).first;
        expect(tester.getSize(content).width, min(size.width, 640));
        expect(tester.takeException(), isNull);
      }

      expect(find.text('No log entries yet'), findsOneWidget);
      checkWidth();
      backend.logs = 'short log entry';
      await tester.tap(find.byTooltip('Refresh logs'));
      await tester.pumpAndSettle();
      expect(find.text('short log entry'), findsOneWidget);
      checkWidth();

      backend.logs = 'full session log\nincluding earlier entries';
      await tester.tap(find.byTooltip('Export log'));
      await tester.pumpAndSettle();
      expect(exported.single, contains('full session log\nincluding earlier entries'));
      expect(find.text('Log saved. Attach the .txt file to your GitHub issue.'), findsOneWidget);

      pendingExport = Completer<bool>();
      await tester.tap(find.byTooltip('Export log'));
      await tester.pump();
      final exportButton = find.ancestor(of: find.byTooltip('Export log'), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(exportButton).onPressed, isNull);
      pendingExport.complete(false);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(exportButton).onPressed, isNotNull);
      pendingExport = null;

      failExport = true;
      await tester.tap(find.byTooltip('Export log'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't export log:"), findsOneWidget);
      expect(tester.widget<IconButton>(exportButton).onPressed, isNotNull);
      failExport = false;

      backend.fail = true;
      await tester.tap(find.byTooltip('Refresh logs'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load logs"), findsOneWidget);
      expect(find.text('Permission denied reading the log'), findsOneWidget);
      checkWidth();

      backend.fail = false;
      backend.logs = ' \n\t';
      await tester.tap(find.byTooltip('Refresh logs'));
      await tester.pumpAndSettle();
      expect(find.text('No log entries yet'), findsOneWidget);
      checkWidth();
      await tester.tap(find.byTooltip('Close logs'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  }
}
