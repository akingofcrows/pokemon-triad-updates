class CardSet {
  const CardSet({
    required this.id,
    required this.name,
    required this.description,
    required this.cardIds,
  });

  final String id;
  final String name;
  final String description;
  final List<String> cardIds;

  factory CardSet.fromJson(Map<String, dynamic> json) {
    return CardSet(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      cardIds: (json['cardIds'] as List<dynamic>).cast<String>(),
    );
  }
}
