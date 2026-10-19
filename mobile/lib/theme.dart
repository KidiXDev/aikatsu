import 'dart:math';

import 'package:flutter/material.dart';

// Warm Japanese Anime & Sakura blossom palette.
// Soft pastel tones, cozy layered surfaces, and luminous cherry-blossom accents.
const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xffff8eb3),
  onPrimary: Color(0xff57002b),
  primaryContainer: Color(0xff771741),
  onPrimaryContainer: Color(0xffffd9e4),
  inversePrimary: Color(0xffb22161),
  secondary: Color(0xfff2a2cd),
  onSecondary: Color(0xff520e3a),
  secondaryContainer: Color(0xff6e1e50),
  onSecondaryContainer: Color(0xffffd8eb),
  tertiary: Color(0xffaba5ff),
  onTertiary: Color(0xff23157e),
  tertiaryContainer: Color(0xff392b8d),
  onTertiaryContainer: Color(0xffe2e0ff),
  error: Color(0xffff7187),
  onError: Color(0xff540018),
  errorContainer: Color(0xff8f0b32),
  onErrorContainer: Color(0xffffb3be),
  surface: Color(0xff161113),
  surfaceDim: Color(0xff161113),
  surfaceBright: Color(0xff37292f),
  surfaceContainerLowest: Color(0xff0d090b),
  surfaceContainerLow: Color(0xff1d1619),
  surfaceContainer: Color(0xff251c20),
  surfaceContainerHigh: Color(0xff2e2227),
  surfaceContainerHighest: Color(0xff37292f),
  onSurface: Color(0xfffaedf0),
  onSurfaceVariant: Color(0xffcbb7bd),
  inverseSurface: Color(0xfffff7f8),
  onInverseSurface: Color(0xff5a4f52),
  outline: Color(0xff8c7980),
  outlineVariant: Color(0xff4c3b42),
  shadow: Color(0xff000000),
  scrim: Color(0xff000000),
);

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xffb22466),
  onPrimary: Color(0xfffff0f3),
  primaryContainer: Color(0xffffdbe5),
  onPrimaryContainer: Color(0xff450020),
  inversePrimary: Color(0xfffe5f9b),
  secondary: Color(0xff993b77),
  onSecondary: Color(0xfffff0f6),
  secondaryContainer: Color(0xffffd8eb),
  onSecondaryContainer: Color(0xff591341),
  tertiary: Color(0xff5750b9),
  onTertiary: Color(0xfff7f4ff),
  tertiaryContainer: Color(0xffe1deff),
  onTertiaryContainer: Color(0xff1c1274),
  error: Color(0xffb81944),
  onError: Color(0xfffff0f1),
  errorContainer: Color(0xffffdadf),
  onErrorContainer: Color(0xff410012),
  surface: Color(0xfffff7f8),
  surfaceDim: Color(0xffeae0e2),
  surfaceBright: Color(0xfffff7f8),
  surfaceContainerLowest: Color(0xffffffff),
  surfaceContainerLow: Color(0xfffaf0f2),
  surfaceContainer: Color(0xfff5e9ec),
  surfaceContainerHigh: Color(0xffefe2e6),
  surfaceContainerHighest: Color(0xffe9dce0),
  onSurface: Color(0xff362b2e),
  onSurfaceVariant: Color(0xff67565b),
  inverseSurface: Color(0xff161113),
  onInverseSurface: Color(0xffa8999d),
  outline: Color(0xff88747a),
  outlineVariant: Color(0xffdac5cb),
  shadow: Color(0xff000000),
  scrim: Color(0xff000000),
);

/// Custom styling tokens for the Warm Sakura & Japanese Anime theme.
class AikatsuTheme extends ThemeExtension<AikatsuTheme> {
  const AikatsuTheme({
    required this.sakuraGlow,
    required this.sakuraGradient,
    required this.heroGradient,
    required this.cardBorder,
    required this.cardShadow,
    required this.softShadow,
    required this.cardRadius,
    required this.pillRadius,
  });

  final Color sakuraGlow;
  final LinearGradient sakuraGradient;
  final LinearGradient heroGradient;
  final BorderSide cardBorder;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> softShadow;
  final BorderRadius cardRadius;
  final BorderRadius pillRadius;

  @override
  AikatsuTheme copyWith({
    Color? sakuraGlow,
    LinearGradient? sakuraGradient,
    LinearGradient? heroGradient,
    BorderSide? cardBorder,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? softShadow,
    BorderRadius? cardRadius,
    BorderRadius? pillRadius,
  }) {
    return AikatsuTheme(
      sakuraGlow: sakuraGlow ?? this.sakuraGlow,
      sakuraGradient: sakuraGradient ?? this.sakuraGradient,
      heroGradient: heroGradient ?? this.heroGradient,
      cardBorder: cardBorder ?? this.cardBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      softShadow: softShadow ?? this.softShadow,
      cardRadius: cardRadius ?? this.cardRadius,
      pillRadius: pillRadius ?? this.pillRadius,
    );
  }

  @override
  AikatsuTheme lerp(ThemeExtension<AikatsuTheme>? other, double t) {
    if (other is! AikatsuTheme) return this;
    return AikatsuTheme(
      sakuraGlow: Color.lerp(sakuraGlow, other.sakuraGlow, t) ?? sakuraGlow,
      sakuraGradient: LinearGradient.lerp(sakuraGradient, other.sakuraGradient, t) ?? sakuraGradient,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t) ?? heroGradient,
      cardBorder: BorderSide.lerp(cardBorder, other.cardBorder, t),
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? cardShadow,
      softShadow: BoxShadow.lerpList(softShadow, other.softShadow, t) ?? softShadow,
      cardRadius: BorderRadius.lerp(cardRadius, other.cardRadius, t) ?? cardRadius,
      pillRadius: BorderRadius.lerp(pillRadius, other.pillRadius, t) ?? pillRadius,
    );
  }
}

extension AikatsuThemeContext on BuildContext {
  AikatsuTheme get aikatsu => Theme.of(this).extension<AikatsuTheme>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark ? _dark : _light;

  final cardRadius = BorderRadius.circular(20);
  final pillRadius = BorderRadius.circular(999);
  final cardBorder = BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.6), width: 1);

  final cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
      blurRadius: 18,
      offset: const Offset(0, 6),
      spreadRadius: -2,
    ),
  ];

  final softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
      blurRadius: 10,
      offset: const Offset(0, 3),
    ),
  ];

  final customTheme = AikatsuTheme(
    sakuraGlow: isDark ? const Color(0xffff8eb3) : const Color(0xffb22466),
    sakuraGradient: LinearGradient(
      colors: isDark ? const [Color(0xffff8eb3), Color(0xfff2a2cd)] : const [Color(0xffb22466), Color(0xffd44a8b)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    heroGradient: LinearGradient(
      colors: [scheme.surface.withValues(alpha: 0.1), scheme.surface.withValues(alpha: 0.75), scheme.surface],
      stops: const [0.0, 0.6, 1.0],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    cardBorder: cardBorder,
    cardShadow: cardShadow,
    softShadow: softShadow,
    cardRadius: cardRadius,
    pillRadius: pillRadius,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'GoogleSansFlex',
    scaffoldBackgroundColor: scheme.surface,
    extensions: [customTheme],

    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: cardRadius, side: cardBorder),
      margin: EdgeInsets.zero,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 20, fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontFamily: 'GoogleSansFlex', fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),

    chipTheme: ChipThemeData(
      showCheckmark: false,
      shape: const StadiumBorder(),
      side: cardBorder,
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 0,
    ),

    // Same pill, colors and label as the chips, as one control split evenly across the row.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: const StadiumBorder(),
        side: cardBorder,
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurface,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        textStyle: const TextStyle(fontFamily: 'GoogleSansFlex', fontSize: 13, fontWeight: FontWeight.w500),
        visualDensity: VisualDensity.compact,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: cardBorder),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: cardBorder),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.65), fontSize: 14),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: cardBorder),
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: const BoxConstraints(minWidth: 560, maxWidth: 560),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      dragHandleColor: null,
      elevation: 8,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(fontFamily: 'GoogleSansFlex', color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: cardBorder),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.35), thickness: 1, space: 1),
  );
}

ThemeMode themeModeOf(String setting) => switch (setting) {
  'dark' => ThemeMode.dark,
  'light' => ThemeMode.light,
  _ => ThemeMode.system,
};

/// 340.2 MB, or 1.25 GB.
String formatBytes(num n) => n > 1073741824 ? '${(n / 1073741824).toStringAsFixed(2)} GB' : '${(n / 1048576).toStringAsFixed(1)} MB';

/// 5:09, or 1:05:09 past an hour.
String formatTime(num seconds) {
  final sec = seconds.isFinite ? seconds.floor().clamp(0, 1 << 31) : 0;
  final h = sec ~/ 3600, m = sec % 3600 ~/ 60, s = sec % 60;
  final mm = h > 0 ? '$m'.padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${'$s'.padLeft(2, '0')}';
}

/// When a scheduled episode airs, relative to [now]: "45m ago", "3h ago",
/// "21:30" later today, "Tomorrow 08:00".
String airingLabel(int airingAt, DateTime now) {
  final t = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
  final diff = t.difference(now);
  if (diff.isNegative) {
    final ago = -diff.inMinutes;
    return ago < 60 ? '${max(ago, 1)}m ago' : '${ago ~/ 60}h ago';
  }
  final hhmm = '${'${t.hour}'.padLeft(2, '0')}:${'${t.minute}'.padLeft(2, '0')}';
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return sameDay ? hhmm : 'Tomorrow $hhmm';
}
