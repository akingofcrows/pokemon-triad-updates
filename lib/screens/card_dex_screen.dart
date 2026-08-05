import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_set.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

enum _SortMode { number, rarity, type }
enum _DexTab { allCards, shiny }

class CardDexScreen extends StatefulWidget {
  const CardDexScreen({super.key});

  @override
  State<CardDexScreen> createState() => _CardDexScreenState();
}

class _CardDexScreenState extends State<CardDexScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedSetId = 'all';
  _SortMode _sortMode = _SortMode.number;

  // Lazy-built lookup: cardId → list of set names that contain this card
  Map<String, List<String>>? _cardSets;
  // cardId → list of location names where this card appears in encounters
  Map<String, List<String>>? _cardLocations;
  // set ID → booster name
  static const _setToBooster = {
    'field_trip': 'Field Trip Booster',
    'safari_tour': 'Safari Tour Booster',
    'urban_life': 'Urban Life Booster',
    'base': 'Kanto Collection',
    'johto': 'Johto Collection',
  };

  Future<void> _ensureLookups() async {
    if (_cardSets != null && _cardLocations != null) return;

    // Build card → sets lookup
    final sets = CardRepository.instance.sets;
    final cardSets = <String, List<String>>{};
    for (final set in sets) {
      for (final cardId in set.cardIds) {
        cardSets.putIfAbsent(cardId, () => []).add(set.name);
      }
    }
    _cardSets = cardSets;

    // Build card → locations lookup from routes.json
    final cardLocations = <String, List<String>>{};
    try {
      final jsonStr = await rootBundle.loadString('assets/data/routes.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final locations = data['locations'] as List<dynamic>? ?? [];
      for (final loc in locations) {
        final locName = (loc['name'] as String?) ?? '';
        final nodes = loc['nodes'] as List<dynamic>? ?? [];
        for (final node in nodes) {
          final table = node['encounterTable'] as List<dynamic>? ?? [];
          for (final entry in table) {
            final cardId = entry['cardId'] as String?;
            if (cardId != null) {
              cardLocations.putIfAbsent(cardId, () => []).add(locName);
            }
          }
        }
      }
    } catch (_) {}
    _cardLocations = cardLocations;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = CardRepository.instance;
    final profileCtrl = context.watch<PlayerProfileController>();
    final seenCardIds = profileCtrl.seenCardIds;
    final everOwnedCardIds = profileCtrl.everOwnedCardIds;
    final everOwnedShinyCardIds = profileCtrl.everOwnedShinyCardIds;
    final allInstances = profileCtrl.allCardInstances;
    final shinyInstanceIds = allInstances
        .where((inst) => inst.shiny)
        .map((inst) => inst.cardId)
        .toSet();
    final sets = repository.sets;
    final selectedSet = sets.firstWhere(
      (s) => s.id == _selectedSetId,
      orElse: () => sets.first,
    );

    final allCards = _selectedSetId == 'all'
        ? repository.allCards
        : repository.cardsForIds(selectedSet.cardIds);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text('Card Dex'),
        actions: [
          PopupMenuButton<_SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.number, child: Text('Sort by number')),
              PopupMenuItem(value: _SortMode.rarity, child: Text('Sort by rarity')),
              PopupMenuItem(value: _SortMode.type, child: Text('Sort by type')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Card Dex'),
            Tab(text: 'Shiny Dex'),
          ],
        ),
      ),
      body: Column(
        children: [
          _SetSelector(
            sets: sets,
            selectedSetId: _selectedSetId,
            onChanged: (id) => setState(() => _selectedSetId = id),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  '${allCards.length} cards',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (_, __) {
                    if (_tabController.index == 1) {
                      // Shiny Dex tab — count ever-owned shinies
                      final shinyCount = allCards.where((c) => everOwnedShinyCardIds.contains(c.id)).length;
                      return Text(
                        'Shiny: $shinyCount/${allCards.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber),
                      );
                    }
                    // Card Dex tab — count cards ever owned
                    final owned = allCards.where((c) => everOwnedCardIds.contains(c.id)).length;
                    return Text(
                      'Owned: $owned/${allCards.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.amber),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCardGrid(allCards, seenCardIds: seenCardIds, everOwnedCardIds: everOwnedCardIds, ownedOnly: false, shinyOnly: false),
                _buildCardGrid(allCards, seenCardIds: seenCardIds, everOwnedCardIds: everOwnedCardIds, ownedOnly: false, shinyOnly: true, shinyIds: shinyInstanceIds, everOwnedShinyCardIds: everOwnedShinyCardIds),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGrid(
    List<TriadCard> cards, {
    Set<String> seenCardIds = const {},
    Set<String> everOwnedCardIds = const {},
    required bool ownedOnly,
    required bool shinyOnly,
    Set<String> shinyIds = const {},
    Set<String> everOwnedShinyCardIds = const {},
  }) {
    final sorted = _sortedCards(cards);

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final card = sorted[index];
        final everOwned = everOwnedCardIds.contains(card.id);
        final isSeen = seenCardIds.contains(card.id);

        Widget cardWidget;
        bool isUnlocked;
        // Shiny Dex:
        // - ever owned shiny (now or previously) → full color
        // - never owned shiny → dark grey
        if (shinyOnly) {
          final hasShiny = shinyIds.contains(card.id) || everOwnedShinyCardIds.contains(card.id);
          isUnlocked = hasShiny;
          if (hasShiny) {
            cardWidget = TriadCardView(card: card.copyWith(shiny: true), size: 100);
          } else {
            cardWidget = _greyedCard(card, seen: false);
          }
        } else {
          // Card Dex:
          // - ever owned (now or previously) → full color
          // - seen but never owned → bright grey
          // - never seen → dark grey
          // Trainers are always unlocked since they aren't wild encounters.
          isUnlocked = everOwned || isSeen || card.cardType == TriadCardType.trainer;
          if (everOwned) {
            cardWidget = TriadCardView(card: card, size: 100);
          } else {
            cardWidget = _greyedCard(card, seen: isSeen);
          }
        }

        return GestureDetector(
          onTap: () => _showCardInfo(context, card, isUnlocked: isUnlocked),
          child: cardWidget,
        );
      },
    );
  }

  /// [seen] = true  → brighter grey (encountered but not currently owned).
  /// [seen] = false → dark grey (never seen at all).
  Widget _greyedCard(TriadCard card, {bool seen = false}) {
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        seen ? 0.55 : 0.33, seen ? 0.70 : 0.59, seen ? 0.35 : 0.11, 0, 0,
        seen ? 0.55 : 0.33, seen ? 0.70 : 0.59, seen ? 0.35 : 0.11, 0, 0,
        seen ? 0.55 : 0.33, seen ? 0.70 : 0.59, seen ? 0.35 : 0.11, 0, 0,
        0,    0,    0,    1, 0,
      ]),
      child: Opacity(
        opacity: seen ? 0.60 : 0.35,
        child: TriadCardView(card: card, size: 100),
      ),
    );
  }

  List<TriadCard> _sortedCards(List<TriadCard> cards) {
    final sorted = cards.toList();
    switch (_sortMode) {
      case _SortMode.number:
        sorted.sort((a, b) {
          final typeCmp = _cardTypeRank(a).compareTo(_cardTypeRank(b));
          if (typeCmp != 0) return typeCmp;
          return _compareNumberParts(a.cardNumber, b.cardNumber);
        });
      case _SortMode.rarity:
        sorted.sort((a, b) => a.rarity.index.compareTo(b.rarity.index));
      case _SortMode.type:
        sorted.sort((a, b) => a.affinity.compareTo(b.affinity));
    }
    return sorted;
  }

  int _cardTypeRank(TriadCard card) => card.cardType == TriadCardType.pokemon ? 0 : 1;

  int _compareNumberParts(String a, String b) {
    final partsA = a.split(RegExp(r'[^0-9]+')).where((p) => p.isNotEmpty).map(int.parse).toList();
    final partsB = b.split(RegExp(r'[^0-9]+')).where((p) => p.isNotEmpty).map(int.parse).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final cmp = partsA[i].compareTo(partsB[i]);
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }

  void _showCardInfo(BuildContext context, TriadCard card, {bool isUnlocked = true}) {
    if (!isUnlocked) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'UNKNOWN',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You haven\'t encountered this Pokémon yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close', style: TextStyle(color: Colors.amber)),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    _ensureLookups().then((_) {
      if (!mounted) return;
      final cardSets = _cardSets?[card.id] ?? <String>[];
      final cardLocations = _cardLocations?[card.id] ?? <String>[];

      // Find which boosters this card can come from (matching set IDs)
      final boosterNames = <String>{};
      final sets = CardRepository.instance.sets;
      for (final set in sets) {
        if (set.cardIds.contains(card.id)) {
          final boosterName = _setToBooster[set.id] ?? set.name;
          boosterNames.add(boosterName);
        }
      }

      // Evolution line (calculated inside _buildEvoChain)

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with card image
                Center(
                  child: TriadCardView(card: card, size: 120),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${card.name}  #${card.cardNumber}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '${_capitalize(card.rarity.name)} · ${_capitalize(card.affinity)}${card.cardType == TriadCardType.trainer ? " · Trainer" : ""}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                ),
                const SizedBox(height: 16),
                // Pokédex entry (fetched from PokéAPI)
                if (card.cardType == TriadCardType.pokemon)
                  _PokedexEntry(speciesId: card.speciesId),
                // Evolution line
                const SizedBox(height: 12),
                _buildEvoChain(card),
                // Found in boosters
                if (boosterNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Found in Boosters'),
                  const SizedBox(height: 4),
                  ...boosterNames.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.card_giftcard, size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(b, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  )),
                ],
                // Found in locations
                if (cardLocations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Found in Locations'),
                  const SizedBox(height: 8),
                  _buildLocationGrid(cardLocations),
                ],
                // Sets
                if (cardSets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Card Sets'),
                  const SizedBox(height: 4),
                  ...cardSets.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.collections_bookmark, size: 14, color: Colors.blueAccent),
                        const SizedBox(width: 6),
                        Text(s, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  )),
                ],
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close', style: TextStyle(color: Colors.amber)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildEvoChain(TriadCard card) {
    final line = CardRepository.instance.evolutionLineFor(card.id);
    if (line.isStandalone) return const SizedBox.shrink();

    final nodes = <Widget>[];
    final repository = CardRepository.instance;

    Widget node(String cardId, {bool highlight = false}) {
      final c = repository.cardById(cardId);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: highlight ? Colors.amber.withValues(alpha: 0.15) : Colors.white10,
              borderRadius: BorderRadius.circular(6),
              border: highlight
                  ? Border.all(color: Colors.amber, width: 1.5)
                  : Border.all(color: Colors.white24, width: 1),
            ),
            child: c != null
                ? TriadCardView(card: c, size: 40)
                : const Icon(Icons.help_outline, color: Colors.white24, size: 20),
          ),
          const SizedBox(height: 3),
          Text(c?.name ?? cardId, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      );
    }

    Widget arrow(int level) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Lv.$level', style: const TextStyle(fontSize: 8, color: Colors.amber)),
            const Icon(Icons.arrow_forward, size: 12),
          ],
        ),
      );
    }

    for (final step in line.ancestors) {
      nodes.add(node(step.cardId));
      nodes.add(arrow(step.level));
    }
    nodes.add(node(card.id, highlight: true));
    for (final step in line.descendants) {
      nodes.add(arrow(step.level));
      nodes.add(node(step.cardId));
    }
    for (final branch in line.branchOptions) {
      nodes.add(arrow(branch.level));
      nodes.add(node(branch.cardId));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Evolution Line'),
        const SizedBox(height: 8),
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: nodes),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildLocationGrid(List<String> locations) {
    const columns = 3;
    final rows = <List<String>>[];
    for (var i = 0; i < locations.length; i += columns) {
      rows.add(locations.sublist(i, (i + columns).clamp(0, locations.length)));
    }
    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              for (var i = 0; i < columns; i++)
                Expanded(
                  child: i < row.length
                      ? Row(
                          children: [
                            const Icon(Icons.location_on, size: 12, color: Colors.greenAccent),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(row[i], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.amber,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Inline set selector (same pattern as CollectionScreen).
class _SetSelector extends StatelessWidget {
  const _SetSelector({
    required this.sets,
    required this.selectedSetId,
    required this.onChanged,
  });

  final List<CardSet> sets;
  final String selectedSetId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: sets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final set = sets[index];
          final selected = set.id == selectedSetId;
          return ChoiceChip(
            label: Text(set.name, style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 12)),
            selected: selected,
            selectedColor: Colors.amber,
            backgroundColor: Colors.grey[850],
            onSelected: (_) => onChanged(set.id),
          );
        },
      ),
    );
  }
}

/// Fetches and displays Pokédex data from PokéAPI for a given species.
class _PokedexEntry extends StatefulWidget {
  const _PokedexEntry({required this.speciesId});
  final String speciesId;

  @override
  State<_PokedexEntry> createState() => _PokedexEntryState();
}

class _PokedexEntryState extends State<_PokedexEntry> {
  String? _flavorText;
  String? _genus;
  String? _habitat;
  String? _height;
  String? _weight;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final species = widget.speciesId.toLowerCase().replaceAll(' ', '-');
      final results = await Future.wait([
        http.get(Uri.parse('https://pokeapi.co/api/v2/pokemon-species/$species')),
        http.get(Uri.parse('https://pokeapi.co/api/v2/pokemon/$species')),
      ]);

      // Parse species data
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body) as Map<String, dynamic>;
        // English flavor text
        final entries = data['flavor_text_entries'] as List<dynamic>? ?? [];
        for (final e in entries) {
          final lang = (e['language'] as Map<String, dynamic>?)?['name'];
          if (lang == 'en') {
            var text = (e['flavor_text'] as String?) ?? '';
            // Clean up newlines and form feeds
            _flavorText = text.replaceAll('\n', ' ').replaceAll('\f', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
            break;
          }
        }
        // Genus (category)
        final genera = data['genera'] as List<dynamic>? ?? [];
        for (final g in genera) {
          final lang = (g['language'] as Map<String, dynamic>?)?['name'];
          if (lang == 'en') {
            _genus = (g['genus'] as String?) ?? '';
            break;
          }
        }
        // Habitat
        final hab = data['habitat'] as Map<String, dynamic>?;
        _habitat = hab?['name'] as String?;
      }

      // Parse pokemon data (height/weight)
      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body) as Map<String, dynamic>;
        final h = (data['height'] as num?) ?? 0;
        final w = (data['weight'] as num?) ?? 0;
        _height = '${(h / 10).toStringAsFixed(1)} m';
        _weight = '${(w / 10).toStringAsFixed(1)} kg';
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Flavor text
        if (_flavorText != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              _flavorText!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Info rows
        if (_genus != null)
          _dexRow('Category', _genus!),
        if (_height != null)
          _dexRow('Height', _height!),
        if (_weight != null)
          _dexRow('Weight', _weight!),
        if (_habitat != null)
          _dexRow('Habitat', _capitalizeFirst(_habitat!)),
      ],
    );
  }

  Widget _dexRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
