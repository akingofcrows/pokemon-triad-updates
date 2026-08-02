import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_triad/game/systems/capture_system.dart';
import 'package:pokemon_triad/models/board_position.dart';
import 'package:pokemon_triad/models/card_owner.dart';
import 'package:pokemon_triad/models/match_state.dart';

import 'test_helpers.dart';

void main() {
  group('placedCardWins', () {
    test('higher value wins', () {
      final placed = makeTestCard(id: 'a', north: 4, south: 1, east: 1, west: 1);
      final adjacent = makeTestCard(id: 'b', north: 1, south: 3, east: 1, west: 1);
      expect(
        placedCardWins(placed: placed, adjacent: adjacent, direction: CompareDirection.north),
        isTrue,
      );
    });

    test('equal values do not capture', () {
      final placed = makeTestCard(id: 'a', north: 4, south: 1, east: 1, west: 1);
      final adjacent = makeTestCard(id: 'b', north: 1, south: 4, east: 1, west: 1);
      expect(
        placedCardWins(placed: placed, adjacent: adjacent, direction: CompareDirection.north),
        isFalse,
      );
    });

    test('lower value loses', () {
      final placed = makeTestCard(id: 'a', north: 2, south: 1, east: 1, west: 1);
      final adjacent = makeTestCard(id: 'b', north: 1, south: 5, east: 1, west: 1);
      expect(
        placedCardWins(placed: placed, adjacent: adjacent, direction: CompareDirection.north),
        isFalse,
      );
    });
  });

  group('CaptureSystem.applyPlacement', () {
    test('captures a single weaker adjacent enemy card', () {
      // GDD §7 example: Bulbasaur placed west of Rattata — Bulbasaur's east
      // (4) beats Rattata's west (3), so Rattata is captured.
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.player);
      final rattata = makeTestCard(
        id: 'rattata',
        north: 1,
        south: 1,
        east: 1,
        west: 3,
        owner: CardOwner.opponent,
      );
      state.cellAt(const BoardPosition(1, 1)).card = rattata;

      final bulbasaur = makeTestCard(
        id: 'bulbasaur',
        north: 3,
        south: 3,
        east: 4,
        west: 2,
        owner: CardOwner.player,
      );
      final captured = CaptureSystem.applyPlacement(state, const BoardPosition(1, 0), bulbasaur);

      expect(captured, [const BoardPosition(1, 1)]);
      expect(state.cellAt(const BoardPosition(1, 1)).card!.owner, CardOwner.player);
    });

    test('does not capture on equal values', () {
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.player);
      final enemy = makeTestCard(
        id: 'enemy',
        north: 1,
        south: 1,
        east: 1,
        west: 4,
        owner: CardOwner.opponent,
      );
      state.cellAt(const BoardPosition(1, 2)).card = enemy;

      final placed = makeTestCard(
        id: 'placed',
        north: 1,
        south: 1,
        east: 4,
        west: 1,
        owner: CardOwner.player,
      );
      final captured = CaptureSystem.applyPlacement(state, const BoardPosition(1, 1), placed);

      expect(captured, isEmpty);
      expect(state.cellAt(const BoardPosition(1, 2)).card!.owner, CardOwner.opponent);
    });

    test('does not flip a friendly adjacent card even if it would lose', () {
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.player);
      final friendly = makeTestCard(
        id: 'friendly',
        north: 1,
        south: 1,
        east: 1,
        west: 1,
        owner: CardOwner.player,
      );
      state.cellAt(const BoardPosition(0, 1)).card = friendly;

      final placed = makeTestCard(
        id: 'placed',
        north: 9,
        south: 1,
        east: 1,
        west: 1,
        owner: CardOwner.player,
      );
      final captured = CaptureSystem.applyPlacement(state, const BoardPosition(1, 1), placed);

      expect(captured, isEmpty);
    });

    test('captures multiple adjacent enemies at once', () {
      final state = MatchState(playerHand: [], opponentHand: [], firstTurn: CardOwner.player);
      final north = makeTestCard(
        id: 'n',
        north: 1,
        south: 2,
        east: 1,
        west: 1,
        owner: CardOwner.opponent,
      );
      final south = makeTestCard(
        id: 's',
        north: 2,
        south: 1,
        east: 1,
        west: 1,
        owner: CardOwner.opponent,
      );
      final east = makeTestCard(
        id: 'e',
        north: 1,
        south: 1,
        east: 1,
        west: 2,
        owner: CardOwner.opponent,
      );
      final west = makeTestCard(
        id: 'w',
        north: 1,
        south: 1,
        east: 2,
        west: 1,
        owner: CardOwner.opponent,
      );
      state.cellAt(const BoardPosition(0, 1)).card = north;
      state.cellAt(const BoardPosition(2, 1)).card = south;
      state.cellAt(const BoardPosition(1, 2)).card = east;
      state.cellAt(const BoardPosition(1, 0)).card = west;

      final placed = makeTestCard(
        id: 'placed',
        north: 5,
        south: 5,
        east: 5,
        west: 5,
        owner: CardOwner.player,
      );
      final captured = CaptureSystem.applyPlacement(state, const BoardPosition(1, 1), placed);

      expect(captured, hasLength(4));
      expect(state.scoreFor(CardOwner.player), 5); // 1 placed + 4 flipped
    });
  });
}
