import 'triad_card.dart';

const int kDeckSize = 5;

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.cardIds,
    this.instanceIds,
    this.boxImage = 'field_deck',
    this.isDefault = false,
    this.featuredCardIndex = 0,
    this.shinyIndices,
    this.opponentCards,
  });

  final String id;
  final String name;
  /// Exactly [kDeckSize] card ids. Duplicates are allowed.
  final List<String> cardIds;
  /// Optional per-slot instance IDs for individual card copies.
  /// Length matches [cardIds]; null entries mean "use best available instance."
  final List<int?>? instanceIds;
  /// Deck box image key: 'field_deck', 'field_box', 'base_box'
  final String? boxImage;
  final bool isDefault;
  /// Index of the featured card shown on the deck box.
  final int? featuredCardIndex;
  /// Indices into [cardIds] that should render as shiny (for wild encounters).
  final Set<int>? shinyIndices;
  /// Pre-built cards (for wild battles with random stats). When provided,
  /// these are used instead of looking up from [cardIds].
  final List<TriadCard>? opponentCards;

  bool get isValid => cardIds.length == kDeckSize;

  Deck copyWith({String? name, List<String>? cardIds, List<int?>? instanceIds, String? boxImage, bool? isDefault, int? featuredCardIndex}) {
    return Deck(
      id: id,
      name: name ?? this.name,
      cardIds: cardIds ?? this.cardIds,
      instanceIds: instanceIds ?? this.instanceIds,
      boxImage: boxImage ?? this.boxImage,
      isDefault: isDefault ?? this.isDefault,
      featuredCardIndex: featuredCardIndex ?? this.featuredCardIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cardIds': cardIds,
    if (instanceIds != null) 'instanceIds': instanceIds,
    'boxImage': boxImage,
    'isDefault': isDefault,
    if (featuredCardIndex != null) 'featuredCardIndex': featuredCardIndex,
  };

  factory Deck.fromJson(Map<String, dynamic> json) {
    final raw = json['instanceIds'];
    List<int?>? instanceIds;
    if (raw is List) {
      instanceIds = raw.map((e) {
        if (e is int) return e;
        if (e is String) return int.tryParse(e);
        return null;
      }).toList();
    }
    return Deck(
      id: json['id'] as String,
      name: json['name'] as String,
      cardIds: (json['cardIds'] as List<dynamic>).cast<String>(),
      instanceIds: instanceIds,
      boxImage: json['boxImage'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      featuredCardIndex: json['featuredCardIndex'] as int?,
    );
  }
}
