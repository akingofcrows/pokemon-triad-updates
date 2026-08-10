import 'package:flutter/material.dart';

import '../models/deck.dart' show kDeckSize;
import 'home_style_panel.dart';

/// Two-tone player/opponent header bar using header_color.png stripes.
/// header_color.png: 226×396, 12 color stripes stacked vertically
/// (grey, orange, brown, red=3, blue=4, green=5, yellow, purple, black, gold, silver)
class BattleHeaderBar extends StatefulWidget {
  const BattleHeaderBar({
    super.key,
    required this.playerName,
    required this.opponentName,
    required this.playerScore,
    required this.opponentScore,
    required this.isPlayerTurn,
  });

  final String playerName;
  final String opponentName;
  final int playerScore;
  final int opponentScore;
  final bool isPlayerTurn;

  @override
  State<BattleHeaderBar> createState() => _BattleHeaderBarState();
}

class _BattleHeaderBarState extends State<BattleHeaderBar> {
  static const double _barHeight = 36;
  static const int _colorCount = 11;
  static const int _playerColorIdx = 4; // blue
  static const int _opponentColorIdx = 3; // red

  Widget _headerStrip(String name, int colorIdx, Alignment textAlign, EdgeInsets padding) {
    return ClipRect(
      child: SizedBox(
        height: _barHeight,
        child: Stack(
          children: [
            Positioned(
              top: -colorIdx * _barHeight,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/ui/header_color.png',
                height: _colorCount * _barHeight,
                fit: BoxFit.fill,
              ),
            ),
            Container(
              alignment: textAlign,
              padding: padding,
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontFamily: 'PowerGreen',
                  shadows: [
                    Shadow(
                      offset: Offset(2, 2),
                      color: Color(0xFF606060),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HomeStylePanel(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      borderRadius: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: SizedBox(
              height: _barHeight,
              child: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _headerStrip(
                          widget.playerName, _playerColorIdx,
                          Alignment.centerLeft,
                          const EdgeInsets.only(left: 16),
                        ),
                      ),
                      Expanded(
                        child: _headerStrip(
                          widget.opponentName, _opponentColorIdx,
                          Alignment.centerRight,
                          const EdgeInsets.only(right: 16),
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Image.asset(
                      'assets/ui/hgss_vs1.png',
                      width: 24,
                      height: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF282A30),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Opacity(
                      opacity: widget.isPlayerTurn ? 1.0 : 0.0,
                      child: const _TurnArrow(),
                    ),
                  ),
                ),
                _ScorePill(playerScore: widget.playerScore, opponentScore: widget.opponentScore),
                Expanded(
                  child: Center(
                    child: Opacity(
                      opacity: (!widget.isPlayerTurn) ? 1.0 : 0.0,
                      child: const _TurnArrow(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated turn arrow — cycles through 8 frames (28×40 each)
/// from up_arrow.png (224×40 spritesheet).
class _TurnArrow extends StatefulWidget {
  const _TurnArrow();

  @override
  State<_TurnArrow> createState() => _TurnArrowState();
}

class _TurnArrowState extends State<_TurnArrow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // up_arrow.png: 224×40, 8 frames of 28×40 each.
  static const double _h = 20;
  static const double _w = 14; // 28 * (20/40)

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final frame = (_ctrl.value * 8).floor() % 8;
        return SizedBox(
          width: _w,
          height: _h,
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: -frame * _w,
                  child: Image.asset(
                    'assets/ui/up_arrow.png',
                    height: _h,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.playerScore, required this.opponentScore});

  final int playerScore;
  final int opponentScore;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Player pips: 5 total, filled up to playerScore
            for (var i = 0; i < kDeckSize; i++)
              _ScorePip(col: i < playerScore ? 4 : 0),
            const SizedBox(width: 8),
            // Opponent pips: 5 total, filled up to opponentScore
            for (var i = 0; i < kDeckSize; i++)
              _ScorePip(col: i < opponentScore ? 3 : 0),
          ],
        ),
      ),
    );
  }
}

class _ScorePip extends StatelessWidget {
  /// [col] is the 0-based column in score.png (242×24, 11 cards of 22×24 each).
  /// 0 = blank (now a white card, see column 0's recolor), 3 = opponent
  /// card, 4 = player card.
  const _ScorePip({required this.col});

  final int col;

  /// Slightly smaller than score.png's native 22×24 cells during battle —
  /// scaled uniformly so the crop offset below still lines up per column.
  static const double _scale = 0.75;
  static const double _w = 22 * _scale;
  static const double _h = 24 * _scale;
  static const double _fullW = 242 * _scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -col * _w,
              child: Image.asset('assets/ui/score.png', width: _fullW, height: _h, fit: BoxFit.fill),
            ),
          ],
        ),
      ),
    );
  }
}
