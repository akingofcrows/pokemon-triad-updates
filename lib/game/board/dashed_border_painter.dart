import 'dart:ui';

/// Strokes [rrect]'s outline as a dashed line. `dart:ui`'s [Canvas]/[Path] are
/// the same type for both Flame's [Component.render] and Flutter's
/// `CustomPainter.paint`, so this one function is shared by both.
void drawDashedRRect(
  Canvas canvas,
  RRect rrect,
  Paint paint, {
  double dash = 4,
  double gap = 3,
}) {
  final path = Path()..addRRect(rrect);
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = (distance + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance += dash + gap;
    }
  }
}
