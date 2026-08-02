import 'package:flutter/material.dart';
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

    final allCards = repository.cardsForIds(selectedSet.cardIds);

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

        // Shiny Dex:
        // - ever owned shiny (now or previously) → full color
        // - never owned shiny → dark grey
        if (shinyOnly) {
          if (shinyIds.contains(card.id) || everOwnedShinyCardIds.contains(card.id)) {
            return TriadCardView(card: card.copyWith(shiny: true), size: 100);
          }
          return _greyedCard(card, seen: false);
        }

        // Card Dex:
        // - ever owned (now or previously) → full color
        // - seen but never owned → bright grey
        // - never seen → dark grey
        if (everOwned) return TriadCardView(card: card, size: 100);
        return _greyedCard(card, seen: isSeen);
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
