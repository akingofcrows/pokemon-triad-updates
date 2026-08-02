import 'dart:ui';

import 'package:flame/components.dart';

import '../../models/board_position.dart';
import 'board_cell_component.dart';
import 'board_visuals.dart';

/// The 3×3 grid. When using [BoardComponent] the cells are rendered
/// procedurally; when using [BoardComponent.ttmmo] the grid is baked into
/// bg_black.png so cells are invisible hit-targets only.
class BoardComponent extends PositionComponent {
  BoardComponent({
    required Vector2 topLeft,
    required this.cellSize,
    required this.gap,
    required void Function(BoardPosition position) onCellTap,
    Image? cardPlacer,
    Image? cardPlacerSelect,
  }) : super(
         position: topLeft,
         size: Vector2.all(cellSize * 3 + gap * 2),
         anchor: Anchor.topLeft,
       ) {
    _buildCells(onCellTap, cellSize, gap, cardPlacer: cardPlacer, cardPlacerSelect: cardPlacerSelect);
  }

  /// Creates a board whose cells sit at TTMMO's exact pixel positions
  /// (the grid is already in bg_black.png, so the cells are invisible).
  factory BoardComponent.ttmmo({
    required void Function(BoardPosition position) onCellTap,
  }) {
    final cellSize = kBoardCell;
    final gap = kBoardCols[1] - kBoardCols[0] - kBoardCell;
    final board = BoardComponent._(
      topLeft: Vector2(kBoardCols.first, kBoardRows.first),
      cellSize: cellSize,
      gap: gap,
      onCellTap: onCellTap,
      cellVisible: false,
    );
    return board;
  }

  BoardComponent._({
    required Vector2 topLeft,
    required this.cellSize,
    required this.gap,
    required void Function(BoardPosition position) onCellTap,
    bool cellVisible = true,
  }) : super(
         position: topLeft,
         size: Vector2.all(cellSize * 3 + gap * 2),
         anchor: Anchor.topLeft,
       ) {
    _buildCells(onCellTap, cellSize, gap, visible: cellVisible);
  }

  void _buildCells(
    void Function(BoardPosition) onCellTap,
    double cellSize,
    double gap, {
    bool visible = true,
    Image? cardPlacer,
    Image? cardPlacerSelect,
  }) {
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final boardPosition = BoardPosition(row, col);
        final cell = BoardCellComponent(
          boardPosition: boardPosition,
          onCellTap: onCellTap,
          position: Vector2(col * (cellSize + gap), row * (cellSize + gap)),
          size: Vector2.all(cellSize),
          visible: visible,
          cardPlacer: cardPlacer,
          cardPlacerSelect: cardPlacerSelect,
        );
        _cells[boardPosition.index] = cell;
        add(cell);
      }
    }
  }

  double cellSize;
  double gap;
  final List<BoardCellComponent?> _cells = List.filled(9, null);

  BoardCellComponent cellAt(BoardPosition boardPosition) => _cells[boardPosition.index]!;

  void relayout(Vector2 newTopLeft, double newCellSize, double newGap) {
    cellSize = newCellSize;
    gap = newGap;
    position.setFrom(newTopLeft);
    size.setValues(newCellSize * 3 + newGap * 2, newCellSize * 3 + newGap * 2);

    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final boardPosition = BoardPosition(row, col);
        cellAt(boardPosition).relayout(
          Vector2(col * (newCellSize + newGap), row * (newCellSize + newGap)),
          newCellSize,
        );
      }
    }
  }

  /// World-space center point of a cell — where a [CardComponent] placed
  /// there (anchor = center) should sit.
  Vector2 worldCenterFor(BoardPosition boardPosition) {
    final cell = cellAt(boardPosition);
    return position + cell.position + Vector2.all(cellSize / 2);
  }

  Rect _worldRectFor(BoardPosition boardPosition) {
    final cell = cellAt(boardPosition);
    final topLeftWorld = position + cell.position;
    return Rect.fromLTWH(topLeftWorld.x, topLeftWorld.y, cellSize, cellSize);
  }

  BoardPosition? positionAtWorldPoint(Vector2 point) {
    for (var i = 0; i < 9; i++) {
      final boardPosition = BoardPosition.fromIndex(i);
      if (_worldRectFor(boardPosition).contains(Offset(point.x, point.y))) {
        return boardPosition;
      }
    }
    return null;
  }

  void setHighlights(Set<BoardPosition> highlighted) {
    for (var i = 0; i < 9; i++) {
      _cells[i]!.highlighted = highlighted.contains(BoardPosition.fromIndex(i));
    }
  }

  void clearHighlights() => setHighlights(const {});
}
