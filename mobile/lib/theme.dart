import 'package:flutter/material.dart';

// Material 3 tokens and the sakura palette (generated from #ff7aa8), same as desktop/qml/Theme.qml.
const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xffff89b0),
  onPrimary: Color(0xff610030),
  primaryContainer: Color(0xffff6fa3),
  onPrimaryContainer: Color(0xff4c0024),
  inversePrimary: Color(0xffb22161),
  secondary: Color(0xffff8ed2),
  onSecondary: Color(0xff63054a),
  secondaryContainer: Color(0xff7d2160),
  onSecondaryContainer: Color(0xffffbde0),
  tertiary: Color(0xffa39eff),
  onTertiary: Color(0xff201083),
  tertiaryContainer: Color(0xff958efb),
  onTertiaryContainer: Color(0xff14006d),
  error: Color(0xffff6e84),
  onError: Color(0xff490013),
  errorContainer: Color(0xffa70138),
  onErrorContainer: Color(0xffffb2b9),
  surface: Color(0xff130d0e),
  surfaceDim: Color(0xff130d0e),
  surfaceBright: Color(0xff36292c),
  surfaceContainerLowest: Color(0xff000000),
  surfaceContainerLow: Color(0xff191113),
  surfaceContainer: Color(0xff211719),
  surfaceContainerHigh: Color(0xff271d1f),
  surfaceContainerHighest: Color(0xff2f2226),
  onSurface: Color(0xfff6e0e4),
  onSurfaceVariant: Color(0xffbaa6aa),
  inverseSurface: Color(0xfffff8f8),
  onInverseSurface: Color(0xff5c5354),
  outline: Color(0xff827175),
  outlineVariant: Color(0xff534448),
  shadow: Color(0xff000000),
  scrim: Color(0xff000000),
);

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xffad1c5e),
  onPrimary: Color(0xffffeff1),
  primaryContainer: Color(0xffff6fa3),
  onPrimaryContainer: Color(0xff4c0024),
  inversePrimary: Color(0xfffe5f9b),
  secondary: Color(0xff963776),
  onSecondary: Color(0xffffeef4),
  secondaryContainer: Color(0xffffbfe1),
  onSecondaryContainer: Color(0xff7d2160),
  tertiary: Color(0xff544db6),
  onTertiary: Color(0xfff5f1ff),
  tertiaryContainer: Color(0xffaca7ff),
  onTertiaryContainer: Color(0xff281b89),
  error: Color(0xffb41340),
  onError: Color(0xffffefef),
  errorContainer: Color(0xfff74b6d),
  onErrorContainer: Color(0xff510017),
  surface: Color(0xfffff8f8),
  surfaceDim: Color(0xffead5d9),
  surfaceBright: Color(0xfffff8f8),
  surfaceContainerLowest: Color(0xffffffff),
  surfaceContainerLow: Color(0xfffff0f2),
  surfaceContainer: Color(0xfffce9ed),
  surfaceContainerHigh: Color(0xfff7e3e7),
  surfaceContainerHighest: Color(0xfff3dde1),
  onSurface: Color(0xff3c2f32),
  onSurfaceVariant: Color(0xff6b5b5f),
  inverseSurface: Color(0xff130d0e),
  onInverseSurface: Color(0xffa69a9c),
  outline: Color(0xff88767a),
  outlineVariant: Color(0xffc1adb1),
  shadow: Color(0xff000000),
  scrim: Color(0xff000000),
);

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _dark : _light;
  return ThemeData(colorScheme: scheme, fontFamily: 'GoogleSansFlex', scaffoldBackgroundColor: scheme.surface);
}

ThemeMode themeModeOf(String setting) => switch (setting) {
  'dark' => ThemeMode.dark,
  'light' => ThemeMode.light,
  _ => ThemeMode.system,
};

/// 5:09, or 1:05:09 past an hour.
String formatTime(num seconds) {
  final sec = seconds.isFinite ? seconds.floor().clamp(0, 1 << 31) : 0;
  final h = sec ~/ 3600, m = sec % 3600 ~/ 60, s = sec % 60;
  final mm = h > 0 ? '$m'.padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${'$s'.padLeft(2, '0')}';
}
