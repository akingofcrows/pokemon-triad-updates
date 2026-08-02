import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/card_set.dart';
import '../models/deck.dart';
import '../models/evolution_chain.dart';
import '../models/evolution_line.dart';
import '../models/npc_trainer.dart';
import '../models/triad_card.dart';

/// Loads and caches the static card pool from assets/data/*.json — the
/// converted output of TTMMO's pokemon_cards.json/sets.json/starter_decks.json
/// (see scripts/convert_ttmmo_data.mjs), plus evolutions.json and npcs.json.
class CardRepository {
  CardRepository._();
  static final CardRepository instance = CardRepository._();

  final Map<String, TriadCard> _cardsById = {};
  List<TriadCard> _allCards = const [];
  List<CardSet> _sets = const [];
  List<Deck> _starterDecks = const [];
  final Map<String, List<EvolutionChain>> _evolutionsByFrom = {};
  final Map<String, EvolutionChain> _evolutionsByTo = {};
  List<NpcTrainer> _npcs = const [];

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;

    final cardsJson =
        jsonDecode(await rootBundle.loadString('assets/data/cards.json'))
            as Map<String, dynamic>;
    _allCards = (cardsJson['cards'] as List<dynamic>)
        .map((e) => TriadCard.fromJson(e as Map<String, dynamic>))
        .toList();
    for (final card in _allCards) {
      _cardsById[card.id] = card;
    }

    final setsJson =
        jsonDecode(await rootBundle.loadString('assets/data/sets.json'))
            as Map<String, dynamic>;
    _sets = (setsJson['sets'] as List<dynamic>)
        .map((e) => CardSet.fromJson(e as Map<String, dynamic>))
        .toList();

    final startersJson = jsonDecode(
      await rootBundle.loadString('assets/data/starter_decks.json'),
    ) as Map<String, dynamic>;
    _starterDecks = (startersJson['decks'] as List<dynamic>).map((e) {
      final map = e as Map<String, dynamic>;
      return Deck(
        id: map['id'] as String,
        name: map['name'] as String,
        cardIds: (map['cards'] as List<dynamic>).cast<String>(),
      );
    }).toList();

    final evolutionsJson = jsonDecode(
      await rootBundle.loadString('assets/data/evolutions.json'),
    ) as Map<String, dynamic>;
    for (final e in evolutionsJson['chains'] as List<dynamic>) {
      final chain = EvolutionChain.fromJson(e as Map<String, dynamic>);
      _evolutionsByFrom.putIfAbsent(chain.from, () => []).add(chain);
      _evolutionsByTo[chain.to] = chain;
    }

    final npcsJson = jsonDecode(
      await rootBundle.loadString('assets/data/npcs.json'),
    ) as Map<String, dynamic>;
    _npcs = (npcsJson['npcs'] as List<dynamic>)
        .map((e) => NpcTrainer.fromJson(e as Map<String, dynamic>))
        .toList();

    _loaded = true;
  }

  List<TriadCard> get allCards => _allCards;
  List<CardSet> get sets => _sets;
  List<Deck> get starterDecks => _starterDecks;
  List<NpcTrainer> get npcs => _npcs;

  TriadCard? cardById(String id) => _cardsById[id];

  /// Resolves a list of card ids to cards, in order, skipping unknown ids.
  List<TriadCard> cardsForIds(List<String> ids) {
    return ids.map((id) => _cardsById[id]).whereType<TriadCard>().toList();
  }

  List<String> get allCardIds => _allCards.map((c) => c.id).toList();

  /// Level-based evolution options for [cardId] — more than one entry means
  /// a branching evolution (e.g. Eevee), each a separate player choice.
  List<EvolutionChain> evolutionsFrom(String cardId) =>
      _evolutionsByFrom[cardId] ?? const [];

  /// The full evolution lineage around [cardId] — see [EvolutionLine].
  EvolutionLine evolutionLineFor(String cardId) {
    final ancestors = <EvolutionStep>[];
    var cur = cardId;
    for (;;) {
      final parent = _evolutionsByTo[cur];
      if (parent == null) break;
      ancestors.insert(0, EvolutionStep(cardId: parent.from, level: parent.level));
      cur = parent.from;
    }

    final descendants = <EvolutionStep>[];
    var branchOptions = const <EvolutionStep>[];
    cur = cardId;
    for (;;) {
      final children = _evolutionsByFrom[cur] ?? const [];
      if (children.isEmpty) break;
      if (children.length > 1) {
        branchOptions = children.map((c) => EvolutionStep(cardId: c.to, level: c.level)).toList();
        break;
      }
      descendants.add(EvolutionStep(cardId: children.first.to, level: children.first.level));
      cur = children.first.to;
    }

    return EvolutionLine(ancestors: ancestors, descendants: descendants, branchOptions: branchOptions);
  }
}
