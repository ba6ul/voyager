import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calls [onHide] when Esc is pressed anywhere inside [child], so the tray
/// window can be put away from the keyboard.
class HideOnEscape extends StatelessWidget {
  const HideOnEscape({super.key, required this.onHide, required this.child});

  final VoidCallback onHide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onHide},
      // Without a focused widget inside, key events never reach the bindings.
      child: Focus(autofocus: true, child: child),
    );
  }
}
