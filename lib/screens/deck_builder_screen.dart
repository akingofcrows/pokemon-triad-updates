import 'dart:ui';

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
      _workingCardIds = <String>[...deck.cardIds];
      _workingInstanceIds = deck.instanceIds != null
          ? <int?>[...deck.instanceIds!]
          : List.filled(deck.cardIds.length, null, growable: true);
      _nameController.text = deck.name;
    });
  }

  void _toggleCard(String cardId, int instanceId) {
    setState(() {
      // Find by exact instance ID match
      final idx = instanceId > 0
          ? _workingInstanceIds.indexOf(instanceId)
          : -1;
      if (idx >= 0) {
        _workingCardIds.removeAt(idx);
        _workingInstanceIds.removeAt(idx);
      } else if (_workingCardIds.length < kDeckSize) {
        _workingCardIds.add(cardId);
        _workingInstanceIds.add(instanceId > 0 ? instanceId : null);
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
      boxImage: _editing!.boxImage,
      featuredCardIndex: _editing!.featuredCardIndex,
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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Decks'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewDeck,
        backgroundColor: const Color(0xFF4CAF50),
        icon: const Icon(Icons.add),
        label: const Text('New Deck'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Image.asset('assets/locations/oakslab.png', fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.40),
                  colorBlendMode: BlendMode.darken),
            ),
          ),
          profile.decks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.style, color: Colors.white.withValues(alpha: 0.2), size: 64),
                  const SizedBox(height: 16),
                  Text('No decks yet',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('Create one to get started!',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
                ],
              ),
            )
          : GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 16 + kToolbarHeight + MediaQuery.of(context).padding.top, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 1.05,
              ),
              itemCount: profile.decks.length,
              itemBuilder: (context, index) {
                final deck = profile.decks[index];
                final isDefault = profile.defaultDeckId == deck.id;
                final boxImg = deck.boxImage ?? 'field_deck';
                final fi = (deck.featuredCardIndex ?? 0).clamp(0, deck.cardIds.length - 1);
                final featuredId = deck.cardIds.isNotEmpty ? deck.cardIds[fi] : null;
                final featuredCard = featuredId != null ? CardRepository.instance.cardById(featuredId) : null;

                return GestureDetector(
                  onTap: () {
                    context.read<PlayerProfileController>().setDefaultDeck(deck.id);
                    Navigator.of(context).pop();
                  },
                  onLongPress: () => _showDeckMenu(context, deck),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Deck box — anchored to bottom, centered
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Center(
                          child: Image.asset('assets/images/Booster Pack/$boxImg.png', width: 120, height: 85, fit: BoxFit.contain),
                        ),
                      ),
                      // Featured card
                      if (featuredCard != null)
                        Builder(builder: (_) {
                          final ctrl = context.read<PlayerProfileController>();
                          CardGrowth? g;
                          final instId = deck.instanceIds != null && fi < deck.instanceIds!.length
                              ? deck.instanceIds![fi] : null;
                          if (instId != null && instId > 0) {
                            g = ctrl.allCardInstances.where((inst) => inst.instanceId == instId).firstOrNull;
                          }
                          // Only use instance-specific; don't fall back to general pool
                          return Positioned(
                            left: 0,
                            right: 0,
                            top: 57,
                            child: Center(
                              child: Transform.translate(
                                offset: const Offset(-4, 2),
                                child: Transform.rotate(
                                  angle: -0.08,
                                  child: SizedBox(
                                  width: 44, height: 44,
                                  child: TriadCardView(card: featuredCard, size: 44, growth: g),
                                ),
                              ),
                              ),
                            ),
                          );
                        }),
                      // Deck name on box
                      Positioned(
                        top: 38,
                        left: 0,
                        right: 4,
                        child: Text(
                            deck.name.length > 12 ? '${deck.name.substring(0, 12)}…' : deck.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'PowerGreen', shadows: [Shadow(color: boxImg == 'field_deck' ? const Color(0xFF169A3D) : Colors.black87, blurRadius: 3, offset: const Offset(1, 1))])),
                      ),
                      // Default star
                      if (isDefault)
                        const Positioned(
                          top: 19, left: 14,
                          child: Icon(Icons.star, color: Color(0xFFC9A44C), size: 14),
                        ),
                      // Three-dot menu
                      Positioned(
                        top: 4, right: -4,
                        child: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.6), size: 18),
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                          onSelected: (action) {
                            switch (action) {
                              case 'edit': _startEditDeck(deck);
                              case 'rename': _showRenameDialog(context, deck);
                              case 'delete': context.read<PlayerProfileController>().deleteDeck(deck.id);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showDeckMenu(BuildContext context, Deck deck) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text('Edit', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _startEditDeck(deck); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: Colors.white70),
              title: const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _showRenameDialog(context, deck); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                context.read<PlayerProfileController>().deleteDeck(deck.id);
              },
            ),
          ],
        ),
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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _editing = null),
        ),
        title: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Deck name',
            hintStyle: TextStyle(color: Colors.white30),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isValid ? _save : null,
            child: Text('Save',
                style: TextStyle(
                  color: isValid ? const Color(0xFF4CAF50) : Colors.white30,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Image.asset('assets/locations/oakslab.png', fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.40),
                  colorBlendMode: BlendMode.darken),
            ),
          ),
          Column(
        children: [
          SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top),
          // Deck preview — box image with featured card, tap to change box
          Center(
            child: SizedBox(
              height: 140,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: _showBoxPicker,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Image.asset('assets/images/Booster Pack/${_editing?.boxImage ?? 'field_deck'}.png', fit: BoxFit.contain),
                    ),
                  ),
                  if (selectedCards.isNotEmpty) ...[
                    Builder(builder: (ctx) {
                      final fi = ((_editing?.featuredCardIndex) ?? 0).clamp(0, selectedCards.length - 1);
                      final c = context.read<PlayerProfileController>();
                      final instId = fi < _workingInstanceIds.length ? _workingInstanceIds[fi] : null;
                      final g = (instId != null && instId > 0)
                          ? c.allCardInstances.where((inst) => inst.instanceId == instId).firstOrNull
                          : null;
                      return Transform.translate(
                        offset: const Offset(-5, 20),
                        child: Transform.rotate(
                          angle: -0.05,
                          child: SizedBox(
                            width: 72, height: 72,
                            child: TriadCardView(key: ValueKey('prev_${selectedCards[fi].id}_${g?.instanceId ?? 0}'), card: selectedCards[fi], size: 72, growth: g),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF333333), width: 1),
              ),
            ),
            child: Text(
              '${_workingCardIds.length}/$kDeckSize selected • Strength $strength',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isValid ? const Color(0xFF4CAF50) : Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
          Container(
              height: 80,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFF333333), width: 1),
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(kDeckSize, (index) {
                  final hasCard = index < _workingCardIds.length;
                  if (!hasCard) {
                    return Container(
                      width: 60, height: 60,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                    );
                  }
                  final cardId = _workingCardIds[index];
                  final card = CardRepository.instance.cardById(cardId);
                  if (card == null) return const SizedBox.shrink();
                  final instId = index < _workingInstanceIds.length ? _workingInstanceIds[index] : null;
                  CardGrowth? growth;
                  if (instId != null) {
                    growth = instances.where((inst) => inst.instanceId == instId).firstOrNull;
                  }
                  // Only use instance-specific growth
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleCard(cardId, instId ?? 0),
                    onLongPress: () => setState(() {
                      _editing = _editing?.copyWith(featuredCardIndex: index);
                    }),
                    child: Stack(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: TriadCardView(card: card, size: 60, growth: growth, selected: true),
                        ),
                        if ((_editing?.featuredCardIndex) == index)
                          const Positioned(
                            top: 2, right: 2,
                            child: Icon(Icons.star, color: Color(0xFFC9A44C), size: 16),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            ),
            ),
          const Divider(height: 1, color: Color(0xFF333333)),
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
                final selected = inst.instanceId != null
                    ? _workingInstanceIds.contains(inst.instanceId)
                    : _workingCardIds.contains(inst.cardId);
                final full = !selected && _workingCardIds.length >= kDeckSize;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleCard(inst.cardId, inst.instanceId ?? 0),
                  child: Opacity(
                    opacity: (full || selected) ? 0.4 : 1,
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
        ],
      ),
    );
  }

  void _showBoxPicker() {
    const boxes = [
      {'key': 'field_deck', 'label': 'Field'},
      {'key': 'safari_deck', 'label': 'Safari'},
      {'key': 'urban_deck', 'label': 'Urban'},
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Deck Box', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.2,
            ),
            itemCount: boxes.length,
            itemBuilder: (_, i) {
              final box = boxes[i];
              final selected = _editing?.boxImage == box['key'];
              return GestureDetector(
                onTap: () {
                  setState(() => _editing = _editing!.copyWith(boxImage: box['key'] as String));
                  Navigator.pop(ctx);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? const Color(0xFFC9A44C) : const Color(0xFF333333), width: selected ? 2 : 1),
                    color: const Color(0xFF2A2A2A),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/Booster Pack/${box['key']}.png', width: 70, height: 50, fit: BoxFit.contain),
                      const SizedBox(height: 4),
                      Text(box['label'] as String, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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
