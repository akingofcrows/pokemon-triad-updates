import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_growth.dart';
import '../models/deck.dart';
import '../models/player_profile.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../widgets/pokemon_icon.dart';
import '../widgets/triad_card_view.dart';

class DeckBuilderScreen extends StatefulWidget {
  const DeckBuilderScreen({super.key});

  @override
  State<DeckBuilderScreen> createState() => _DeckBuilderScreenState();
}

class _DeckBuilderScreenState extends State<DeckBuilderScreen> {
  Deck? _editing;
  /// Instance IDs for each slot, matching [_workingCardIds] positions.
  List<String> _workingCardIds = [];
  List<int?> _workingInstanceIds = [];
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startNewDeck() {
    setState(() {
      _editing = Deck(
        id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
        name: 'New Deck',
        cardIds: const [],
      );
      _workingCardIds = [];
      _workingInstanceIds = [];
      _nameController.text = 'New Deck';
    });
  }

  void _startEditDeck(Deck deck) {
    setState(() {
      _editing = deck;
      _workingCardIds = List.of(deck.cardIds);
      _workingInstanceIds = deck.instanceIds != null
          ? List.of(deck.instanceIds!)
          : List.filled(deck.cardIds.length, null);
      _nameController.text = deck.name;
    });
  }

  void _toggleCard(String cardId, int instanceId) {
    setState(() {
      // Find if this specific INSTANCE is already selected
      final idx = _workingInstanceIds.indexOf(instanceId);
      if (idx >= 0) {
        _workingCardIds.removeAt(idx);
        _workingInstanceIds.removeAt(idx);
      } else if (_workingCardIds.length < kDeckSize) {
        _workingCardIds.add(cardId);
        _workingInstanceIds.add(instanceId);
      }
    });
  }

  Future<void> _save() async {
    final controller = context.read<PlayerProfileController>();
    final name = _nameController.text.trim();
    // Build instanceIds list — only include if we have actual instance picks
    final hasInstances = _workingInstanceIds.any((id) => id != null);
    final deck = Deck(
      id: _editing!.id,
      name: name.isEmpty ? 'Deck' : name,
      cardIds: _workingCardIds,
      instanceIds: _workingInstanceIds,
    );
    await controller.saveDeck(deck);
    if (mounted) setState(() => _editing = null);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerProfileController>();
    final profile = controller.profile;
    return _editing == null ? _buildListView(context, profile) : _buildEditView(context);
  }

  Widget _buildListView(BuildContext context, PlayerProfile profile) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewDeck,
        icon: const Icon(Icons.add),
        label: const Text('New Deck'),
      ),
      body: profile.decks.isEmpty
          ? const Center(child: Text('No decks yet. Create one to get started.'))
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              itemCount: profile.decks.length,
              itemBuilder: (context, index) {
                final deck = profile.decks[index];
                final cards = CardRepository.instance.cardsForIds(deck.cardIds);
                final strength = cards.fold<int>(0, (sum, c) => sum + c.values.total);
                final isDefault = profile.defaultDeckId == deck.id;
                return Card(
                  color: Colors.grey[900],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isDefault)
                              const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(deck.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                            Text('$strength str', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white60),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit Cards')),
                                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                const PopupMenuItem(value: 'default', child: Text('Set as Default')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                              onSelected: (action) {
                                switch (action) {
                                  case 'edit':
                                    _startEditDeck(deck);
                                  case 'rename':
                                    _showRenameDialog(context, deck);
                                  case 'default':
                                    context.read<PlayerProfileController>().setDefaultDeck(deck.id);
                                  case 'delete':
                                    context.read<PlayerProfileController>().deleteDeck(deck.id);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: cards.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 2),
                            itemBuilder: (_, i) {
                              final c = cards[i];
                              // Use instance-specific growth if available
                              final instId = deck.instanceIds != null && i < deck.instanceIds!.length
                                  ? deck.instanceIds![i]
                                  : null;
                              CardGrowth? g;
                              if (instId != null) {
                                g = context.read<PlayerProfileController>().allCardInstances
                                    .where((inst) => inst.instanceId == instId)
                                    .firstOrNull;
                              }
                              g ??= context.read<PlayerProfileController>().cardGrowth[c.id];
                              return TriadCardView(card: c, size: 48, growth: g);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showRenameDialog(BuildContext context, Deck deck) {
    final ctrl = TextEditingController(text: deck.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Deck'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<PlayerProfileController>().saveDeck(deck.copyWith(name: name));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditView(BuildContext context) {
    final controller = context.watch<PlayerProfileController>();
    // Filter to only valid instances (cards that exist in the repository)
    final allInstances = controller.allCardInstances;
    final instances = allInstances
        .where((inst) => CardRepository.instance.cardById(inst.cardId) != null)
        .toList();
    final selectedCards = CardRepository.instance.cardsForIds(_workingCardIds);
    final strength = selectedCards.fold<int>(0, (sum, c) => sum + c.values.total);
    final isValid = _workingCardIds.length == kDeckSize;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _editing = null),
        ),
        title: TextField(
          controller: _nameController,
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Deck name'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          TextButton(onPressed: isValid ? _save : null, child: const Text('Save')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('${_workingCardIds.length}/$kDeckSize selected · strength $strength',
                style: const TextStyle(color: Colors.white70)),
          ),
          if (_workingCardIds.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _workingCardIds.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final cardId = _workingCardIds[index];
                  final card = CardRepository.instance.cardById(cardId);
                  if (card == null) return const SizedBox.shrink();
                  final instId = index < _workingInstanceIds.length ? _workingInstanceIds[index] : null;
                  CardGrowth? growth;
                  if (instId != null) {
                    growth = instances.where((inst) => inst.instanceId == instId).firstOrNull;
                  }
                  growth ??= controller.cardGrowth[cardId];
                  return GestureDetector(
                    onTap: () => _toggleCard(cardId, instId ?? 0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TriadCardView(card: card, size: 60, growth: growth, selected: true),
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: instances.length,
              itemBuilder: (context, index) {
                final inst = instances[index];
                final card = CardRepository.instance.cardById(inst.cardId)!;
                // Selected if instance ID matches, or fall back to card ID match
                final selected = _workingInstanceIds.contains(inst.instanceId) ||
                    (inst.instanceId == null && _workingCardIds.contains(inst.cardId));
                final full = !selected && _workingCardIds.length >= kDeckSize;
                return GestureDetector(
                  onTap: () => _toggleCard(inst.cardId, inst.instanceId ?? 0),
                  child: Opacity(
                    opacity: full ? 0.4 : 1,
                    child: Stack(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: TriadCardView(card: card, size: 100, growth: inst, selected: selected),
                        ),
                        if (card.cardType == TriadCardType.pokemon)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: _levelBadge(inst.level),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _levelBadge(int level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(1, 1)),
          ],
        ),
      ),
    );
  }
}
