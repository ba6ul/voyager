import 'package:flutter/material.dart';

/// One colour scheme of the handheld: the LCD [screen] and [panel] surfaces
/// inside the plastic [shell], with [ink] as the text and line colour.
///
/// Every text colour ([ink], [inkDim], [warn], [danger]) must reach 4.5:1 on
/// both [screen] and [panel]; test/core/theme/retro_palette_test.dart checks
/// each palette. [ok] and [shellDark] are decoration only.
@immutable
class RetroPalette extends ThemeExtension<RetroPalette> {
  const RetroPalette({
    required this.name,
    required this.screen,
    required this.panel,
    required this.shell,
    required this.shellDark,
    required this.ink,
    required this.inkDim,
    required this.warn,
    required this.danger,
    required this.ok,
    required this.shadow,
    required this.scanline,
  });

  final String name;

  /// The LCD background.
  final Color screen;

  /// Raised surfaces on the LCD (panels, rows).
  final Color panel;

  /// The plastic around the screen (header, nav keys, status bar).
  final Color shell;
  final Color shellDark;

  /// Text, borders and fills of the "dark pixels".
  final Color ink;

  /// Secondary text.
  final Color inkDim;

  /// "Needs attention" text.
  final Color warn;
  final Color danger;

  /// An LED or bar that is on and healthy (decoration, not text).
  final Color ok;

  /// Hard offset shadow under panels.
  final Color shadow;

  /// Colour of the scanline overlay (drawn at low alpha).
  final Color scanline;

  /// Classic olive monochrome LCD.
  static const lcd = RetroPalette(
    name: 'LCD',
    screen: Color(0xFFC6CF9A),
    panel: Color(0xFFB5BF86),
    shell: Color(0xFFCFCABA),
    shellDark: Color(0xFF8E8A78),
    ink: Color(0xFF1B2612),
    inkDim: Color(0xFF38461F),
    warn: Color(0xFF6E2F00),
    danger: Color(0xFF7A0F0F),
    ok: Color(0xFF1F5A1A),
    shadow: Color(0x661B2612),
    scanline: Color(0xFF1B2612),
  );

  /// Green phosphor CRT.
  static const phosphor = RetroPalette(
    name: 'CRT GREEN',
    screen: Color(0xFF06120A),
    panel: Color(0xFF0C2214),
    shell: Color(0xFF1A2A20),
    shellDark: Color(0xFF0B140F),
    ink: Color(0xFF6BFF8A),
    inkDim: Color(0xFF3FB05B),
    warn: Color(0xFFFFC94D),
    danger: Color(0xFFFF7B7B),
    ok: Color(0xFF6BFF8A),
    shadow: Color(0xFF000000),
    scanline: Color(0xFF000000),
  );

  /// Amber monochrome terminal.
  static const amber = RetroPalette(
    name: 'AMBER',
    screen: Color(0xFF140B02),
    panel: Color(0xFF241504),
    shell: Color(0xFF2A2118),
    shellDark: Color(0xFF120D08),
    ink: Color(0xFFFFB63D),
    inkDim: Color(0xFFC48520),
    warn: Color(0xFFFF8A5C),
    danger: Color(0xFFFF7070),
    ok: Color(0xFFFFB63D),
    shadow: Color(0xFF000000),
    scanline: Color(0xFF000000),
  );

  static const all = [lcd, phosphor, amber];

  /// Whether the screen is darker than its text (phosphor and amber).
  bool get isDark => screen.computeLuminance() < ink.computeLuminance();

  @override
  RetroPalette copyWith({Color? screen, Color? ink}) => RetroPalette(
    name: name,
    screen: screen ?? this.screen,
    panel: panel,
    shell: shell,
    shellDark: shellDark,
    ink: ink ?? this.ink,
    inkDim: inkDim,
    warn: warn,
    danger: danger,
    ok: ok,
    shadow: shadow,
    scanline: scanline,
  );

  // Palettes are swapped, never blended.
  @override
  RetroPalette lerp(ThemeExtension<RetroPalette>? other, double t) =>
      other is RetroPalette && t >= 0.5 ? other : this;
}
