import 'package:flutter/foundation.dart';

import 'retro_palette.dart';

/// Which palette is active and whether the scanline overlay is drawn.
/// Held for the session only; not persisted yet.
class ThemeController extends ChangeNotifier {
  int _index = 0;
  bool _scanlines = true;

  RetroPalette get palette => RetroPalette.all[_index];
  bool get scanlines => _scanlines;

  void nextPalette() {
    _index = (_index + 1) % RetroPalette.all.length;
    notifyListeners();
  }

  void toggleScanlines() {
    _scanlines = !_scanlines;
    notifyListeners();
  }
}
