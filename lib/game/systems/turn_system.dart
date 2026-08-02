import '../../models/card_owner.dart';
import '../../models/match_state.dart';

class TurnSystem {
  static bool isPlayerTurn(MatchState state) => state.turn == CardOwner.player;

  static void endTurn(MatchState state) {
    if (state.isComplete) return;
    state.toggleTurn();
  }
}
