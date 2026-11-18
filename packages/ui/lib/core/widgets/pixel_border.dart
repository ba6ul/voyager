import 'package:flutter/material.dart';

/// A rectangle whose corners are cut in two pixel steps instead of rounded:
/// the outline of every panel and button in the app.
class PixelBorder extends OutlinedBorder {
  const PixelBorder({super.side = BorderSide.none, this.step = 2});

  /// Size of one stair step of a corner, in logical pixels.
  final double step;

  Path _path(Rect r) {
    final s = step;
    final s2 = step * 2;
    return Path()
      ..moveTo(r.left, r.top + s2)
      ..lineTo(r.left + s, r.top + s2)
      ..lineTo(r.left + s, r.top + s)
      ..lineTo(r.left + s2, r.top + s)
      ..lineTo(r.left + s2, r.top)
      ..lineTo(r.right - s2, r.top)
      ..lineTo(r.right - s2, r.top + s)
      ..lineTo(r.right - s, r.top + s)
      ..lineTo(r.right - s, r.top + s2)
      ..lineTo(r.right, r.top + s2)
      ..lineTo(r.right, r.bottom - s2)
      ..lineTo(r.right - s, r.bottom - s2)
      ..lineTo(r.right - s, r.bottom - s)
      ..lineTo(r.right - s2, r.bottom - s)
      ..lineTo(r.right - s2, r.bottom)
      ..lineTo(r.left + s2, r.bottom)
      ..lineTo(r.left + s2, r.bottom - s)
      ..lineTo(r.left + s, r.bottom - s)
      ..lineTo(r.left + s, r.bottom - s2)
      ..lineTo(r.left, r.bottom - s2)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = false
      ..color = side.color;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), paint);
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      PixelBorder(side: side ?? this.side, step: step);

  @override
  ShapeBorder scale(double t) =>
      PixelBorder(side: side.scale(t), step: step * t);
}
