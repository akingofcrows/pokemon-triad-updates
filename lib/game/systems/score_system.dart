import '../../models/card_owner.dart';
import '../../models/match_state.dart';

enum MatchOutcome { win, loss, draw }

class ScoreSystem {
  static int scoreFor(MatchState state, CardOwner owner) => state.scoreFor(owner);

  /// Result from [perspective]'s point of view. Only meaningful once
  /// [MatchState.isComplete] (GDD §9: more cards controlled wins).
  static MatchOutcome outcomeFor(MatchState state, CardOwner perspective) {
    final opponent =
        perspective == CardOwner.player ? CardOwner.opponent : CardOwner.player;
    final mine = state.scoreFor(perspective);
    final theirs = state.scoreFor(opponent);
    if (mine > theirs) return MatchOutcome.win;
    if (mine < theirs) return MatchOutcome.loss;
    return MatchOutcome.draw;
  }
}
