import 'deck.dart';

class PlayerProfile {
  PlayerProfile({
    required this.playerName,
    required this.ownedCardIds,
    required this.decks,
    this.defaultDeckId,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.money = 0,
    this.joinedAt,
    this.trainerName,
    this.gender,
    this.skinTone,
    this.hairPath,
    this.topPath,
    this.bottomPath,
    this.hatPath,
    this.friendCode,
    this.location,
    Set<String>? seenCardIds,
    Set<String>? everOwnedCardIds,
    Set<String>? everOwnedShinyCardIds,
  })  : seenCardIds = seenCardIds ?? {},
        everOwnedCardIds = everOwnedCardIds ?? {},
        everOwnedShinyCardIds = everOwnedShinyCardIds ?? {};

  String playerName;
  Set<String> ownedCardIds;
  /// Cards the player has encountered (seen in battle, opponent's deck, etc.).
  /// Always a superset of [ownedCardIds] — owning a card implies having seen it.
  Set<String> seenCardIds;
  /// Cards the player has ever owned at any point (persisted locally).
  /// Survives evolution — once owned, always remembered.
  Set<String> everOwnedCardIds;
  /// Cards the player has ever owned as *shiny* variants (persisted locally).
  /// Survives evolution — once a shiny was owned, it stays in the Shiny Dex.
  Set<String> everOwnedShinyCardIds;
  List<Deck> decks;
  String? defaultDeckId;
  int wins;
  int losses;
  int draws;
  int money;

  /// Raw `created_at` timestamp string from TTMMO's `player_profiles` table
  /// (e.g. `2026-07-01 12:34:56`) — parsed for display on the Trainer Card.
  String? joinedAt;

  /// Null until the player has completed the Professor Oak character
  /// creation flow (see CharacterCreatorScreen) — that's the gate used to
  /// decide whether to show it after login/registration.
  String? trainerName;
  String? gender; // 'boy' | 'girl'
  String? skinTone;
  String? hairPath;
  String? topPath;
  String? bottomPath;
  String? hatPath;
  String? friendCode;
  String? location;
  int giftCount = 0;

  bool get hasCharacter => trainerName != null;

  /// A fresh profile owns every card in the pool — this game has no
  /// booster-pack/wild-capture acquisition loop yet (see GDD "Not Included
  /// Yet"), so Collection/Deck Builder need somewhere to start from.
  factory PlayerProfile.newProfile({
    required String playerName,
    required List<String> allCardIds,
  }) {
    return PlayerProfile(
      playerName: playerName,
      ownedCardIds: allCardIds.toSet(),
      decks: [],
    );
  }

  Deck? get defaultDeck {
    if (defaultDeckId == null) return null;
    for (final deck in decks) {
      if (deck.id == defaultDeckId) return deck;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'playerName': playerName,
    'ownedCardIds': ownedCardIds.toList(),
    'seenCardIds': seenCardIds.toList(),
    'decks': decks.map((d) => d.toJson()).toList(),
    'defaultDeckId': defaultDeckId,
    'wins': wins,
    'losses': losses,
    'draws': draws,
    'money': money,
    'joinedAt': joinedAt,
  };

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      playerName: json['playerName'] as String,
      ownedCardIds: (json['ownedCardIds'] as List<dynamic>).cast<String>().toSet(),
      seenCardIds: json['seenCardIds'] != null
          ? (json['seenCardIds'] as List<dynamic>).cast<String>().toSet()
          : null,
      decks: (json['decks'] as List<dynamic>)
          .map((d) => Deck.fromJson(d as Map<String, dynamic>))
          .toList(),
      defaultDeckId: json['defaultDeckId'] as String?,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
      money: json['money'] as int? ?? 0,
      joinedAt: json['joinedAt'] as String?,
    );
  }
}
