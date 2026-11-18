import '../core/widgets/pixel_icon.dart';

/// The workspaces of the app, in nav order (F1 to F4).
enum AppSection {
  home('HOME', 'HOME / DEVICE CONTROL', PixelGlyph.phone),
  flutter('FLUTTER', 'FLUTTER / APP DEVELOPMENT', PixelGlyph.flutter),
  files('FILES', 'FILE SHARING / TRANSFER', PixelGlyph.floppy),
  recording('RECORD', 'RECORDING / MONITOR', PixelGlyph.record);

  const AppSection(this.label, this.title, this.glyph);

  /// Short name on the nav key.
  final String label;

  /// Full name in the header.
  final String title;
  final PixelGlyph glyph;
}
