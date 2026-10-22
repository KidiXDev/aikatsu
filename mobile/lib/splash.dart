import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

const _tau = 2 * math.pi;

/// Takes over from Android's launch screen (res/drawable/splash_icon.xml: same blossom, size and spot), blooms,
/// then opens onto [child] through a growing circle. [child] builds and loads underneath from the first frame.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.child});

  final Widget child;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _done = true);
    })
    ..forward();
  bool _done = false;

  static const _bloom = Interval(0, 0.45, curve: Curves.easeInOutCubic);
  static const _burst = Interval(0.06, 0.6, curve: Curves.easeOutCubic);
  static const _word = Interval(0.22, 0.58, curve: Curves.easeOutCubic);
  static const _reveal = Interval(0.66, 1, curve: Curves.easeInOutCubic);
  static const _fade = Interval(0.66, 0.9, curve: Curves.easeInCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done && !MediaQuery.disableAnimationsOf(context))
          // The launch screen follows the system, not the app's theme setting; so does this until it opens.
          Theme(
            data: buildTheme(MediaQuery.platformBrightnessOf(context)),
            child: AbsorbPointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final c = Theme.of(context).colorScheme;
                  final t = _c.value, out = _fade.transform(t);
                  final word = _word.transform(t), pulse = math.sin(math.pi * math.min(t, 0.4) / 0.4);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipPath(
                        clipper: _Hole(_reveal.transform(t)),
                        child: ColoredBox(color: c.surface),
                      ),
                      Opacity(
                        opacity: 1 - out,
                        child: Transform.scale(
                          scale: 1 + 0.35 * out,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(painter: _Bloom(c, _bloom.transform(t), _burst.transform(t), pulse)),
                              Center(
                                child: Transform.translate(
                                  offset: Offset(0, 112 + 18 * (1 - word)),
                                  child: Opacity(
                                    opacity: word,
                                    child: Text(
                                      'Aikatsu',
                                      style: TextStyle(
                                        fontFamily: 'GoogleSansFlex',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 30,
                                        letterSpacing: 1 + 9 * (1 - word),
                                        color: c.onSurface,
                                        decoration: TextDecoration.none, // above any Material, so no default text style
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything but a centred circle that grows from nothing to the screen's far corners.
class _Hole extends CustomClipper<Path> {
  const _Hole(this.progress);

  final double progress;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: size.longestSide * 0.6 * progress));

  @override
  bool shouldReclip(_Hole old) => old.progress != progress;
}

final _petal = Path()
  ..moveTo(128, 128)
  ..cubicTo(104, 112, 92, 86, 106, 58)
  ..cubicTo(110, 52, 115, 50, 119, 54)
  ..lineTo(128, 65)
  ..lineTo(137, 54)
  ..cubicTo(141, 50, 146, 52, 150, 58)
  ..cubicTo(164, 86, 152, 112, 128, 128)
  ..close();

// The launcher icon's colours, as in splash_icon.xml.
const _petalColors = [Color(0xffffffff), Color(0xffffbde0), Color(0xffff6fa3)];
final _petalFill = Paint()..shader = ui.Gradient.radial(const Offset(128, 116), 64, _petalColors, const [0, 0.45, 1]);
final _pistil = Paint()..color = const Color(0xffa39eff);
final _dot = Paint()..color = const Color(0xfffff8f8);

/// The blossom turns one petal (so it lands looking as it started) with a pulse, a ring and petals scattering out.
class _Bloom extends CustomPainter {
  _Bloom(this.c, this.turn, this.burst, this.pulse);

  final ColorScheme c;
  final double turn, burst, pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (burst > 0 && burst < 1) {
      canvas.drawCircle(
        center,
        70 + 170 * burst,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 6 * (1 - burst)
          ..color = c.primary.withValues(alpha: 0.35 * (1 - burst)),
      );
      for (var i = 0; i < 10; i++) {
        final a = _tau * i / 10 + 0.3, reach = 60 + (i.isEven ? 150 : 110) * burst;
        canvas
          ..save()
          ..translate(center.dx + math.cos(a) * reach, center.dy + math.sin(a) * reach)
          ..rotate(a + math.pi / 2 + burst * (i.isEven ? 2 : -2))
          ..scale(0.22 * (1 - burst * 0.4))
          ..translate(-128, -92);
        canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: math.sin(math.pi * burst)));
        canvas.drawPath(_petal, _petalFill);
        canvas
          ..restore()
          ..restore();
      }
    }
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(0.75 * (1 + 0.1 * pulse))
      ..rotate(turn * _tau / 5)
      ..translate(-128, -128);
    for (var i = 0; i < 5; i++) {
      canvas
        ..save()
        ..translate(128, 128)
        ..rotate(i * _tau / 5)
        ..translate(-128, -128)
        ..drawPath(_petal, _petalFill)
        ..restore();
    }
    canvas
      ..drawCircle(const Offset(128, 128), 12, _pistil)
      ..drawCircle(const Offset(128, 128), 5, _dot)
      ..restore();
  }

  @override
  bool shouldRepaint(_Bloom old) => old.turn != turn || old.burst != burst || old.pulse != pulse || old.c != c;
}
