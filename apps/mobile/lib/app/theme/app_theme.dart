import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The "Sơn Mài" themes (docs/DESIGN.md): rice paper + cinnabar ink in light,
/// black lacquer + gold leaf in dark.
///
/// Colour roles are spelled out instead of derived from a seed: `fromSeed` turns
/// the brand red into muddy pink surfaces, and the dark theme deliberately swaps
/// its primary to gold, which no seed would produce.
class AppTheme {
  const AppTheme._();

  /// Bundled UI font (see pubspec.yaml).
  static const String fontFamily = 'BeVietnamPro';

  /// Bundled brush-style face for board glyphs (帥, 將, 楚河 …).
  static const String pieceFontFamily = 'XiangqiPieces';

  static ThemeData get light => _build(_lightScheme, AppPalette.light);

  static ThemeData get dark => _build(_darkScheme, AppPalette.dark);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFB3261E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDAD5),
    onPrimaryContainer: Color(0xFF410002),
    secondary: Color(0xFF7C5A0E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF8E2B0),
    onSecondaryContainer: Color(0xFF271900),
    tertiary: Color(0xFF2F6B53),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFCDEBDD),
    onTertiaryContainer: Color(0xFF002115),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFBF7F1),
    onSurface: Color(0xFF221A15),
    onSurfaceVariant: Color(0xFF574840),
    surfaceDim: Color(0xFFE3D8CC),
    surfaceBright: Color(0xFFFFFBF6),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6EFE6),
    surfaceContainer: Color(0xFFF1E8DD),
    surfaceContainerHigh: Color(0xFFEBE1D4),
    surfaceContainerHighest: Color(0xFFE6D9CA),
    outline: Color(0xFF8A776B),
    outlineVariant: Color(0xFFDDCDBF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF382E28),
    onInverseSurface: Color(0xFFFBEEE6),
    inversePrimary: Color(0xFFFFB4A9),
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE9BE62),
    onPrimary: Color(0xFF3A2900),
    primaryContainer: Color(0xFF563F00),
    onPrimaryContainer: Color(0xFFFFDF9E),
    secondary: Color(0xFFFFB4A9),
    onSecondary: Color(0xFF690003),
    secondaryContainer: Color(0xFF7A1D16),
    onSecondaryContainer: Color(0xFFFFDAD5),
    tertiary: Color(0xFF96D4B6),
    onTertiary: Color(0xFF003826),
    tertiaryContainer: Color(0xFF12513B),
    onTertiaryContainer: Color(0xFFB1F1D1),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF15100D),
    onSurface: Color(0xFFEFE4DA),
    onSurfaceVariant: Color(0xFFD4C3B6),
    surfaceDim: Color(0xFF15100D),
    surfaceBright: Color(0xFF3D342F),
    surfaceContainerLowest: Color(0xFF100B09),
    surfaceContainerLow: Color(0xFF1E1714),
    surfaceContainer: Color(0xFF231B17),
    surfaceContainerHigh: Color(0xFF2E2521),
    surfaceContainerHighest: Color(0xFF39302A),
    outline: Color(0xFF9D8D81),
    outlineVariant: Color(0xFF4D4038),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEFE4DA),
    onInverseSurface: Color(0xFF382E28),
    inversePrimary: Color(0xFF7A5900),
    surfaceTint: Colors.transparent,
  );

  static ThemeData _build(ColorScheme scheme, AppPalette palette) {
    final isLight = scheme.brightness == Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
    );
    final text = _textTheme(base.textTheme);

    const radius14 = BorderRadius.all(Radius.circular(14));
    const buttonShape = RoundedRectangleBorder(borderRadius: radius14);
    const buttonSize = Size(64, 52);
    final buttonText = text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);

    return base.copyWith(
      textTheme: text,
      extensions: [palette],
      // Predictive back (on by default for apps targeting Android 16) gets the
      // shrinking-page preview; iOS keeps its swipe.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: 0,
        color: isLight ? scheme.surfaceContainerLowest : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          side: isLight ? BorderSide(color: scheme.outlineVariant) : BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape, textStyle: buttonText),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? scheme.surfaceContainerLowest : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius14,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium,
        backgroundColor: scheme.surfaceContainerLow,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
        titleTextStyle: text.bodyLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: radius14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
      ),
    );
  }

  /// Material 3 scale in Be Vietnam Pro, with firmer headings.
  static TextTheme _textTheme(TextTheme base) {
    TextStyle? tight(TextStyle? s, FontWeight w) =>
        s?.copyWith(fontWeight: w, letterSpacing: -0.2);
    return base.copyWith(
      displaySmall: tight(base.displaySmall, FontWeight.w700),
      headlineLarge: tight(base.headlineLarge, FontWeight.w700),
      headlineMedium: tight(base.headlineMedium, FontWeight.w700),
      headlineSmall: tight(base.headlineSmall, FontWeight.w700),
      titleLarge: tight(base.titleLarge, FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.bodySmall?.copyWith(height: 1.4),
    );
  }
}
