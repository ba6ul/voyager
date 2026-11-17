import 'package:flutter/material.dart';

import '../theme/retro_theme.dart';
import 'pixel_border.dart';
import 'pixel_icon.dart';

/// Faint horizontal scanlines over the LCD. Drawn over the screen only, at
/// low alpha, so text stays crisp and readable.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScanlinePainter(context.retro.scanline),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.07)
      ..isAntiAlias = false;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.color != color;
}

/// A dithered (checkerboard) fill, for empty states and test patterns.
class DitherFill extends StatelessWidget {
  const DitherFill({super.key, this.cell = 2, this.opacity = 0.18});

  final double cell;
  final double opacity;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _DitherPainter(context.retro.ink, cell, opacity),
  );
}

class _DitherPainter extends CustomPainter {
  _DitherPainter(this.color, this.cell, this.opacity);
  final Color color;
  final double cell;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..isAntiAlias = false;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DitherPainter old) =>
      old.color != color || old.cell != cell || old.opacity != opacity;
}

/// A battery-style meter built from [segments] blocks, [value] in 0..1.
class SegmentBar extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.value,
    this.segments = 12,
    this.height = 12,
    this.color,
  });

  final double value;
  final int segments;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final lit = (value.clamp(0, 1) * segments).round();
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(border: Border.all(color: p.ink, width: 2)),
      child: Row(
        children: [
          for (var i = 0; i < segments; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: ColoredBox(
                color: i < lit
                    ? (color ?? p.ink)
                    : p.ink.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows [child] and hides it again, a few times a second.
class Blink extends StatefulWidget {
  const Blink({super.key, required this.child, this.period});

  final Widget child;
  final Duration? period;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period ?? const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) =>
        Opacity(opacity: _c.value < 0.5 ? 1 : 0, child: child),
    child: widget.child,
  );
}

/// A round-ish status LED made of pixels.
class Led extends StatelessWidget {
  const Led({super.key, required this.on, this.color, this.size = 10});

  final bool on;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? (color ?? p.ok) : Colors.transparent,
        border: Border.all(color: p.ink, width: 2),
      ),
    );
  }
}

/// A chunky icon + label key: used for the quick operations and the nav rail.
class PixelKey extends StatelessWidget {
  const PixelKey({
    super.key,
    required this.glyph,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.hint,
    this.compact = false,
    this.tooltip,
  });

  final PixelGlyph glyph;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// Small text under the label (a key name such as "F1").
  final String? hint;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    final fg = selected ? p.screen : p.ink;
    final key = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: p.ink.withValues(alpha: 0.12),
        child: Ink(
          decoration: ShapeDecoration(
            color: selected ? p.ink : p.panel,
            shape: PixelBorder(side: BorderSide(color: p.ink, width: 2)),
            shadows: selected
                ? null
                : [BoxShadow(color: p.shadow, offset: const Offset(2, 2))],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 6 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(glyph, size: compact ? 16 : 24, color: fg),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: context.pixel(color: fg),
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: context.pixel(color: selected ? p.screen : p.inkDim),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
  }
}

/// Feedback for a control whose function is not built yet, so a click never
/// looks like nothing happened.
void showNotWired(BuildContext context, String feature) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text('$feature: coming soon. Not wired to the phone yet.'),
      ),
    );
}

/// A selectable label: a mode switch, a filter, a source picker.
class PixelChip extends StatelessWidget {
  const PixelChip(
    this.label, {
    super.key,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? p.ink : Colors.transparent,
            border: Border.all(color: selected ? p.ink : p.inkDim, width: 2),
          ),
          child: Text(
            label,
            style: context.pixel(color: selected ? p.screen : p.ink),
          ),
        ),
      ),
    );
  }
}

/// A row of "label ........ value" for status read-outs.
class ReadoutRow extends StatelessWidget {
  const ReadoutRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.retro;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label, style: context.pixel(size: 8, color: p.inkDim)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.body(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
