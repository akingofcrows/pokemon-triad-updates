import 'dart:math' show min;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Colors;

/// A face-down card, used for the opponent's remaining hand (their identity
/// isn't revealed — no "Reveal Hand" rule in this build).
class CardBackComponent extends PositionComponent {
  CardBackComponent({required Vector2 position, required Vector2 size, Image? cardBackImage})
    : _cardBackImage = cardBackImage,
      targetPosition = position.clone(),
      super(position: position, size: size, anchor: Anchor.center);

  final Image? _cardBackImage;

  Vector2 targetPosition;

  void moveTo(Vector2 worldPosition) => targetPosition = worldPosition;

  /// Updates this card-back's true pixel dimensions — called when the
  /// board's layout changes (e.g. a device rotation).
  void resize(double pixelSize) => size.setValues(pixelSize, pixelSize);

  @override
  void update(double dt) {
    super.update(dt);
    final t = min(1.0, dt * 14);
    position.setFrom(position + (targetPosition - position) * t);
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final radius = Radius.circular(size.x * 0.08);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    canvas.save();
    canvas.clipRRect(rrect);

    final backImg = _cardBackImage;
    if (backImg != null) {
      canvas.drawImageRect(
        backImg,
        Rect.fromLTWH(0, 0, backImg.width.toDouble(), backImg.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else {

    final center = Offset(size.x / 2, size.y / 2);
    final r = size.x * 0.32;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(center.dx - r, center.dy - r, r * 2, r));
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFE53935));
    canvas.restore();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(center.dx - r, center.dy, r * 2, r));
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFF5F5F5));
    canvas.restore();

    canvas.drawRect(
      Rect.fromLTWH(center.dx - r, center.dy - r * 0.08, r * 2, r * 0.16),
      Paint()..color = Colors.black,
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = Colors.black,
    );
    canvas.drawCircle(center, r * 0.28, Paint()..color = const Color(0xFFF5F5F5));
    canvas.drawCircle(
      center,
      r * 0.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = Colors.black,
    );
    }
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x26FFFFFF),
    );
  }
}
