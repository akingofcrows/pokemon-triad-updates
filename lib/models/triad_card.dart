import 'card_owner.dart';
import 'card_values.dart';

enum TriadCardType { pokemon, trainer }

enum CardRarity { common, uncommon, rare, epic, legendary }

CardRarity rarityFromString(String value) {
  return CardRarity.values.firstWhere(
    (r) => r.name == value,
    orElse: () => CardRarity.common,
  );
}

class TriadCard {
  const TriadCard({
    required this.id,
    required this.speciesId,
    required this.name,
    required this.cardType,
    required this.rarity,
    required this.affinity,
    required this.values,
    required this.image,
    this.owner = CardOwner.neutral,
    this.worth = 0,
    this.cardNumber = '',
    this.isStarter = false,
    this.holo = false,
    this.reverseHolo = false,
    this.shiny = false,
    this.evolvesTo,
    this.baseLevel,
  });

  final String id;
  final String speciesId;
  final String name;
  final TriadCardType cardType;
  final CardRarity rarity;
  final String affinity;
  final CardValues values;
  final String image;
  final CardOwner owner;
  final int worth;
  final String cardNumber;
  final bool isStarter;
  final bool holo;
  final bool reverseHolo;
  final bool shiny;
  final String? evolvesTo;
  final int? baseLevel;

  TriadCard copyWith({CardOwner? owner, CardValues? values, bool? holo, bool? reverseHolo, bool? shiny, String? image, int? baseLevel}) {
    return TriadCard(
      id: id, speciesId: speciesId, name: name, cardType: cardType, rarity: rarity, affinity: affinity,
      values: values ?? this.values, image: image ?? this.image,
      owner: owner ?? this.owner, worth: worth, cardNumber: cardNumber, isStarter: isStarter,
      holo: holo ?? this.holo, reverseHolo: reverseHolo ?? this.reverseHolo, shiny: shiny ?? this.shiny,
      evolvesTo: evolvesTo, baseLevel: baseLevel ?? this.baseLevel,
    );
  }

  factory TriadCard.fromJson(Map<String, dynamic> json) {
    return TriadCard(
      id: json['id'] as String,
      speciesId: json['speciesId'] as String,
      name: json['name'] as String,
      cardType: json['cardType'] == 'trainer'
          ? TriadCardType.trainer
          : TriadCardType.pokemon,
      rarity: rarityFromString(json['rarity'] as String),
      affinity: json['affinity'] as String,
      values: CardValues.fromJson(json['values'] as Map<String, dynamic>),
      image: json['image'] as String,
      worth: json['worth'] as int? ?? 0,
      cardNumber: json['cardNumber'] as String? ?? '',
      isStarter: json['isStarter'] as bool? ?? false,
      holo: json['holo'] as bool? ?? false,
      shiny: json['shiny'] as bool? ?? false,
      evolvesTo: json['evolvesTo'] as String?,
      baseLevel: json['baseLevel'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TriadCard && other.id == id && other.owner == owner;

  @override
  int get hashCode => Object.hash(id, owner);

  /// Placeholder card used when the repository hasn't loaded yet.
  factory TriadCard.fallback() {
    return const TriadCard(
      id: 'fallback',
      speciesId: '0',
      name: '???',
      cardType: TriadCardType.pokemon,
      rarity: CardRarity.common,
      affinity: 'normal',
      values: CardValues(north: 1, south: 1, east: 1, west: 1),
      image: '',
    );
  }
}
