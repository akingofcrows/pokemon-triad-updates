import '../../models/board_position.dart';
import '../../models/card_owner.dart';
import '../../models/match_state.dart';
import '../../models/triad_card.dart';
import '../systems/capture_system.dart';
import '../systems/turn_system.dart';
import 'move_evaluator.dart';

class AiController {
  /// Picks and applies the opponent's best move, after a short "thinking"
  /// delay so the placement doesn't feel instant (GDD §28/§29). No-ops if
  /// it isn't the opponent's turn.
  static Future<void> takeTurn(
    MatchState state, {
    Duration thinkDelay = const Duration(milliseconds: 600),
    void Function(BoardPosition position, TriadCard card, List<BoardPosition> captured)?
        onPlaced,
  }) async {
    if (state.turn != CardOwner.opponent || state.isComplete) return;
    await Future.delayed(thinkDelay);

    final hand = state.opponentHand;
    final best = MoveEvaluator.bestMove(state, hand);
    if (best == null) return;

    hand.removeWhere((c) => identical(c, best.card));
    final captured = CaptureSystem.applyPlacement(state, best.position, best.card);
    TurnSystem.endTurn(state);
    onPlaced?.call(best.position, best.card, captured);
    // Wait for the placement animation to finish before the next turn
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}
