import 'package:flutter/material.dart';

import '../widgets/pixel_border.dart';
import 'retro_palette.dart';

/// Pixel font for labels, headings and buttons. Designed on an 8px grid, so
/// use sizes that are multiples of 8 (8, 16) where it matters.
const pixelFont = 'PressStart2P';

/// Terminal font for body text and numbers.
const bodyFont = 'VT323';

extension RetroContext on BuildContext {
  /// The active palette. Falls back to [RetroPalette.lcd] when there is no
  /// Voyager theme above (plain `MaterialApp` in widget tests).
  RetroPalette get retro =>
      Theme.of(this).extension<RetroPalette>() ?? RetroPalette.lcd;

  /// A label in the pixel font.
  TextStyle pixel({double size = 8, Color? color}) => TextStyle(
    fontFamily: pixelFont,
    fontSize: size,
    height: 1.4,
    color: color ?? retro.ink,
  );

  /// Body text in the terminal font.
  TextStyle body({double size = 20, Color? color}) => TextStyle(
    fontFamily: bodyFont,
    fontSize: size,
    height: 1.05,
    color: color ?? retro.ink,
  );
}

ThemeData buildRetroTheme(RetroPalette p) {
  final border = PixelBorder(side: BorderSide(color: p.ink, width: 2));
  final dimBorder = PixelBorder(side: BorderSide(color: p.inkDim, width: 2));
  final scheme = ColorScheme(
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    primary: p.ink,
    onPrimary: p.screen,
    secondary: p.inkDim,
    onSecondary: p.screen,
    error: p.danger,
    onError: p.screen,
    surface: p.screen,
    onSurface: p.ink,
  );
  const pixelButton = TextStyle(
    fontFamily: pixelFont,
    fontSize: 8,
    height: 1.4,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: bodyFont,
  );

  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.screen,
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme
        .apply(fontFamily: bodyFont, bodyColor: p.ink, displayColor: p.ink)
        .copyWith(
          titleMedium: TextStyle(
            fontFamily: bodyFont,
            fontSize: 24,
            height: 1,
            color: p.ink,
          ),
          bodyMedium: TextStyle(
            fontFamily: bodyFont,
            fontSize: 20,
            height: 1.05,
            color: p.ink,
          ),
          bodySmall: TextStyle(
            fontFamily: bodyFont,
            fontSize: 18,
            height: 1.05,
            color: p.inkDim,
          ),
        ),
    dividerTheme: DividerThemeData(color: p.inkDim, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.ink,
      circularTrackColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(border),
        textStyle: const WidgetStatePropertyAll(pixelButton),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.disabled) ||
                  s.contains(WidgetState.pressed)
              ? p.inkDim
              : p.ink,
        ),
        foregroundColor: WidgetStatePropertyAll(p.screen),
        overlayColor: WidgetStatePropertyAll(p.screen.withValues(alpha: 0.18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(border),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.disabled) ? p.inkDim : p.ink,
            width: 2,
          ),
        ),
        textStyle: const WidgetStatePropertyAll(pixelButton),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.pressed) ? p.ink : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? p.inkDim
              : s.contains(WidgetState.pressed)
              ? p.screen
              : p.ink,
        ),
        overlayColor: WidgetStatePropertyAll(p.ink.withValues(alpha: 0.12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(dimBorder),
        textStyle: const WidgetStatePropertyAll(pixelButton),
        foregroundColor: WidgetStatePropertyAll(p.ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
      hintStyle: TextStyle(fontFamily: bodyFont, fontSize: 20, color: p.inkDim),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.ink,
      selectionColor: p.ink.withValues(alpha: 0.35),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(
        fontFamily: bodyFont,
        fontSize: 20,
        color: p.screen,
      ),
      shape: PixelBorder(side: BorderSide(color: p.screen, width: 2)),
      width: 420,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: ShapeDecoration(
        color: p.ink,
        shape: PixelBorder(side: BorderSide(color: p.ink, width: 2)),
      ),
      textStyle: TextStyle(fontFamily: bodyFont, fontSize: 18, color: p.screen),
    ),
  );
}
