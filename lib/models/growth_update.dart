/// One card's XP/level-up outcome from a single `POST /me/match-result`
/// call, as returned by TTMMO's `addGrowthXP`.
class GrowthUpdate {
  const GrowthUpdate({
    required this.cardId,
    required this.leveledUp,
    required this.newLevel,
    this.statBumped,
    this.xpGained = 0,
    this.instanceId,
  });

  final String cardId;
  final bool leveledUp;
  final int newLevel;
  final String? statBumped;
  final int xpGained;
  final int? instanceId;

  factory GrowthUpdate.fromJson(Map<String, dynamic> json) {
    return GrowthUpdate(
      cardId: json['cardId'] as String,
      leveledUp: json['leveledUp'] as bool? ?? false,
      newLevel: json['newLevel'] as int? ?? 1,
      statBumped: json['statBumped'] as String?,
      xpGained: json['xpGained'] as int? ?? 0,
      instanceId: json['instanceId'] as int?,
    );
  }
}
