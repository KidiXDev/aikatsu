import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'pages/downloads.dart';
import 'pages/home.dart';
import 'pages/search.dart';
import 'pages/settings.dart';
import 'src/rust/frb_generated.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  final data = await getApplicationSupportDirectory();
  // App-specific external storage: no permission needed, removed with the app.
  final videos = await getExternalStorageDirectory() ?? data;
  Api.init(data.path, '${videos.path}/Anime');
  runApp(const AikatsuApp());
}

class AikatsuApp extends StatefulWidget {
  const AikatsuApp({super.key});

  @override
  State<AikatsuApp> createState() => _AikatsuAppState();
}

class _AikatsuAppState extends State<AikatsuApp> {
  var _theme = themeModeOf(Api.setting('theme'));
  late final StreamSubscription<(String, String)> _sub;

  @override
  void initState() {
    super.initState();
    _sub = Api.settingChanged.listen((s) {
      if (s.$1 == 'theme') setState(() => _theme = themeModeOf(s.$2));
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Aikatsu',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: messenger,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: _theme,
    home: const Shell(),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _go(int tab) {
    // Home and Downloads read local state that other tabs change.
    if (tab == 0) Api.historyRevision.value++;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: IndexedStack(
        index: _tab,
        children: [
          HomePage(onFindSomething: () => _go(1)),
          const SearchPage(),
          const DownloadsPage(),
          const SettingsPage(),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _go,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
        NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_rounded), label: 'Downloads'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
      ],
    ),
  );
}
