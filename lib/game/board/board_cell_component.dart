import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection;

import '../../models/board_position.dart';

/// One empty-or-occupied cell of the 3×3 board. When the grid is baked into
/// bg_black.png (TTMMO layout) set [visible] to false so the cell only
/// handles hit-testing without drawing anything.
class BoardCellComponent extends PositionComponent with TapCallbacks {
  BoardCellComponent({
    required this.boardPosition,
    required this.onCellTap,
    required super.position,
    required super.size,
    this.visible = true,
    this.cardPlacer,
    this.cardPlacerSelect,
  }) : super(anchor: Anchor.topLeft);

  final BoardPosition boardPosition;
  final void Function(BoardPosition position) onCellTap;
  final bool visible;
  final Image? cardPlacer;
  final Image? cardPlacerSelect;

  bool highlighted = false;

  void relayout(Vector2 newPosition, double newCellSize) {
    position.setFrom(newPosition);
    size.setValues(newCellSize, newCellSize);
  }

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    if (highlighted) {
      // Draw highlighted card placer
      final select = cardPlacerSelect ?? cardPlacer;
      if (select != null) {
        canvas.drawImageRect(
          select,
          Rect.fromLTWH(0, 0, select.width.toDouble(), select.height.toDouble()),
          rect,
          Paint()..filterQuality = FilterQuality.none,
        );
      }
      return;
    }

    // Draw card placer image
    final placer = cardPlacer;
    if (placer != null) {
      canvas.drawImageRect(
        placer,
        Rect.fromLTWH(0, 0, placer.width.toDouble(), placer.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.none,
      );
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    onCellTap(boardPosition);
  }
}
