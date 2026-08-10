import 'card_values.dart';
import 'condition.dart';

/// XP awarded per opponent card captured — kept in sync with the server's
/// XP_PER_CAPTURE constant (`playerRoutes.ts`); used client-side only for
/// immediate display (the battle log, before the match result round-trip).
const int kXpPerCapture = 5;

/// Returns the XP earned from capturing a card with the given total power.
/// Scales with opponent strength, minimum 5 XP.
int xpForCapture(int capturedCardTotal) => capturedCardTotal < 5 ? 5 : capturedCardTotal;

/// Per-card growth progress from TTMMO's `player_card_instances` — XP,
/// level, and any random N/S/E/W stat bumps earned at milestone levels.
class CardGrowth {
  const CardGrowth({
    required this.cardId,
    required this.xp,
    required this.level,
    required this.bonusNorth,
    required this.bonusSouth,
    required this.bonusEast,
    required this.bonusWest,
    this.source,
    this.shiny = false,
    this.instanceId,
    this.condition = kMaxCondition,
    this.reverseHolo = false,
  });

  final String cardId;
  final int xp;
  final int level;
  final int bonusNorth;
  final int bonusSouth;
  final int bonusEast;
  final int bonusWest;
  final bool shiny;
  final String? source;
  final int? instanceId;
  final bool reverseHolo;

  /// 0-100 wear value for this owned card instance. See
  /// pokemon_triad_condition_system.md.
  final int condition;

  ConditionTier get conditionTier => tierForCondition(condition);

  /// A human-readable "how obtained" string for the card detail dialog.
  String get humanizedSource {
    switch (source) {
      case 'registration_grant':
        return 'Starter Collection';
      case 'starter_deck':
        return "Prof. Oak's Starter Deck";
      case 'wild_battle':
        return 'Wild Battle';
      case null:
        return 'Unknown';
      default:
        return source!
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  CardValues get bonusValues => CardValues(
    north: bonusNorth,
    south: bonusSouth,
    east: bonusEast,
    west: bonusWest,
  );

  factory CardGrowth.fromJson(Map<String, dynamic> json) {
    return CardGrowth(
      cardId: json['cardId'] as String,
      xp: json['xp'] as int,
      level: json['level'] as int,
      bonusNorth: json['bonusNorth'] as int? ?? 0,
      bonusSouth: json['bonusSouth'] as int? ?? 0,
      bonusEast: json['bonusEast'] as int? ?? 0,
      bonusWest: json['bonusWest'] as int? ?? 0,
      source: json['source'] as String?,
      shiny: json['shiny'] == 1 || json['shiny'] == true,
      instanceId: json['instanceId'] as int?,
      condition: json['condition'] as int? ?? kMaxCondition,
      reverseHolo: json['reverseHolo'] == 1 || json['reverseHolo'] == true,
    );
  }
}
