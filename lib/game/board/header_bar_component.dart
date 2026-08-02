import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextAlign, TextDirection;

import '../cards/card_visuals.dart' show flameImageKey;
import 'board_visuals.dart';

/// TTMMO-style header above the board: a colored name strip on each side
/// (`header_color.png`), a row of card-count pips (`score.png`) growing
/// toward the center from both sides, and a turn indicator underneath.
///
/// [relayout] lets the bar resize in place when the board's layout changes
/// (e.g. a device rotation between landscape/portrait).
class HeaderBarComponent extends PositionComponent {
  HeaderBarComponent({
    required this.images,
    required this.playerName,
    required this.opponentName,
    required this.handTotal,
    required Vector2 position,
    required double width,
    required double height,
  }) : super(position: position, size: Vector2(width, height), anchor: Anchor.topLeft) {
    _headerStrip = images.fromCache(flameImageKey(kHeaderColorAsset));
    _scorePips = images.fromCache(flameImageKey(kScoreAsset));
  }

  final Images images;
  final String playerName;
  final String opponentName;
  final int handTotal;

  Image? _headerStrip;
  Image? _scorePips;

  int playerScore = 0;
  int opponentScore = 0;
  bool isPlayerTurn = true;

  void updateScore(int player, int opponent) {
    playerScore = player;
    opponentScore = opponent;
  }

  void updateTurn(bool playerTurn) {
    isPlayerTurn = playerTurn;
  }

  void relayout(double width, double height) {
    size.setValues(width, height);
  }

  static const double _stripH = 26;
  static const double _stripMargin = 16;

  @override
  void render(Canvas canvas) {
    final stripW = (size.x * 0.32).clamp(90.0, 190.0);

    final strip = _headerStrip;
    if (strip != null) {
      canvas.drawImageRect(
        strip,
        headerStripSourceRect(kHeaderRowPlayer),
        Rect.fromLTWH(_stripMargin, 4, stripW, _stripH),
        Paint(),
      );
      canvas.drawImageRect(
        strip,
        headerStripSourceRect(kHeaderRowOpponent),
        Rect.fromLTWH(size.x - stripW - _stripMargin, 4, stripW, _stripH),
        Paint(),
      );
    }

    _drawText(canvas, playerName, _stripMargin + 12, 9, false, 14);
    _drawText(canvas, opponentName, size.x - _stripMargin - 12, 9, true, 14);

    final pips = _scorePips;
    if (pips != null) {
      const pipW = 22.0, pipH = 24.0, gap = 1.0;
      final centerX = size.x / 2;
      final pipY = _stripH + 8;

      // TTMMO draws only filled pips (no empty placeholders), staggered away
      // from the center — player pips fan left, opponent pips fan right.
      // See TTMMO src/utils/boardRenderer.ts for the original offsets.
      const playerOffX = [-4, -5, -6, -7, -8];
      const opponentOffX = [7, 6, 5, 4, 3];

      final totalW = handTotal * pipW + (handTotal - 1) * gap;
      // Draw all 5 pips per side, filled where earned, blank otherwise
      for (var i = 0; i < handTotal; i++) {
        final dx = centerX - totalW + i * (pipW + gap) + pipW / 2 + playerOffX[i];
        final col = i < playerScore ? kScorePipBlue : kScorePipEmpty;
        canvas.drawImageRect(
          pips,
          scorePipSourceRect(col),
          Rect.fromLTWH(dx - pipW / 2, pipY - pipH / 2 - 1, pipW, pipH),
          Paint(),
        );
      }
      for (var i = 0; i < handTotal; i++) {
        final dx = centerX + gap + i * (pipW + gap) + pipW / 2 + opponentOffX[i];
        final col = i < opponentScore ? kScorePipRed : kScorePipEmpty;
        canvas.drawImageRect(
          pips,
          scorePipSourceRect(col),
          Rect.fromLTWH(dx - pipW / 2, pipY - pipH / 2 - 1, pipW, pipH),
          Paint(),
        );
      }

      _drawText(
        canvas,
        isPlayerTurn ? 'Your turn' : "Opponent's turn",
        centerX,
        pipY + pipH + 4,
        null,
        13,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    bool? alignRight,
    double fontSize,
  ) {
    final align = alignRight == null
        ? TextAlign.center
        : (alignRight ? TextAlign.right : TextAlign.left);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: const Color(0xFFF8F8F8), fontSize: fontSize, fontFamily: 'PowerGreen'),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (alignRight) {
      true => x - painter.width,
      false => x,
      null => x - painter.width / 2,
    };
    painter.paint(canvas, Offset(dx, y));
  }
}
