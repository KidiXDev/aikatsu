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
  Completer<String>? pending;
  String? called;
  String autoCheck = 'true';
  List<dynamic>? reposOverride;

  @override
  Future<String> crateApiCall({required String method, required String args}) {
    called = method;
    return pending!.future;
  }

  @override
  String crateApiGet({required String method, required String args}) {
    if ((method == 'logTail' || method == 'logReport') && fail) throw 'Permission denied reading the log';
    return jsonEncode(switch (method) {
      'settings' => {'theme': 'system', 'anime4k': 'off', 'debug': 'false', 'tmdbKey': '', 'disabledSources': '', 'autoCheckPluginUpdates': autoCheck},
      'setSetting' => autoCheck = jsonDecode(args)['value'] as String,
      'anime4kModes' => [],
      'officialRepo' => 'https://github.com/KidiXDev/kyoko',
      'sources' => [
        {'key': 'someone/a', 'name': 'A source', 'repo': "Someone's repo", 'version': 1},
      ],
      'repos' => reposOverride ?? [
        {
          'url': 'https://github.com/someone/repo',
          'short': 'someone/repo',
          'official': false,
          'name': 'Someone\'s repo with a long name',
          'error': null,
          'plugins': [
            {'key': 'someone/a', 'name': 'A source', 'version': 1, 'compatible': true, 'loaded': true},
            {'key': 'someone/b', 'name': 'B source', 'version': 2, 'compatible': false, 'loaded': false},
          ],
        },
      ],
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

  for (final count in [0, 1, 2]) {
    testWidgets('startup check announces $count updates without downloading', (tester) async {
      final repos = jsonDecode(backend.crateApiGet(method: 'repos', args: '{}')) as List;
      repos[0]['updates'] = count;
      backend.reposOverride = repos;
      backend.pending = Completer<String>();
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => checkPluginUpdatesOnOpen(context),
          child: const Text('Open app'),
        ))),
      ));
      await tester.tap(find.text('Open app'));
      expect(backend.called, 'checkPluginUpdates');
      backend.pending!.complete(jsonEncode(repos));
      await tester.pumpAndSettle();
      if (count == 0) {
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.text('$count plugin update${count == 1 ? '' : 's'} available'), findsOneWidget);
        expect(backend.called, 'checkPluginUpdates', reason: 'announcing an update must not install it');
        await tester.tap(find.text(count == 1 ? 'View updates' : 'Later'));
        await tester.pumpAndSettle();
        if (count == 1) expect(find.byTooltip('Download 1 plugin update'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('startup check can be disabled from Settings', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SettingsPage()),
    ));
    final toggle = find.widgetWithText(SwitchListTile, 'Check for plugin updates on startup');
    await tester.scrollUntilVisible(toggle, 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(backend.autoCheck, 'false');
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    await checkPluginUpdatesOnOpen(tester.element(toggle));
    expect(backend.called, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('plugin actions show their completed list without a manual refresh', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      scaffoldMessengerKey: messenger,
      home: const Scaffold(body: SettingsPage()),
    ));
    await tester.scrollUntilVisible(find.text('1 source'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('1 source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 source'));
    await tester.pumpAndSettle();

    final updateButton = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Check for updates');
    backend.pending = Completer<String>();
    await tester.tap(find.text('Add Kyoko'));
    await tester.pump();
    expect(backend.called, 'addRepo');
    expect(tester.widget<IconButton>(updateButton).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Add')).onPressed, isNull);
    final repos = jsonDecode(backend.crateApiGet(method: 'repos', args: '{}')) as List;
    (repos[0]['plugins'] as List).add({'key': 'someone/c', 'name': 'New source', 'compatible': true, 'loaded': true});
    backend.pending!.complete(jsonEncode(repos));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, 'New source'), findsOneWidget);
    expect(tester.widget<IconButton>(updateButton).onPressed, isNotNull);

    backend.pending = Completer<String>();
    await tester.tap(updateButton);
    await tester.pump();
    expect(backend.called, 'checkPluginUpdates');
    repos[0]['updates'] = 1;
    backend.pending!.complete(jsonEncode(repos));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, 'New source'), findsOneWidget);
    expect(find.byTooltip('Download 1 plugin update'), findsOneWidget);
    expect(find.byTooltip('Add plugins'), findsOneWidget);

    messenger.currentState!.removeCurrentSnackBar();
    backend.pending = Completer<String>();
    await tester.tap(find.byTooltip('Download 1 plugin update'));
    await tester.pump();
    expect(backend.called, 'syncPlugins');
    repos[0]['updates'] = 0;
    repos[0]['plugins'][2]['name'] = 'Updated source';
    backend.pending!.complete(jsonEncode({'repos': repos, 'updated': true}));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, 'Updated source'), findsOneWidget);
    expect(find.text('Plugins updated'), findsOneWidget);
    expect(find.byTooltip('Download 1 plugin update'), findsNothing);

    messenger.currentState!.removeCurrentSnackBar();
    backend.pending = Completer<String>();
    await tester.tap(updateButton);
    await tester.pump();
    backend.pending!.complete(jsonEncode(repos));
    await tester.pumpAndSettle();
    expect(find.text('Plugins are up to date'), findsOneWidget);

    messenger.currentState!.removeCurrentSnackBar();
    backend.pending = Completer<String>();
    await tester.tap(updateButton);
    await tester.pump();
    repos[0]['error'] = 'Checksum mismatch';
    backend.pending!.complete(jsonEncode(repos));
    await tester.pumpAndSettle();
    expect(find.text("Some repos couldn't be checked"), findsOneWidget);
    expect(find.text('Checksum mismatch'), findsOneWidget);

    messenger.currentState!.removeCurrentSnackBar();
    backend.pending = Completer<String>();
    await tester.tap(updateButton);
    await tester.pump();
    backend.pending!.completeError('Offline');
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(tester.widget<IconButton>(updateButton).onPressed, isNotNull);

    messenger.currentState!.removeCurrentSnackBar();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    backend.pending = Completer<String>();
    await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
    await tester.pump();
    expect(backend.called, 'removeRepo');
    backend.pending!.complete('[]');
    await tester.pumpAndSettle();
    expect(find.text('No plugins'), findsOneWidget);
    expect(find.text('Updated source'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 700), const Size(800, 500)]) {
    testWidgets('plugins page opens from Settings and asks only for a GitHub link at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(size.width == 320 ? Brightness.light : Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(size.width == 320 ? 1 : 2)),
            child: child!,
          ),
          home: const Scaffold(body: SettingsPage()),
        ),
      );
      await tester.scrollUntilVisible(find.text('1 source'), 300, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('1 source'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 source'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Plugins'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'A source'), findsOneWidget);
      expect(find.text('Needs a newer Aikatsu'), findsOneWidget);
      expect(find.text('someone/repo  ·  Third-party'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('https://github.com/user/repo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
