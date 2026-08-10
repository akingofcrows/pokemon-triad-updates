import '../../models/board_position.dart';
import '../../models/card_owner.dart';
import '../../models/match_state.dart';
import '../../models/triad_card.dart';

enum CompareDirection { north, south, east, west }

/// GDD §16 capture comparison: the placed card wins a side if its value is
/// strictly greater than the touching value of the adjacent card. Equal
/// values do not capture under the default rule.
bool placedCardWins({
  required TriadCard placed,
  required TriadCard adjacent,
  required CompareDirection direction,
}) {
  final placedVal = _sideValue(placed, direction);
  final adjVal = _sideValue(adjacent, _opposite(direction));

  return placedVal > adjVal;
}

/// Returns the value on the side of [card] facing [direction].
int _sideValue(TriadCard card, CompareDirection direction) {
  switch (direction) {
    case CompareDirection.north: return card.values.north;
    case CompareDirection.south: return card.values.south;
    case CompareDirection.east: return card.values.east;
    case CompareDirection.west: return card.values.west;
  }
}

/// Returns the opposite direction.
CompareDirection _opposite(CompareDirection d) {
  switch (d) {
    case CompareDirection.north: return CompareDirection.south;
    case CompareDirection.south: return CompareDirection.north;
    case CompareDirection.east: return CompareDirection.west;
    case CompareDirection.west: return CompareDirection.east;
  }
}

class _NeighborRule {
  const _NeighborRule(this.rowOffset, this.colOffset, this.direction);
  final int rowOffset;
  final int colOffset;
  final CompareDirection direction;
}

const List<_NeighborRule> _neighborRules = [
  _NeighborRule(-1, 0, CompareDirection.north),
  _NeighborRule(1, 0, CompareDirection.south),
  _NeighborRule(0, 1, CompareDirection.east),
  _NeighborRule(0, -1, CompareDirection.west),
];

/// Which Triple Triad rules are active for a match.
class RuleSet {
  final bool same;   // Equal values capture (combo)
  final bool plus;   // Sum-match captures
  final bool wall;   // Walls count as A in same/plus calculations

  const RuleSet({this.same = false, this.plus = false, this.wall = false});

  static const RuleSet basic = RuleSet();
  static const RuleSet advanced = RuleSet(same: true, plus: false);
  static const RuleSet expert = RuleSet(same: true, plus: true);
}

class CaptureSystem {
  /// Pure: given the current board arrangement (not yet containing
  /// [placedCard] at [position]), returns the positions that would be
  /// captured if [placedCard] were placed there. Does not mutate [board] —
  /// used both by real placement and by AI move evaluation.
  static List<BoardPosition> resolveCaptures(
    List<TriadCard?> board,
    BoardPosition position,
    TriadCard placedCard, {
    RuleSet rules = RuleSet.basic,
  }) {
    final captured = <BoardPosition>{};
    final touches = <_NeighborRule, TriadCard>{};

    // Phase 1: basic greater-than captures
    for (final rule in _neighborRules) {
      final neighborPos = position.offset(rule.rowOffset, rule.colOffset);
      if (!neighborPos.isValid) continue;
      final neighborCard = board[neighborPos.index];
      if (neighborCard == null) continue;
      if (neighborCard.owner == placedCard.owner) continue;
      if (neighborCard.pokeballCaptured) continue; // can't flip pokéball-captured
      if (placedCardWins(placed: placedCard, adjacent: neighborCard, direction: rule.direction)) {
        captured.add(neighborPos);
      }
      // Track touches for Same/Plus rules
      if (neighborCard.owner != placedCard.owner) {
        touches[rule] = neighborCard;
      }
    }

    // Phase 2: Same rule — equal values capture
    if (rules.same) {
      for (final entry in touches.entries) {
        final rule = entry.key;
        final neighborCard = entry.value;
        final neighborPos = position.offset(rule.rowOffset, rule.colOffset);
        final placedVal = _sideValue(placedCard, rule.direction);
        final neighborVal = _sideValue(neighborCard, _opposite(rule.direction));
        if (placedVal == neighborVal) {
          captured.add(neighborPos);
        }
      }
    }

    // Phase 3: Plus rule — sum of two touching sides equals another pair's sum
    if (rules.plus && touches.length >= 2) {
      final entries = touches.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          final aRule = entries[i].key;
          final bRule = entries[j].key;
          final aPlaced = _sideValue(placedCard, aRule.direction);
          final aNeighbor = _sideValue(entries[i].value, _opposite(aRule.direction));
          final bPlaced = _sideValue(placedCard, bRule.direction);
          final bNeighbor = _sideValue(entries[j].value, _opposite(bRule.direction));
          if (aPlaced + aNeighbor == bPlaced + bNeighbor) {
            captured.add(position.offset(aRule.rowOffset, aRule.colOffset));
            captured.add(position.offset(bRule.rowOffset, bRule.colOffset));
          }
        }
      }
    }

    return captured.toList();
  }

  /// Places [card] on [state] at [position], resolving and applying
  /// captures. Mutates [state] and returns the positions captured.
  static List<BoardPosition> applyPlacement(
    MatchState state,
    BoardPosition position,
    TriadCard card, {
    RuleSet rules = RuleSet.basic,
  }) {
    final cell = state.cellAt(position);
    assert(cell.isEmpty, 'Cannot place on an occupied cell');

    final board = state.cells.map((c) => c.card).toList(growable: false);
    final captured = resolveCaptures(board, position, card, rules: rules);

    cell.card = card;
    for (final pos in captured) {
      final capturedCell = state.cellAt(pos);
      final previousCard = capturedCell.card!;
      // A player card that gets flipped by the opponent accrues Condition
      // wear (GDD §7); the reverse (player flipping an opponent card) does
      // not, since opponent cards don't carry persistent Condition.
      if (previousCard.owner == CardOwner.player && card.owner != CardOwner.player) {
        state.recordFlipped(previousCard);
      }
      capturedCell.card = previousCard.copyWith(owner: card.owner);
    }

    state.lastCaptured
      ..clear()
      ..addAll(captured);
    return captured;
  }

  static List<BoardPosition> emptyPositions(MatchState state) {
    return [
      for (var i = 0; i < state.cells.length; i++)
        if (state.cells[i].isEmpty) BoardPosition.fromIndex(i),
    ];
  }
}
