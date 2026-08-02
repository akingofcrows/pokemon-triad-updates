import '../../models/board_position.dart';
import '../../models/card_owner.dart';
import '../../models/match_state.dart';
import '../../models/triad_card.dart';
import '../systems/capture_system.dart';

class ScoredMove {
  const ScoredMove({required this.position, required this.card, required this.score});

  final BoardPosition position;
  final TriadCard card;
  final double score;
}

/// GDD §28 "Normal" difficulty heuristic: weighs immediate captures, prefers
/// corners/edges (fewer exposed sides), and penalizes leaving a weak value
/// facing an open cell where the opponent could attack it next turn.
class MoveEvaluator {
  static List<ScoredMove> scoreAllMoves(MatchState state, List<TriadCard> hand) {
    final owner = state.turn;
    final board = state.cells.map((c) => c.card).toList(growable: false);
    final positions = CaptureSystem.emptyPositions(state);

    final moves = <ScoredMove>[];
    for (final card in hand) {
      for (final position in positions) {
        moves.add(
          ScoredMove(
            position: position,
            card: card,
            score: _scoreMove(board, position, card, owner),
          ),
        );
      }
    }
    return moves;
  }

  static ScoredMove? bestMove(MatchState state, List<TriadCard> hand) {
    final moves = scoreAllMoves(state, hand);
    if (moves.isEmpty) return null;
    moves.sort((a, b) => b.score.compareTo(a.score));
    return moves.first;
  }

  static double _scoreMove(
    List<TriadCard?> board,
    BoardPosition position,
    TriadCard card,
    CardOwner owner,
  ) {
    final placedCard = card.owner == owner ? card : card.copyWith(owner: owner);
    final captured = CaptureSystem.resolveCaptures(board, position, placedCard);

    double score = captured.length * 10;
    score += (4 - _exposedSideCount(position)) * 1.5;
    score -= _weakestExposedSidePenalty(board, position, placedCard);
    return score;
  }

  static int _exposedSideCount(BoardPosition position) {
    var count = 0;
    if (position.row > 0) count++;
    if (position.row < 2) count++;
    if (position.column > 0) count++;
    if (position.column < 2) count++;
    return count;
  }

  /// For each side of [placedCard] facing a still-empty on-board cell (i.e.
  /// a side the opponent could attack from a future placement), the lower
  /// that side's value, the riskier the placement.
  static double _weakestExposedSidePenalty(
    List<TriadCard?> board,
    BoardPosition position,
    TriadCard placedCard,
  ) {
    final checks = [
      (value: placedCard.values.north, rowOffset: -1, colOffset: 0),
      (value: placedCard.values.south, rowOffset: 1, colOffset: 0),
      (value: placedCard.values.east, rowOffset: 0, colOffset: 1),
      (value: placedCard.values.west, rowOffset: 0, colOffset: -1),
    ];

    double penalty = 0;
    for (final check in checks) {
      final neighborPos = position.offset(check.rowOffset, check.colOffset);
      if (!neighborPos.isValid) continue;
      if (board[neighborPos.index] != null) continue;
      penalty += (5 - check.value).clamp(0, 5) * 0.6;
    }
    return penalty;
  }
}
