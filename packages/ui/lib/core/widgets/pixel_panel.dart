import 'package:flutter/material.dart';

import '../theme/retro_theme.dart';
import 'pixel_border.dart';

/// A framed section of the screen: stepped corners, a hard offset shadow and
/// an optional inverse title bar (like a window title on an old GUI).
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(10),
    this.raised = true,
  });

  final Widget child;
  final String? title;

  /// Shown at the right end of the title bar (a badge, a count).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Whether the hard shadow is drawn.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final shape = PixelBorder(side: BorderSide(color: p.ink, width: 2));
    // In a bounded height (an Expanded slot) the panel fills it and the body
    // stretches; in a list it wraps its content.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: p.panel,
            shape: shape,
            shadows: raised
                ? [BoxShadow(color: p.shadow, offset: const Offset(3, 3))]
                : null,
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Container(
                    color: p.ink,
                    padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: context.pixel(color: p.screen),
                          ),
                        ),
                        if (trailing != null) trailing!,
                      ],
                    ),
                  ),
                Flexible(
                  fit: bounded ? FlexFit.tight : FlexFit.loose,
                  child: Padding(padding: padding, child: child),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A small inverse tag: "DEMO", "SOON", "REC".
class PixelBadge extends StatelessWidget {
  const PixelBadge(this.label, {super.key, this.inverse = false, this.color});

  final String label;

  /// Draw as an outline on the panel instead of solid; used on title bars,
  /// which are already ink-coloured.
  final bool inverse;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final fill = color ?? (inverse ? p.screen : p.ink);
    final text = inverse ? p.ink : p.screen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      color: fill,
      child: Text(label, style: context.pixel(color: text)),
    );
  }
}

/// Marks content that is made up, so no demo looks like real data.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO', this.onTitleBar = false});

  final String label;
  final bool onTitleBar;

  @override
  Widget build(BuildContext context) => PixelBadge(label, inverse: onTitleBar);
}
