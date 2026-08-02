/// A card that just became eligible to evolve, returned from
/// `POST /me/match-result` after a level-up crosses an evolution threshold.
class PendingEvolution {
  const PendingEvolution({required this.cardId, required this.toId, required this.level, this.instanceId});

  final String cardId;
  final String toId;
  final int level;
  final int? instanceId;

  factory PendingEvolution.fromJson(Map<String, dynamic> json) {
    return PendingEvolution(
      cardId: json['cardId'] as String,
      toId: json['toId'] as String,
      level: json['level'] as int,
      instanceId: json['instanceId'] as int?,
    );
  }
}
