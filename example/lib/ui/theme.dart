import 'package:flutter/material.dart';

/// Night-sky indigo: the app is about what happens while the phone sleeps.
const _seed = Color(0xFF3F51B5);

const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    extensions: [StatusColors.forBrightness(brightness)],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 2),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
  );
}

/// Good / warning colors in the same tonal system as the seed. Errors use [ColorScheme.error].
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.good,
    required this.goodContainer,
    required this.onGoodContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
  });

  factory StatusColors.forBrightness(Brightness brightness) {
    final good = ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32), brightness: brightness);
    final warn = ColorScheme.fromSeed(seedColor: const Color(0xFFF9A825), brightness: brightness);
    return StatusColors(
      good: good.primary,
      goodContainer: good.primaryContainer,
      onGoodContainer: good.onPrimaryContainer,
      warn: warn.primary,
      warnContainer: warn.primaryContainer,
      onWarnContainer: warn.onPrimaryContainer,
    );
  }

  static StatusColors of(BuildContext context) => Theme.of(context).extension<StatusColors>()!;

  final Color good;
  final Color goodContainer;
  final Color onGoodContainer;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;

  @override
  StatusColors copyWith({
    Color? good,
    Color? goodContainer,
    Color? onGoodContainer,
    Color? warn,
    Color? warnContainer,
    Color? onWarnContainer,
  }) =>
      StatusColors(
        good: good ?? this.good,
        goodContainer: goodContainer ?? this.goodContainer,
        onGoodContainer: onGoodContainer ?? this.onGoodContainer,
        warn: warn ?? this.warn,
        warnContainer: warnContainer ?? this.warnContainer,
        onWarnContainer: onWarnContainer ?? this.onWarnContainer,
      );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      good: Color.lerp(good, other.good, t)!,
      goodContainer: Color.lerp(goodContainer, other.goodContainer, t)!,
      onGoodContainer: Color.lerp(onGoodContainer, other.onGoodContainer, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnContainer: Color.lerp(warnContainer, other.warnContainer, t)!,
      onWarnContainer: Color.lerp(onWarnContainer, other.onWarnContainer, t)!,
    );
  }
}
