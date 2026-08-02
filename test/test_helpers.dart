import 'package:pokemon_triad/models/card_owner.dart';
import 'package:pokemon_triad/models/card_values.dart';
import 'package:pokemon_triad/models/triad_card.dart';

TriadCard makeTestCard({
  required String id,
  required int north,
  required int south,
  required int east,
  required int west,
  CardOwner owner = CardOwner.neutral,
}) {
  return TriadCard(
    id: id,
    speciesId: id,
    name: id,
    cardType: TriadCardType.pokemon,
    rarity: CardRarity.common,
    affinity: 'normal',
    values: CardValues(north: north, south: south, east: east, west: west),
    image: 'assets/pokemon/$id.png',
    owner: owner,
  );
}
