import 'package:flame/components.dart' show Vector2;

import '../cards/card_visuals.dart' show kHandRestScale;
import '../../models/deck.dart' show kDeckSize;

/// Computes battle-board geometry from the current canvas size, so the
/// board looks right in both landscape and portrait and adapts live if the
/// device rotates (see `TriadGame.onGameResize`). All coordinates are in
/// top-left-anchored screen space (world (0,0) == screen top-left).
class BoardLayout {
  const BoardLayout({
    required this.canvasSize,
    required this.cellSize,
    required this.gap,
    required this.handGap,
    required this.boardTopLeft,
    required this.headerHeight,
    required this.playerHandY,
    required this.opponentHandY,
  });

  final Vector2 canvasSize;
  final double cellSize;
  final double gap;
  final double handGap;
  final Vector2 boardTopLeft;
  final double headerHeight;
  final double playerHandY;
  final double opponentHandY;

  static const double headerGap = 0;
  static const double _marginX = 20;
  static const double _bottomMargin = 16;
  static const double _handToBoardGap = 10;
  static const double _gapRatio = 0.1;
  static const double _handGapRatio = 0.15;
  static const double _minCellSize = 40;
  static const double _maxCellSize = 130;
  static const double _headerHeight = 74;

  factory BoardLayout.compute(Vector2 canvasSize) {
    final width = canvasSize.x;
    final height = canvasSize.y;

    // Board width = 3C + 2*(gapRatio*C) = C*(3 + 2*gapRatio).
    final maxCellFromWidth = (width - _marginX * 2) / (3 + 2 * _gapRatio);

    // Vertical budget: header + headerGap, then (board-half + gap-to-hand +
    // hand-card-height) mirrored above and below the board, plus a bottom
    // margin. Solved for C — see docs/derivation in the class comment.
    final r = kHandRestScale;
    final perSideCoefficient = 1.5 + _gapRatio + r;
    final fixedVertical = headerGap + _handToBoardGap * 2 + _bottomMargin;
    final maxCellFromHeight = (height - fixedVertical) / (2 * perSideCoefficient);

    // A full 5-card hand must also fit across the width — on a narrow
    // portrait screen this is tighter than the board itself.
    // handWidth = C*(kDeckSize*r + (kDeckSize-1)*handGapRatio).
    final handWidthCoefficient = kDeckSize * r + (kDeckSize - 1) * _handGapRatio;
    final maxCellFromHandWidth = (width - _marginX * 2) / handWidthCoefficient;

    var rawCellSize = maxCellFromWidth < maxCellFromHeight ? maxCellFromWidth : maxCellFromHeight;
    if (maxCellFromHandWidth < rawCellSize) rawCellSize = maxCellFromHandWidth;
    final cellSize = rawCellSize.clamp(_minCellSize, _maxCellSize);
    final gap = cellSize * _gapRatio;
    final boardSide = cellSize * 3 + gap * 2;

    // Anchor the whole block (opponent hand, board, player hand) to the
    // bottom of the screen rather than the top: cellSize is often smaller
    // than the height budget allows (width or hand-width bound it tighter),
    // and a player's hand should sit near the bottom edge, not float in the
    // middle with dead space underneath it.
    final handHalf = cellSize * r / 2;
    final boardHalf = boardSide / 2;

    final playerHandY = height - _bottomMargin - handHalf;
    final boardCenterY = playerHandY - handHalf - _handToBoardGap - boardHalf;

    // Pin the opponent hand to the top of the Flame canvas — tuck cards
    // up so they just peek out from under the header bar.
    final opponentHandY = handHalf * 0.7 - 30;


    final boardTopLeft = Vector2((width - boardSide) / 2, boardCenterY - boardHalf);

    return BoardLayout(
      canvasSize: canvasSize,
      cellSize: cellSize,
      gap: gap,
      handGap: cellSize * _handGapRatio,
      boardTopLeft: boardTopLeft,
      headerHeight: _headerHeight,
      playerHandY: playerHandY,
      opponentHandY: opponentHandY,
    );
  }

  double get handCardSize => cellSize * kHandRestScale;
}
