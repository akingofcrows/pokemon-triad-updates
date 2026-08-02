import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_triad/game/ai/move_evaluator.dart';
import 'package:pokemon_triad/models/board_position.dart';
import 'package:pokemon_triad/models/card_owner.dart';
import 'package:pokemon_triad/models/match_state.dart';

import 'test_helpers.dart';

void main() {
  group('MoveEvaluator', () {
    test('prefers a card that captures over one that cannot, at the only open cell', () {
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.opponent);

      // A weak player-owned card sits north of the only empty cell (center).
      final weak = makeTestCard(
        id: 'weak',
        north: 1,
        south: 1,
        east: 1,
        west: 1,
        owner: CardOwner.player,
      );
      state.cellAt(const BoardPosition(0, 1)).card = weak;

      // Fill every other cell so the center is the only legal placement —
      // isolates the "which card" decision from any positional scoring.
      final filler = makeTestCard(
        id: 'filler',
        north: 5,
        south: 5,
        east: 5,
        west: 5,
        owner: CardOwner.opponent,
      );
      for (final position in const [
        BoardPosition(0, 0),
        BoardPosition(0, 2),
        BoardPosition(1, 0),
        BoardPosition(1, 2),
        BoardPosition(2, 0),
        BoardPosition(2, 1),
        BoardPosition(2, 2),
      ]) {
        state.cellAt(position).card = filler;
      }

      final capturer = makeTestCard(
        id: 'capturer',
        north: 9,
        south: 1,
        east: 1,
        west: 1,
        owner: CardOwner.opponent,
      );
      final dud = makeTestCard(id: 'dud', north: 1, south: 1, east: 1, west: 1, owner: CardOwner.opponent);

      final best = MoveEvaluator.bestMove(state, [dud, capturer]);

      expect(best, isNotNull);
      expect(best!.position, const BoardPosition(1, 1));
      expect(best.card.id, 'capturer');
    });

    test('scoreAllMoves returns one entry per (card, empty position) pair', () {
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.opponent);
      final hand = [
        makeTestCard(id: 'a', north: 1, south: 1, east: 1, west: 1, owner: CardOwner.opponent),
        makeTestCard(id: 'b', north: 2, south: 2, east: 2, west: 2, owner: CardOwner.opponent),
      ];

      final moves = MoveEvaluator.scoreAllMoves(state, hand);

      expect(moves, hasLength(hand.length * 9));
    });
  });
}
