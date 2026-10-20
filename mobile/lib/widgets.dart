import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

final messenger = GlobalKey<ScaffoldMessengerState>();

/// Watchlist statuses in menu order (core db::WatchEntry).
const watchStatuses = [
  ('watching', 'Watching', Icons.play_circle_rounded),
  ('planning', 'Plan to watch', Icons.schedule_rounded),
  ('completed', 'Completed', Icons.check_circle_rounded),
  ('paused', 'On hold', Icons.pause_circle_rounded),
  ('dropped', 'Dropped', Icons.cancel_rounded),
];

void toast(String message) {
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Tactile bounce micro-animation for cards and buttons.
/// Scales down gently to 0.97 on press and springs back on release.
class BouncyTap extends StatefulWidget {
  const BouncyTap({super.key, required this.child, this.onTap, this.onLongPress, this.borderRadius});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.965,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius ?? BorderRadius.circular(16);
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: r,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Custom vector painter that renders the 5-petal Aikatsu sakura blossom motif.
class SakuraPainter extends CustomPainter {
  const SakuraPainter({required this.petalColor, required this.centerColor, this.innerDotColor});

  final Color petalColor;
  final Color centerColor;
  final Color? innerDotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final scale = radius / 128.0;

    final paintPetal = Paint()
      ..color = petalColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Petal path matching desktop icon.svg:
    // M128 128 C104 112 92 86 106 58 c4 -6 9 -8 13 -4 l9 11 9 -11 c4 -4 9 -2 13 4 c14 28 2 54 -22 70 z
    final petalPath = Path();
    petalPath.moveTo(128 * scale, 128 * scale);
    petalPath.cubicTo(104 * scale, 112 * scale, 92 * scale, 86 * scale, 106 * scale, 58 * scale);
    petalPath.cubicTo(110 * scale, 52 * scale, 115 * scale, 50 * scale, 119 * scale, 54 * scale);
    petalPath.lineTo(128 * scale, 65 * scale);
    petalPath.lineTo(137 * scale, 54 * scale);
    petalPath.cubicTo(141 * scale, 50 * scale, 146 * scale, 52 * scale, 150 * scale, 58 * scale);
    petalPath.cubicTo(164 * scale, 86 * scale, 152 * scale, 112 * scale, 128 * scale, 128 * scale);
    petalPath.close();

    // Draw 5 petals rotated by 72° around the center:
    for (var i = 0; i < 5; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 72 * math.pi / 180);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawPath(petalPath, paintPetal);
      canvas.restore();
    }

    // Flower center pistil
    final paintCenter = Paint()
      ..color = centerColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, 12 * scale, paintCenter);

    if (innerDotColor != null) {
      final paintDot = Paint()
        ..color = innerDotColor!
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(center, 5 * scale, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant SakuraPainter oldDelegate) =>
      oldDelegate.petalColor != petalColor || oldDelegate.centerColor != centerColor || oldDelegate.innerDotColor != innerDotColor;
}

/// A compact Sakura Blossom icon widget.
class SakuraBlossom extends StatelessWidget {
  const SakuraBlossom({super.key, this.size = 28, this.petalColor, this.centerColor, this.innerDotColor});

  final double size;
  final Color? petalColor;
  final Color? centerColor;
  final Color? innerDotColor;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: SakuraPainter(
        petalColor: petalColor ?? c.primary,
        centerColor: centerColor ?? c.tertiary,
        innerDotColor: innerDotColor ?? c.onPrimary,
      ),
    );
  }
}

/// Cover art with a warm placeholder and clean rounded corners.
class Cover extends StatelessWidget {
  const Cover(this.url, {super.key, this.radius = 18, this.fit = BoxFit.cover, this.showBorder = true});

  final String url;
  final double radius;
  final BoxFit fit;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(radius);

    final placeholder = DecoratedBox(
      decoration: BoxDecoration(color: c.surfaceContainerHigh, borderRadius: r),
      child: Center(
        child: Opacity(
          opacity: 0.25,
          child: SakuraBlossom(size: 36, petalColor: c.primary, centerColor: c.secondary),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        border: showBorder ? Border.all(color: c.outlineVariant.withValues(alpha: 0.45), width: 1) : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: url.isEmpty
            ? placeholder
            : Image.network(
                url,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
              ),
      ),
    );
  }
}

/// Blurred cover or banner behind a header, under its fade (`overlay`).
///
/// The blur is drawn once into a small image and shown as a plain picture: a
/// live blur filter inside a scrolling page leaks a line of bright art past its
/// clip while Impeller renders Android's stretch overscroll (Flutter 3.47).
class BlurredArt extends StatefulWidget {
  const BlurredArt(this.url, {super.key, required this.sigma, this.overlay});

  final String url;
  final double sigma;
  final Gradient? overlay;

  @override
  State<BlurredArt> createState() => _BlurredArtState();
}

class _BlurredArtState extends State<BlurredArt> {
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_loaded, onError: (_, _) {});
  ImageInfo? _source;
  ui.Image? _baked;
  (Size, double)? _bakedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BlurredArt old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    if (widget.url.isEmpty) {
      _stream?.removeListener(_listener);
      _stream = null;
      _forget();
      return;
    }
    final stream = NetworkImage(widget.url).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _loaded(ImageInfo info, bool _) {
    if (!mounted) return info.dispose();
    setState(() {
      _forget();
      _source = info;
    });
  }

  void _forget() {
    _source?.dispose();
    _source = null;
    _baked?.dispose();
    _baked = null;
    _bakedFor = null;
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _forget();
    super.dispose();
  }

  /// The box's final look (cover-fit, zoomed 1.2× so the blur's clamped edges
  /// stay outside, blurred) at up to 256 px wide, which the blur makes
  /// indistinguishable from full size.
  ui.Image _bake(ui.Image src, Size box) {
    final f = math.min(1.0, 256 / box.width);
    final srcSize = Size(src.width.toDouble(), src.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, srcSize, box * 1.2);
    final sigma = widget.sigma * 1.2;
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..scale(f)
      ..drawImageRect(
        src,
        Alignment.center.inscribe(fitted.source, Offset.zero & srcSize),
        Alignment.center.inscribe(fitted.destination, Offset.zero & box),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
      );
    return recorder.endRecording().toImageSync(math.max(1, (box.width * f).round()), math.max(1, (box.height * f).round()));
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest, src = _source?.image;
        if (src != null && box.isFinite && !box.isEmpty && _bakedFor != (box, widget.sigma)) {
          _baked?.dispose();
          _baked = _bake(src, box);
          _bakedFor = (box, widget.sigma);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (_baked != null) RawImage(image: _baked, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            if (overlay != null) DecoratedBox(decoration: BoxDecoration(gradient: overlay)),
          ],
        );
      },
    );
  }
}

/// Solid, tactile anime poster card with warm styling and bouncy tap animation.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    this.subtitle = '',
    this.badge = '',
    this.progress = -1,
    this.onTap,
    this.onLongPress,
  });

  final String title, image, subtitle, badge;
  final double progress;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final aikatsu = context.aikatsu;
    const r = BorderRadius.vertical(top: Radius.circular(18));

    return BouncyTap(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: r,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(image, radius: 18),
                // Subtle bottom gradient scrim to give badges and progress clear legibility
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                        ),
                      ),
                    ),
                  ),
                ),
                // Source / Category pill badge
                if (badge.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.surfaceContainerHighest.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5), width: 0.75),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      child: Text(
                        badge,
                        style: t.textTheme.labelSmall?.copyWith(color: c.onSurface, fontWeight: FontWeight.w600, fontSize: 10),
                      ),
                    ),
                  ),
                // Warm glowing progress bar
                if (progress >= 0)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(aikatsu.sakuraGlow),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Poster grid that adapts smoothly across phone & tablet widths.
SliverGridDelegate posterGrid() => const SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 165,
  childAspectRatio: 1 / 1.88,
  crossAxisSpacing: 12,
  mainAxisSpacing: 14,
);

/// Solid, tactile episode card with warm Japanese anime styling.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.num,
    required this.title,
    this.filler = false,
    this.recap = false,
    this.record,
    this.current = false,
    this.downloaded = false,
    this.onTap,
    this.onLongPress,
  });

  final int num;
  final String title;
  final bool filler, recap, current;

  /// On this phone: plays from the file instead of streaming.
  final bool downloaded;
  final Map<String, dynamic>? record;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final aikatsu = context.aikatsu;
    final completed = record?['completed'] == true;
    final duration = toInt(record?['duration']);
    final fraction = duration > 0 ? toInt(record?['playback_time']) / duration : 0.0;
    final r = BorderRadius.circular(18);

    // Border and surface: current episode has a warm sakura highlight
    final borderColor = current ? c.primary.withValues(alpha: 0.8) : c.outlineVariant.withValues(alpha: 0.45);
    final bgColor = current ? c.primaryContainer.withValues(alpha: 0.35) : c.surfaceContainer;

    return BouncyTap(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: r,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: r,
          border: Border.all(color: borderColor, width: current ? 1.5 : 1),
          boxShadow: current ? aikatsu.softShadow : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Episode avatar / status
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: completed ? c.primary : (current ? c.primaryContainer : c.surfaceContainerHighest),
                shape: BoxShape.circle,
                border: Border.all(
                  color: completed ? c.primary : (current ? c.primary : c.outlineVariant.withValues(alpha: 0.5)),
                  width: 1,
                ),
              ),
              child: Center(
                child: completed
                    ? Icon(Icons.check_rounded, size: 20, color: c.onPrimary)
                    : Text(
                        '$num',
                        style: TextStyle(
                          fontFamily: 'GoogleSansFlex',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: current ? c.primary : c.onSurface,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            // Title & metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title.isEmpty ? 'Episode $num' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            'UP NEXT',
                            style: t.textTheme.labelSmall?.copyWith(
                              color: c.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      if (filler || recap) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: c.tertiaryContainer, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            recap ? 'RECAP' : 'FILLER',
                            style: t.textTheme.labelSmall?.copyWith(color: c.onTertiaryContainer, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      if (downloaded) ...[const SizedBox(width: 6), Icon(Icons.download_done_rounded, size: 16, color: c.primary)],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    completed ? 'Watched' : (current ? 'Playing next' : 'Episode $num'),
                    style: t.textTheme.bodySmall?.copyWith(color: current ? c.primary : c.onSurfaceVariant, fontSize: 12),
                  ),
                  if (!completed && fraction > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: fraction.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: c.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(aikatsu.sakuraGlow),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!completed && fraction > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  '${(fraction * 100).round()}%',
                  style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Warm, themed empty state with an organic sakura backdrop and kaomoji face.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.face,
    required this.title,
    this.message = '',
    this.details = '',
    this.error = false,
    this.action,
  });

  final String face, title, message, details;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final accent = error ? c.error : c.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              face,
              textAlign: TextAlign.center,
              style: t.textTheme.displaySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.4),
                ),
              ),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: SelectableText(
                  details,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: c.outline),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Reusable cute tag badge for genres, ratings, status, etc.
class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.label, this.icon, this.color, this.backgroundColor});

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final fg = color ?? c.onSurface;
    final bg = backgroundColor ?? c.surfaceContainerHigh;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.outlineVariant.withValues(alpha: 0.5), width: 0.75),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: t.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Solid bottom sheet listing choices with a warm sakura check on the active choice.
Future<T?> pickFrom<T>(BuildContext context, String header, List<(String label, T value, bool checked)> items) {
  final c = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(header, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final (label, value, checked) in items)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(
                label,
                style: TextStyle(fontWeight: checked ? FontWeight.w600 : FontWeight.w400, color: checked ? c.primary : c.onSurface),
              ),
              trailing: checked
                  ? Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, size: 16, color: c.onPrimary),
                    )
                  : null,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  );
}

/// Yes/no dialog for destructive actions; false when dismissed.
Future<bool> confirm(BuildContext context, String title, String message, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// The GitHub mark, drawn from the Octicons path: Material Icons has no brand logos and this avoids an SVG package.
class GithubMark extends StatelessWidget {
  const GithubMark({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GithubMarkPainter(color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface),
  );
}

class _GithubMarkPainter extends CustomPainter {
  _GithubMarkPainter(this.color);

  final Color color;

  // Relative cubics (c1x, c1y, c2x, c2y, x, y) that follow the first absolute curve and run up to the closing arc.
  static const _curves = <List<double>>[
    [0, 3.54, 2.29, 6.53, 5.47, 7.59],
    [.4, .07, .55, -.17, .55, -.38],
    [0, -.19, -.01, -.82, -.01, -1.49],
    [-2.01, .37, -2.53, -.49, -2.69, -.94],
    [-.09, -.23, -.48, -.94, -.82, -1.13],
    [-.28, -.15, -.68, -.52, -.01, -.53],
    [.63, -.01, 1.08, .58, 1.23, .82],
    [.72, 1.21, 1.87, .87, 2.33, .66],
    [.07, -.52, .28, -.87, .51, -1.07],
    [-1.78, -.2, -3.64, -.89, -3.64, -3.95],
    [0, -.87, .31, -1.59, .82, -2.15],
    [-.08, -.2, -.36, -1.02, .08, -2.12],
    [0, 0, .67, -.21, 2.2, .82],
    [.64, -.18, 1.32, -.27, 2, -.27],
    [.68, 0, 1.36, .09, 2, .27],
    [1.53, -1.04, 2.2, -.82, 2.2, -.82],
    [.44, 1.1, .16, 1.92, .08, 2.12],
    [.51, .56, .82, 1.27, .82, 2.15],
    [0, 3.07, -1.87, 3.75, -3.65, 3.95],
    [.29, .25, .54, .73, .54, 1.48],
    [0, 1.07, -.01, 1.93, -.01, 2.2],
    [0, .21, .15, .46, .55, .38],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, 0)
      ..cubicTo(3.58, 0, 0, 3.58, 0, 8);
    for (final c in _curves) {
      path.relativeCubicTo(c[0], c[1], c[2], c[3], c[4], c[5]);
    }
    path
      ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(8.013), clockwise: false)
      ..relativeCubicTo(0, -4.42, -3.58, -8, -8, -8)
      ..close();
    canvas
      ..scale(size.width / 16, size.height / 16)
      ..drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GithubMarkPainter old) => old.color != color;
}
