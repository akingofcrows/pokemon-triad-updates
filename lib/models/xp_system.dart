/// Pokémon Triad XP and leveling system.
///
/// Implements the full first-version XP rules:
/// placement, direct/combo flips, assists, move effects, defense,
/// survival, victory, MVP, plus encounter modifiers.
///
/// Level curve uses the real Pokémon cubic formula (n³ / divisor)
/// mapped to species growth rate groups. See [pokemon_leveling.dart].

import 'pokemon_leveling.dart';

// ── XP award constants ──────────────────────────────────────────────────

/// XP awarded the first time a card is placed on the board during a match.
const int kXpPlacement = 4;

/// XP for directly flipping an opponent card.
const int kXpDirectFlip = 5;

/// XP for each card flipped in a combo chain.
const int kXpComboFlip = 3;

/// XP when a move effect helps another ally flip a card.
const int kXpAssist = 2;

/// Maximum assist XP caused by one captured card.
const int kXpMaxAssistPerCapture = 4;

/// XP for a useful move effect (status application, removal, protection, etc.).
const int kXpUsefulMove = 2;

/// XP when successfully resisting a capture attempt.
const int kXpDefense = 2;

/// Maximum defense XP per Pokémon per match.
const int kXpMaxDefensePerMatch = 6;

/// XP for remaining on the player's side at match end.
const int kXpSurvival = 2;

/// XP bonus for winning the match.
const int kXpVictory = 6;

/// XP bonus for a draw.
const int kXpDraw = 3;

/// XP bonus for Match MVP.
const int kXpMvp = 3;

// ── XP per-instance tracking during a match ─────────────────────────────

/// Tracks all XP sources for a single card instance during one match.
class MatchCardXp {
  MatchCardXp({required this.instanceId, required this.cardId});

  final int instanceId;
  final String cardId;

  int placed = 0;
  int directFlips = 0;
  int comboFlips = 0;
  int assists = 0;
  int usefulMoves = 0;
  int defenses = 0;
  int survival = 0;
  int victory = 0;
  int mvp = 0;

  bool get wasPlaced => placed > 0;

  int get totalXp {
    return (wasPlaced ? kXpPlacement : 0) +
        directFlips * kXpDirectFlip +
        comboFlips * kXpComboFlip +
        assists * kXpAssist +
        usefulMoves * kXpUsefulMove +
        defenses * kXpDefense +
        survival * kXpSurvival +
        victory * kXpVictory +
        mvp * kXpMvp;
  }

  /// Human-readable breakdown matching the post-match summary format.
  Map<String, int> get breakdown {
    final result = <String, int>{};
    if (wasPlaced) result['Placed'] = kXpPlacement;
    if (directFlips > 0) result['Direct flip'] = directFlips * kXpDirectFlip;
    if (comboFlips > 0) result['Combo flip'] = comboFlips * kXpComboFlip;
    if (assists > 0) result['Assist'] = assists * kXpAssist;
    if (usefulMoves > 0) result['Useful move'] = usefulMoves * kXpUsefulMove;
    if (defenses > 0) result['Defense'] = defenses * kXpDefense;
    if (survival > 0) result['Survival'] = survival * kXpSurvival;
    if (victory > 0) result['Victory'] = victory * kXpVictory;
    if (mvp > 0) result['MVP'] = mvp * kXpMvp;
    return result;
  }

  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'cardId': cardId,
    'placed': wasPlaced,
    'directFlips': directFlips,
    'comboFlips': comboFlips,
    'assists': assists,
    'usefulMoves': usefulMoves,
    'defenses': defenses,
    'survival': survival,
    'victory': victory,
    'mvp': mvp,
    'totalXp': totalXp,
  };
}

// ── Encounter modifiers ─────────────────────────────────────────────────

enum EncounterType {
  practice,
  tutorial,
  commonWild,
  strongWild,
  npcTrainer,
  gymTrainer,
  rival,
  gymLeader,
  storyBoss,
  standardPvP,
  tournament,
}

double encounterXpModifier(EncounterType type) => switch (type) {
  EncounterType.practice => 0.25,
  EncounterType.tutorial => 0.50,
  EncounterType.commonWild => 1.00,
  EncounterType.strongWild => 1.20,
  EncounterType.npcTrainer => 1.25,
  EncounterType.gymTrainer => 1.40,
  EncounterType.rival => 1.50,
  EncounterType.gymLeader => 1.75,
  EncounterType.storyBoss => 1.75,
  EncounterType.standardPvP => 1.00,
  EncounterType.tournament => 1.25,
};
