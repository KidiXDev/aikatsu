import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'download_notifications.dart';
import 'episode_notifications.dart';
import 'pages/anime.dart';
import 'pages/downloads.dart';
import 'pages/home.dart';
import 'pages/library.dart';
import 'pages/onboarding.dart';
import 'pages/search.dart';
import 'pages/settings.dart';
import 'splash.dart';
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
  try {
    await Api.init(data.path, '${videos.path}/Anime');
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(body: SafeArea(child: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text("Couldn't open app storage.\n\n$error"),
    ))))));
    return;
  }
  await DownloadNotifications.init();
  await EpisodeNotifications.init();
  runApp(const AikatsuApp());
}

class AikatsuApp extends StatefulWidget {
  const AikatsuApp({super.key});

  @override
  State<AikatsuApp> createState() => _AikatsuAppState();
}

class _AikatsuAppState extends State<AikatsuApp> {
  var _theme = themeModeOf(Api.setting('theme'));
  var _onboarded = Api.setting('onboarded') == 'true' || Api.get('syncStatus')['signedIn'] == true;
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
    navigatorObservers: [_DismissKeyboardObserver()],
    // Taps that no widget claims (empty space, text) drop the focus and with it the keyboard.
    builder: (context, child) => Splash(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: dismissKeyboard,
        child: child,
      ),
    ),
    home: AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _onboarded ? const Shell() : OnboardingPage(onDone: () => setState(() => _onboarded = true)),
    ),
  );
}

void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// A keyboard left open over the next screen, or over the page we just returned to, only gets in the way.
class _DismissKeyboardObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => dismissKeyboard();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => dismissKeyboard();
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _searchKey = GlobalKey<SearchPageState>();
  final _lifecycle = AppLifecycleListener(onResume: () => Api.call('syncNow').ignore());

  @override
  void initState() {
    super.initState();
    DownloadNotifications.tapped.addListener(_showDownloads);
    EpisodeNotifications.opened.addListener(_openNotified);
    SearchPage.requested.addListener(_searchRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      checkUpdatesOnOpen(context);
      _openNotified(); // the app was started from one
    });
  }

  @override
  void dispose() {
    DownloadNotifications.tapped.removeListener(_showDownloads);
    EpisodeNotifications.opened.removeListener(_openNotified);
    SearchPage.requested.removeListener(_searchRequested);
    _lifecycle.dispose();
    super.dispose();
  }

  void _go(int tab) {
    dismissKeyboard();
    if (tab == 0 || tab == 2) Api.historyRevision.value++;
    setState(() => _tab = tab);
  }

  /// A tapped download notification: back out of any anime page or player.
  void _showDownloads() {
    Navigator.popUntil(context, (route) => route.isFirst);
    _go(3);
  }

  /// A tapped episode notification: that show's page, over the current tab.
  void _openNotified() {
    final key = EpisodeNotifications.opened.value;
    if (key == null) return;
    EpisodeNotifications.opened.value = null;
    final w = (Api.get('watchlist') as List).where((w) => w['series_key'] == key).firstOrNull;
    if (w == null) return;
    Navigator.popUntil(context, (route) => route.isFirst);
    openAnime(context, watchedAnime(w));
  }

  void _searchRequested() {
    final q = SearchPage.requested.value;
    if (q == null) return;
    SearchPage.requested.value = null;
    Navigator.popUntil(context, (route) => route.isFirst);
    _go(1);
    _searchKey.currentState?.search(q);
  }

  @override
  Widget build(BuildContext context) {
    // Back from any other tab goes Home first instead of closing the app.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              HomePage(
                onSearch: (q) {
                  _go(1);
                  if (q.isNotEmpty) _searchKey.currentState?.search(q);
                },
              ),
              SearchPage(key: _searchKey),
              const LibraryPage(),
              const DownloadsPage(),
              const SettingsPage(),
            ],
          ),
        ),
        bottomNavigationBar: _WarmCapsuleNavBar(selectedIndex: _tab, onSelected: _go),
      ),
    );
  }
}

/// A bespoke warm Japanese anime navigation capsule.
/// Solid tactile pill with smooth animated expanding tabs on selection.
class _WarmCapsuleNavBar extends StatelessWidget {
  const _WarmCapsuleNavBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.search_rounded, activeIcon: Icons.search_rounded, label: 'Search'),
    (icon: Icons.video_library_outlined, activeIcon: Icons.video_library_rounded, label: 'Library'),
    (icon: Icons.download_outlined, activeIcon: Icons.download_rounded, label: 'Downloads'),
    (icon: Icons.tune_rounded, activeIcon: Icons.tune_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final aikatsu = context.aikatsu;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset + 4 : 14),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: c.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.55), width: 1),
          boxShadow: aikatsu.cardShadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < _items.length; i++)
              _NavItem(index: i, item: _items[i], selected: selectedIndex == i, onTap: () => onSelected(i)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.index, required this.item, required this.selected, required this.onTap});

  final int index;
  final ({IconData icon, IconData activeIcon, String label}) item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return BouncyTap(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 10, vertical: 8), // 5 items fit 360 dp
        decoration: BoxDecoration(color: selected ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.activeIcon : item.icon, size: 22, color: selected ? c.onPrimary : c.onSurfaceVariant),
            if (selected) ...[
              const SizedBox(width: 8),
              Text(
                item.label,
                style: TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w700, fontSize: 13, color: c.onPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
