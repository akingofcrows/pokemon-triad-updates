import 'package:flutter/foundation.dart' show debugPrint;

import 'board_position.dart';
import 'card_owner.dart';
import 'triad_card.dart';
import 'xp_system.dart';

class BoardCell {
  BoardCell({this.card});

  TriadCard? card;

  bool get isEmpty => card == null;
}

/// Mutable battle state for a single match. Owned and driven by the Flame
/// board/turn systems rather than rebuilt immutably each turn — a match is a
/// short-lived, single-screen session, not app-wide state.
class MatchState {
  MatchState({
    required this.playerHand,
    required this.opponentHand,
    required this.firstTurn,
    Map<TriadCard, int>? playerCardInstanceIds,
  }) : cells = List.generate(9, (_) => BoardCell()),
       turn = firstTurn,
       playerCardInstanceIds = playerCardInstanceIds ?? {};

  final List<TriadCard> playerHand;
  final List<TriadCard> opponentHand;
  final List<BoardCell> cells;
  final CardOwner firstTurn;
  CardOwner turn;

  final List<BoardPosition> lastCaptured = [];

  // ── Legacy XP tracking (kept for backward compat) ─────────────────

  /// Total XP earned per player card instance ID from captures this match.
  final Map<int, int> captureXpByInstanceId = {};

  /// How many opponent cards each of the player's own cards personally
  /// captured this match, keyed by card id.
  final Map<String, int> captureCountByCardId = {};

  // ── New per-instance XP breakdown ──────────────────────────────────

  /// Detailed XP tracking per player card instance.
  final Map<int, MatchCardXp> cardXp = {};

  /// Instance IDs of cards that have been placed this match.
  final Set<int> _placedInstances = {};

  /// Maps each player card (TriadCard reference) to its instance ID.
  final Map<TriadCard, int> playerCardInstanceIds;

  /// Look up or create the [MatchCardXp] for a given instance.
  MatchCardXp _xpFor(int instanceId, String cardId) {
    return cardXp.putIfAbsent(instanceId, () => MatchCardXp(instanceId: instanceId, cardId: cardId));
  }

  /// Resolve the instance ID for a player card.
  int? instanceIdFor(TriadCard playerCard) => playerCardInstanceIds[playerCard];

  // ── XP award methods ───────────────────────────────────────────────

  /// Award placement XP the first time a card hits the board.
  void recordPlacement(TriadCard playerCard) {
    final instId = playerCardInstanceIds[playerCard];
    if (instId == null || _placedInstances.contains(instId)) return;
    _placedInstances.add(instId);
    _xpFor(instId, playerCard.id).placed = 1;
    debugPrint('[XP-MATCH] recordPlacement: ${playerCard.name} instId=$instId');
  }

  /// Record a direct or combo flip. [playerCard] is the card that did the flipping.
  /// [capturedCount] is how many cards were captured (1 = direct, >1 includes combos).
  /// [totalXp] is the legacy XP amount (still tracked for backward compat).
  void recordCapture(TriadCard playerCard, int capturedCount, int totalXp) {
    captureCountByCardId.update(playerCard.id, (v) => v + capturedCount,
        ifAbsent: () => capturedCount);
    final instId = playerCardInstanceIds[playerCard];
    if (instId == null) {
      debugPrint('[XP-MATCH] recordCapture: NO instanceId for ${playerCard.name}');
      return;
    }

    // Legacy XP
    captureXpByInstanceId.update(instId, (v) => v + totalXp, ifAbsent: () => totalXp);

    // New per-source XP
    final xp = _xpFor(instId, playerCard.id);
    xp.directFlips += 1;            // first flip is direct
    if (capturedCount > 1) {
      xp.comboFlips += capturedCount - 1;  // rest are combo
    }
    debugPrint('[XP-MATCH] recordCapture: ${playerCard.name} instId=$instId flips=$capturedCount → direct=${xp.directFlips} combo=${xp.comboFlips}');
  }

  /// Award assist XP when a move effect helps another card flip.
  void recordAssist(TriadCard playerCard) {
    final instId = playerCardInstanceIds[playerCard];
    if (instId == null) return;
    final xp = _xpFor(instId, playerCard.id);
    if (xp.assists * kXpAssist < kXpMaxAssistPerCapture) {
      xp.assists += 1;
    }
  }

  /// Award XP for a useful move effect.
  void recordUsefulMove(TriadCard playerCard) {
    final instId = playerCardInstanceIds[playerCard];
    if (instId == null) return;
    _xpFor(instId, playerCard.id).usefulMoves += 1;
  }

  /// Award defense XP when a card resists a capture.
  void recordDefense(TriadCard playerCard) {
    final instId = playerCardInstanceIds[playerCard];
    if (instId == null) return;
    final xp = _xpFor(instId, playerCard.id);
    if (xp.defenses * kXpDefense < kXpMaxDefensePerMatch) {
      xp.defenses += 1;
    }
  }

  /// Called at match end. Awards survival + victory/draw XP.
  /// Returns the MVP instance ID if one was selected.
  int? finalizeMatch({required bool playerWon, required bool isDraw}) {
    // Survival XP for cards still on the player's side
    var survivalCount = 0;
    for (final cell in cells) {
      if (cell.card?.owner == CardOwner.player) {
        final instId = playerCardInstanceIds[cell.card];
        if (instId != null) {
          _xpFor(instId, cell.card!.id).survival = 1;
          survivalCount++;
        }
      }
    }

    // Victory / draw XP — only when board is full (all 9 cells filled)
    var vicCount = 0;
    if ((playerWon || isDraw) && placedCount == 9) {
      for (final entry in playerCardInstanceIds.entries) {
        final xp = _xpFor(entry.value, entry.key.id);
        xp.victory = isDraw ? 0 : 1;
        if (!isDraw) vicCount++;
      }
    }
    debugPrint('[XP-MATCH] finalizeMatch: won=$playerWon draw=$isDraw survival=$survivalCount victory=$vicCount cardXp=${cardXp.length} entries');

    // MVP: pick the card with the highest total XP
    int? mvpId;
    var bestTotal = 0;
    for (final xp in cardXp.values) {
      if (xp.totalXp > bestTotal) {
        bestTotal = xp.totalXp;
        mvpId = xp.instanceId;
      }
    }
    if (mvpId != null) {
      cardXp[mvpId]!.mvp = 1;
    }
    return mvpId;
  }

  BoardCell cellAt(BoardPosition position) => cells[position.index];

  int get placedCount => cells.where((c) => !c.isEmpty).length;

  bool get isComplete => placedCount == 9;

  List<TriadCard> handFor(CardOwner owner) {
    return owner == CardOwner.player ? playerHand : opponentHand;
  }

  /// Cards the player currently controls *on the board* — placed own cards
  /// plus any opponent cards they've captured.  This is the Triple Triad
  /// "score" that the header pips track and that determines the winner.
  int scoreFor(CardOwner owner) {
    return cells.where((c) => c.card?.owner == owner).length;
  }

  void toggleTurn() {
    turn = turn == CardOwner.player ? CardOwner.opponent : CardOwner.player;
  }
}
