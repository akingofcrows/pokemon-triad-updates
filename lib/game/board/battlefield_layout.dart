import 'package:flame/components.dart' show Vector2;

import '../cards/card_visuals.dart' show kHandRestScale;

/// Computes a portrait-friendly battlefield geometry from the current Flame
/// canvas size. The header lives outside this canvas as a separate Flutter
/// widget now, so this canvas stacks (top to bottom): a top margin, the
/// "Opponent Hand" label, the opponent's hand, the 3×3 board, the "Your
/// Hand" label, and the player's hand. All coordinates are in
/// top-left-anchored world space.
class BattlefieldLayout {
  const BattlefieldLayout({
    required this.canvasSize,
    required this.opponentLabelY,
    required this.opponentHandY,
    required this.boardTopLeft,
    required this.boardCellSize,
    required this.boardGap,
    required this.playerLabelY,
    required this.playerHandY,
    required this.handCardSize,
  });

  final Vector2 canvasSize;
  final double opponentLabelY;
  final double opponentHandY;
  final Vector2 boardTopLeft;
  final double boardCellSize;
  final double boardGap;
  final double playerLabelY;
  final double playerHandY;
  final double handCardSize;

  static const double _marginX = 12;
  static const double _marginY = 8;
  static const double _handToBoardGap = 8;
  static const double _cellGapRatio = 0.08;
  static const double _handGap = 6.0;
  static const double _labelBandH = 20.0;
  static const double _labelGap = 4.0;

  factory BattlefieldLayout.compute(Vector2 size) {
    final w = size.x;
    final h = size.y;
    const r = kHandRestScale; // hand card size as a fraction of board cell size

    // Board cell size is bounded by three independent constraints (board
    // width, available height, and hand row width), and hand card size is
    // always derived from it (handCardSize = cellSize * r) rather than
    // computed separately — otherwise a narrow portrait width can force
    // small hand cards that then artificially cap the board even when
    // there's plenty of vertical room.
    final maxCellFromWidth = (w - _marginX * 2) / (3 + 2 * _cellGapRatio);

    final fixedVertical = _marginY * 2 + _handToBoardGap * 2 + 2 * (_labelBandH + _labelGap);
    final maxCellFromHeight = (h - fixedVertical) / (2 * r + 3 + 2 * _cellGapRatio);

    final maxCellFromHandWidth = (w - _marginX * 2 - _handGap * 4) / (5 * r);

    var cellSize = maxCellFromWidth < maxCellFromHeight ? maxCellFromWidth : maxCellFromHeight;
    if (maxCellFromHandWidth < cellSize) cellSize = maxCellFromHandWidth;
    cellSize = cellSize.clamp(60.0, 150.0);

    final handCardSize = cellSize * r;
    final boardGap = cellSize * _cellGapRatio;
    final boardSide = cellSize * 3 + boardGap * 2;

    // Pin "Opponent Hand" right below the top margin and the player's hand
    // right above the bottom margin, then center the board in whatever gap
    // is left between them — cellSize is often smaller than the height
    // budget allows (width or hand-width bound it tighter), and that slack
    // reads better as breathing room around the board than as dead space
    // stacked at one edge.
    final opponentLabelY = _marginY + _labelBandH / 2;
    final opponentHandY = _marginY + handCardSize / 2 - 8;

    final playerHandY = h - _marginY - handCardSize / 2;
    final playerLabelY = playerHandY - handCardSize / 2 - _labelGap - _labelBandH / 2;

    final boardTop = opponentHandY + handCardSize / 2 + _handToBoardGap;
    final boardBottom = playerLabelY - _labelBandH / 2 - _handToBoardGap;
    final boardCenterY = boardTop + (boardBottom - boardTop) / 2;

    final boardTopLeft = Vector2(
      (w - boardSide) / 2,
      boardCenterY - boardSide / 2,
    );

    return BattlefieldLayout(
      canvasSize: size,
      opponentLabelY: opponentLabelY,
      opponentHandY: opponentHandY,
      boardTopLeft: boardTopLeft,
      boardCellSize: cellSize,
      boardGap: boardGap,
      playerLabelY: playerLabelY,
      playerHandY: playerHandY,
      handCardSize: handCardSize,
    );
  }
}
