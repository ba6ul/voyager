import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_ui/features/devices/presentation/widgets/hide_on_escape.dart';

void main() {
  testWidgets('Esc hides the window', (tester) async {
    var hidden = 0;
    await tester.pumpWidget(MaterialApp(
      home: HideOnEscape(
          onHide: () => hidden++, child: const Scaffold(body: Text('x'))),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(hidden, 1);
  });

  testWidgets('other keys do not', (tester) async {
    var hidden = 0;
    await tester.pumpWidget(MaterialApp(
      home: HideOnEscape(
          onHide: () => hidden++, child: const Scaffold(body: Text('x'))),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);

    expect(hidden, 0);
  });

  testWidgets('Esc works while a button has focus', (tester) async {
    var hidden = 0;
    await tester.pumpWidget(MaterialApp(
      home: HideOnEscape(
        onHide: () => hidden++,
        child: Scaffold(
          body: FilledButton(
              autofocus: true, onPressed: () {}, child: const Text('Play')),
        ),
      ),
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(hidden, 1);
  });
}
