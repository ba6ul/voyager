import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/core/theme/retro_palette.dart';

double _contrast(Color a, Color b) {
  final hi = a.computeLuminance() > b.computeLuminance() ? a : b;
  final lo = identical(hi, a) ? b : a;
  return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
}

void main() {
  for (final palette in RetroPalette.all) {
    group('palette ${palette.name}', () {
      final texts = {
        'ink': palette.ink,
        'inkDim': palette.inkDim,
        'warn': palette.warn,
        'danger': palette.danger,
      };
      final surfaces = {'screen': palette.screen, 'panel': palette.panel};
      for (final text in texts.entries) {
        for (final surface in surfaces.entries) {
          test('${text.key} on ${surface.key} has at least 4.5:1 contrast', () {
            expect(
              _contrast(text.value, surface.value),
              greaterThanOrEqualTo(4.5),
            );
          });
        }
      }

      test('inverse text (screen on ink) is readable on filled buttons', () {
        expect(
          _contrast(palette.screen, palette.ink),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }

  test('the stock orange the app used to warn with would have failed', () {
    // Why the rule exists: Colors.orange was about 2:1 on a light surface.
    expect(_contrast(Colors.orange, const Color(0xFFFEF7FF)), lessThan(4.5));
  });
}
