/// A named battle opponent (`assets/data/npcs.json`, converted from TTMMO's
/// `data/npcs.json`) — replaces the generic "starter deck" AI opponents in
/// Battle Setup with Youngster Joey, Brock, Lass, etc.
class NpcTrainer {
  const NpcTrainer({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.flavor,
    required this.cardIds,
    this.deck,
    required this.portrait,
    this.victoryQuote,
    this.defeatQuote,
  });

  final String id;
  final String name;
  final String difficulty;
  final String flavor;
  final List<String> cardIds;
  final List<String>? deck;
  final String portrait;
  final String? victoryQuote;
  final String? defeatQuote;

  String get portraitAsset => 'assets/trainers/npc/$portrait';

  factory NpcTrainer.fromJson(Map<String, dynamic> json) {
    return NpcTrainer(
      id: json['id'] as String,
      name: json['name'] as String,
      difficulty: json['difficulty'] as String,
      flavor: json['flavor'] as String,
      cardIds: (json['cards'] as List<dynamic>).cast<String>(),
      deck: (json['deck'] as List<dynamic>?)?.cast<String>(),
      portrait: json['portrait'] as String,
      victoryQuote: json['victoryQuote'] as String?,
      defeatQuote: json['defeatQuote'] as String?,
    );
  }
}
