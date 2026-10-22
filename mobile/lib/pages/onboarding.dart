import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account.dart';

const _slides = [
  ('さがす · SEARCH', 'Every source, one search', 'Find a show once and watch it from any source.'),
  ('ライブラリ · LIBRARY', 'Your library, anywhere', 'Play your own folders, and the ones your PC shares.'),
  ('どうき · SYNC', 'Pick up where you left off', 'Sign in to sync history and settings across devices.'),
];

/// First launch: three slides previewing the app, ending on sign-in. Skippable throughout.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  int _index = 0;

  bool get _last => _index == _slides.length - 1;

  double get _page => _pages.hasClients && _pages.position.hasContentDimensions ? _pages.page ?? 0 : 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _loop.dispose();
    super.dispose();
  }

  void _finish() {
    Api.setSetting('onboarded', true);
    widget.onDone();
  }

  Future<void> _account({required bool create}) async {
    if (await signIn(context, create: create) && mounted) _finish();
  }

  void _go(int page) => _pages.animateToPage(page, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_index - 1);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(
                  children: [
                    SakuraBlossom(size: 26, petalColor: c.primary, centerColor: c.secondary),
                    const SizedBox(width: 10),
                    Text(
                      'Aikatsu',
                      style: TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w700, fontSize: 18, color: c.onSurface),
                    ),
                    const Spacer(),
                    TextButton(onPressed: _finish, child: const Text('Skip')),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Slide(index: i, active: i == _index, loop: _loop),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    AnimatedBuilder(animation: _pages, builder: (context, _) => _Dots(page: _page, count: _slides.length)),
                    const SizedBox(height: 20),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _last
                            ? Column(
                                key: const ValueKey('account'),
                                spacing: 10,
                                children: [
                                  PillButton(
                                    icon: Icons.person_add_rounded,
                                    label: 'Create account',
                                    filled: true,
                                    onTap: () => _account(create: true),
                                  ),
                                  PillButton(icon: Icons.login_rounded, label: 'Sign in', onTap: () => _account(create: false)),
                                ],
                              )
                            : PillButton(
                                key: const ValueKey('next'),
                                icon: Icons.arrow_forward_rounded,
                                label: 'Next',
                                filled: true,
                                onTap: () => _go(_index + 1),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.page, required this.count});

  final double page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Builder(
            builder: (context) {
              final near = 1 - (page - i).abs().clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8 + 18 * near,
                height: 8,
                decoration: BoxDecoration(color: Color.lerp(c.outlineVariant, c.primary, near), borderRadius: BorderRadius.circular(999)),
              );
            },
          ),
      ],
    );
  }
}

/// Rises into place, after `order` steps, each time its slide becomes the current one.
class _In extends StatelessWidget {
  const _In(this.active, this.order, this.child);

  final bool active;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = 60 * order, length = 260 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: length),
      curve: Interval(delay / length, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

/// A card previewing part of the app, built from its own widgets, over the slide's tag, title and line.
class _Slide extends StatelessWidget {
  const _Slide({required this.index, required this.active, required this.loop});

  final int index;
  final bool active;
  final Animation<double> loop;

  static const _shows = [('Sakura Days', 'Ep 12'), ('Star Drift', 'Ep 24'), ('Moonlit Café', 'Movie')];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final (tag, title, message) = _slides[index];
    final rows = switch (index) {
      0 => _search(context),
      1 => _library(context),
      _ => _sync(context),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: context.aikatsu.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [for (final (i, row) in rows.indexed) _In(active, i, row)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _In(
            active,
            rows.length,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SakuraBlossom(size: 16, petalColor: c.primary, centerColor: c.secondary),
                const SizedBox(width: 6),
                Text(tag, style: t.textTheme.labelMedium?.copyWith(color: c.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _In(
            active,
            rows.length + 1,
            Text(title, textAlign: TextAlign.center, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2)),
          ),
          const SizedBox(height: 8),
          _In(
            active,
            rows.length + 2,
            Text(message, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.4)),
          ),
        ],
      ),
    );
  }

  List<Widget> _search(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: c.primary),
            const SizedBox(width: 10),
            Text('sakura', style: t.textTheme.bodyLarge),
          ],
        ),
      ),
      Row(
        spacing: 8,
        children: [
          PillBadge(icon: Icons.public_rounded, label: '3 sources', color: c.primary),
          const PillBadge(icon: Icons.bolt_rounded, label: '18 results'),
        ],
      ),
      Row(
        spacing: 12,
        children: [
          for (final (title, badge) in _shows)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1 / 1.75,
                child: PosterCard(title: title, image: '', badge: badge),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _library(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    Widget row(String title, String where, Widget badge) => Row(
      children: [
        const SizedBox(width: 44, height: 62, child: Cover('', radius: 12)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(where, style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ),
        ),
        badge,
      ],
    );
    return [
      Row(
        children: [
          Icon(Icons.folder_rounded, size: 20, color: c.primary),
          const SizedBox(width: 8),
          Text('Your folders', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
      row('Sakura Days', 'On this phone', const PillBadge(label: '12 eps')),
      row(
        'Star Drift',
        'On Desktop',
        PillBadge(icon: Icons.computer_rounded, label: 'Online', color: c.onPrimaryContainer, backgroundColor: c.primaryContainer),
      ),
      row('Moonlit Café', 'On Desktop', const PillBadge(label: '1 movie')),
    ];
  }

  List<Widget> _sync(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    Widget device(IconData icon, String name) => PillBadge(icon: icon, label: name, backgroundColor: c.surfaceContainerHighest);
    return [
      Row(
        children: [
          const SizedBox(width: 56, height: 80, child: Cover('', radius: 14)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONTINUE WATCHING',
                  style: t.textTheme.labelSmall?.copyWith(color: c.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                Text('Sakura Days', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('Episode 7 of 12', style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: loop,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: 0.45 + 0.2 * Curves.easeInOutCubic.transform(1 - (2 * loop.value - 1).abs()),
                      minHeight: 5,
                      backgroundColor: c.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(context.aikatsu.sakuraGlow),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      Divider(height: 1, color: c.outlineVariant.withValues(alpha: 0.35)),
      Row(
        children: [
          device(Icons.phone_android_rounded, 'Phone'),
          Expanded(
            child: RotationTransition(turns: loop, child: Icon(Icons.sync_rounded, size: 20, color: c.primary)),
          ),
          device(Icons.computer_rounded, 'Desktop'),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: c.primary),
          const SizedBox(width: 6),
          Text('Synced just now', style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        ],
      ),
    ];
  }
}
