import 'growth_update.dart';
import 'pending_evolution.dart';

/// Combined response from `POST /me/match-result`: per-card XP/level-up
/// outcomes plus any cards that just became eligible to evolve.
class MatchGrowthResult {
  const MatchGrowthResult({
    required this.growth,
    required this.pendingEvolutions,
    this.bonusXp = const {},
    this.trainerXpEarned = 0,
  });

  final List<GrowthUpdate> growth;
  final List<PendingEvolution> pendingEvolutions;
  final Map<String, int> bonusXp; // cardId → bonus XP amount
  final int trainerXpEarned;

  factory MatchGrowthResult.fromJson(Map<String, dynamic> json) {
    return MatchGrowthResult(
      growth: (json['growth'] as List<dynamic>? ?? [])
          .map((e) => GrowthUpdate.fromJson(e as Map<String, dynamic>))
          .toList(),
      pendingEvolutions: (json['pendingEvolutions'] as List<dynamic>? ?? [])
          .map((e) => PendingEvolution.fromJson(e as Map<String, dynamic>))
          .toList(),
      bonusXp: (json['bonusXp'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {},
    );
  }
}
