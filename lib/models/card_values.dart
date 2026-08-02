class CardValues {
  const CardValues({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final int north;
  final int south;
  final int east;
  final int west;

  int get total => north + south + east + west;

  CardValues plusBonus(CardValues bonus) => CardValues(
    north: north + bonus.north,
    south: south + bonus.south,
    east: east + bonus.east,
    west: west + bonus.west,
  );

  /// Caps each directional value at [max] (A = 10).
  CardValues clamped({int max = 10}) => CardValues(
    north: north.clamp(0, max),
    south: south.clamp(0, max),
    east: east.clamp(0, max),
    west: west.clamp(0, max),
  );

  factory CardValues.fromJson(Map<String, dynamic> json) {
    return CardValues(
      north: json['north'] as int,
      south: json['south'] as int,
      east: json['east'] as int,
      west: json['west'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'north': north,
    'south': south,
    'east': east,
    'west': west,
  };
}
