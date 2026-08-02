import '../../models/board_position.dart';
import '../../models/match_state.dart';
import '../../models/triad_card.dart';

enum CompareDirection { north, south, east, west }

/// GDD §16 capture comparison: the placed card wins a side if its value is
/// strictly greater than the touching value of the adjacent card. Equal
/// values do not capture.
bool placedCardWins({
  required TriadCard placed,
  required TriadCard adjacent,
  required CompareDirection direction,
}) {
  switch (direction) {
    case CompareDirection.north:
      return placed.values.north > adjacent.values.south;
    case CompareDirection.south:
      return placed.values.south > adjacent.values.north;
    case CompareDirection.east:
      return placed.values.east > adjacent.values.west;
    case CompareDirection.west:
      return placed.values.west > adjacent.values.east;
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

class CaptureSystem {
  /// Pure: given the current board arrangement (not yet containing
  /// [placedCard] at [position]), returns the positions that would be
  /// captured if [placedCard] were placed there. Does not mutate [board] —
  /// used both by real placement and by AI move evaluation.
  static List<BoardPosition> resolveCaptures(
    List<TriadCard?> board,
    BoardPosition position,
    TriadCard placedCard,
  ) {
    final captured = <BoardPosition>[];
    for (final rule in _neighborRules) {
      final neighborPos = position.offset(rule.rowOffset, rule.colOffset);
      if (!neighborPos.isValid) continue;
      final neighborCard = board[neighborPos.index];
      if (neighborCard == null) continue;
      if (neighborCard.owner == placedCard.owner) continue;
      if (placedCardWins(placed: placedCard, adjacent: neighborCard, direction: rule.direction)) {
        captured.add(neighborPos);
      }
    }
    return captured;
  }

  /// Places [card] on [state] at [position], resolving and applying
  /// captures. Mutates [state] and returns the positions captured.
  static List<BoardPosition> applyPlacement(
    MatchState state,
    BoardPosition position,
    TriadCard card,
  ) {
    final cell = state.cellAt(position);
    assert(cell.isEmpty, 'Cannot place on an occupied cell');

    final board = state.cells.map((c) => c.card).toList(growable: false);
    final captured = resolveCaptures(board, position, card);

    cell.card = card;
    for (final pos in captured) {
      final capturedCell = state.cellAt(pos);
      capturedCell.card = capturedCell.card!.copyWith(owner: card.owner);
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
