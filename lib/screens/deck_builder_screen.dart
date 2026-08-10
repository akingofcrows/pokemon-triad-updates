import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_growth.dart';
import '../models/condition.dart';
import '../models/deck.dart';
import '../models/player_profile.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
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
  String _sortField = 'number';
  bool _sortAscending = true;
  CardRarity? _rarityFilter;
  String? _typeFilter;
  bool _shinyFilter = false;

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

  /// Guards the card-picker grid: Unusable cards can be removed from a deck
  /// freely, but cannot be newly added (GDD §21).
  void _onGridCardTap(CardGrowth inst) {
    final alreadySelected = inst.instanceId != null
        ? _workingInstanceIds.contains(inst.instanceId)
        : _workingCardIds.contains(inst.cardId);
    if (!alreadySelected && inst.conditionTier == ConditionTier.unusable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This card is Unusable — restore it at a Pokémon Center first.'),
        ),
      );
      return;
    }
    _toggleCard(inst.cardId, inst.instanceId ?? 0);
  }

  void _toggleCard(String cardId, int instanceId) {
    setState(() {
      // Find by instance ID first
      int idx = -1;
      if (instanceId > 0) {
        idx = _workingInstanceIds.indexOf(instanceId);
        // If we have an instance ID and it's not found, this is a new card to add
        if (idx < 0) {
          if (_workingCardIds.length < kDeckSize) {
            _workingCardIds.add(cardId);
            _workingInstanceIds.add(instanceId);
          }
          return;
        }
      } else {
        idx = _workingCardIds.indexOf(cardId);
      }
      if (idx >= 0) {
        _workingCardIds.removeAt(idx);
        _workingInstanceIds.removeAt(idx);
      } else if (_workingCardIds.length < kDeckSize) {
        _workingCardIds.add(cardId);
        _workingInstanceIds.add(null);
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
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(
        backgroundColor: const Color(0xFF282A30),
        title: const Text('Decks'),
        elevation: 0,
      ),
      body: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemCount: profile.decks.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _BuildNewTile(onTap: _startNewDeck);
                }
                final deck = profile.decks[index - 1];
                final isDefault = profile.defaultDeckId == deck.id;
                final boxImg = deck.boxImage ?? 'field_deck';
                final fi = (deck.featuredCardIndex ?? 0).clamp(0, deck.cardIds.length - 1);
                final featuredId = deck.cardIds.isNotEmpty ? deck.cardIds[fi] : null;
                final featuredCard = featuredId != null ? CardRepository.instance.cardById(featuredId) : null;

                return _DeckTile(
                  deck: deck,
                  isDefault: isDefault,
                  boxImg: boxImg,
                  featuredCard: featuredCard,
                  featuredIndex: fi,
                  onTap: () async {
                    context.read<PlayerProfileController>().setDefaultDeck(deck.id);
                    Navigator.of(context).pop();
                  },
                  onLongPress: () => _showDeckMenu(context, deck),
                  onMenuAction: (action) {
                    switch (action) {
                      case 'edit': _startEditDeck(deck);
                      case 'rename': _showRenameDialog(context, deck);
                      case 'delete': context.read<PlayerProfileController>().deleteDeck(deck.id);
                    }
                  },
                );
              },
            ),
    );
  }

  void _showDeckMenu(BuildContext context, Deck deck) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF282A30),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white54),
              title: const Text('Edit', style: TextStyle(color: Colors.white70)),
              onTap: () { Navigator.pop(ctx); _startEditDeck(deck); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline, color: Colors.white54),
              title: const Text('Rename', style: TextStyle(color: Colors.white70)),
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
        backgroundColor: const Color(0xFF282A30),
        title: const Text('Rename Deck', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Deck name',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF444444))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF4CAF50))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                context.read<PlayerProfileController>().saveDeck(deck.copyWith(name: name));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFF4CAF50))),
          ),
        ],
      ),
    );
  }

  static List<Color> _gradientForBox(String? boxImg) {
    const bg = Color(0xFF282A30);
    switch (boxImg) {
      case 'field_deck':
        return const [bg, Color(0xFF5CBF60)];
      case 'safari_deck':
        return const [bg, Color(0xFFE07030)];
      case 'urban_deck':
        return const [bg, Color(0xFF4A8ABC)];
      default:
        return const [bg, Color(0xFF526170)];
    }
  }

  Widget _buildEditView(BuildContext context) {
    final controller = context.watch<PlayerProfileController>();
    final allInstances = controller.allCardInstances;
    final instances = allInstances
        .where((inst) => CardRepository.instance.cardById(inst.cardId) != null)
        .toList();
    _sortInstances(instances);
    final selectedCards = CardRepository.instance.cardsForIds(_workingCardIds);
    final unusableCount = _workingInstanceIds.where((id) {
      if (id == null) return false;
      final inst = instances.where((i) => i.instanceId == id).firstOrNull;
      return inst?.conditionTier == ConditionTier.unusable;
    }).length;
    final isValid = _workingCardIds.length == kDeckSize && unusableCount == 0;

    return Scaffold(
      backgroundColor: const Color(0xFF282A30),
      body: Stack(
        children: [
          // Diagonal cut background
          Positioned.fill(
            child: ClipPath(
              clipper: _DiagonalTopClipper(),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.topRight,
                    colors: _gradientForBox(_editing?.boxImage),
                  ),
                ),
              ),
            ),
          ),
          // Deck box icon watermark in the diagonal cut — same treatment as
          // a shop card's type icon watermark, sized up for this full-screen
          // header so it still reads behind the top bar controls.
          if (deckBoxIconAsset(_editing?.boxImage) != null)
            Positioned(
              top: 0,
              left: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.22,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color(0xFFB0B0B8),
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      deckBoxIconAsset(_editing?.boxImage)!,
                      width: 140,
                      height: 140,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          // Content
          Column(
            children: [
              Expanded(
                child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                // Top bar: back arrow | text field with pencil | ... menu
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white70),
                        onPressed: () {
                          if (_workingCardIds.isNotEmpty) _save();
                          setState(() => _editing = null);
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1C20),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _nameController,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Deck name',
                                    hintStyle: TextStyle(color: Colors.white30),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              Icon(Icons.edit, color: Colors.white.withValues(alpha: 0.3), size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz, color: Colors.white.withValues(alpha: 0.6), size: 22),
                        color: const Color(0xFF282A30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (action) {
                          switch (action) {
                            case 'delete':
                              context.read<PlayerProfileController>().deleteDeck(_editing!.id);
                              setState(() => _editing = null);
                            case 'view':
                              // TODO: View all cards
                            case 'copy':
                              _duplicateDeck();
                            case 'share':
                              // TODO: Share deck
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'delete', child: Text('Delete this Deck', style: TextStyle(color: Colors.redAccent))),
                          const PopupMenuItem(value: 'view', child: Text('View All Cards in Deck', style: TextStyle(color: Colors.white70))),
                          const PopupMenuItem(value: 'copy', child: Text('Copy this Deck', style: TextStyle(color: Colors.white70))),
                          const PopupMenuItem(value: 'share', child: Text('Share this Deck', style: TextStyle(color: Colors.white70))),
                        ],
                      ),
                    ],
                  ),
                ),
                // Deck preview
                Center(
                  child: SizedBox(
                    height: 130,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Image.asset('assets/images/Booster Pack/${_editing?.boxImage ?? 'field_deck'}.png', fit: BoxFit.contain),
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
                              offset: const Offset(-5, 16),
                              child: SizedBox(
                                width: 64, height: 64,
                                child: TriadCardView(key: ValueKey('prev_${selectedCards[fi].id}_${g?.instanceId ?? 0}'), card: selectedCards[fi], size: 64, growth: g),
                              ),
                            );
                          }),
                        ],
                        // Change button overlay
                        Positioned(
                          bottom: 0,
                          right: -10,
                          child: OutlinedButton(
                            onPressed: _showBoxPicker,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF74777F)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            ),
                            child: const Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Counter badge
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1A1C20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.style, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${_workingCardIds.length}/$kDeckSize',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Selected cards row
                Container(
                  height: 76,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
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
                if (unusableCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFE53935), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'DECK NOT READY — $unusableCount card${unusableCount == 1 ? '' : 's'} '
                            'Unusable. Swap it out or restore it at a Pokémon Center.',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Sort bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.sort, color: Colors.white38, size: 16),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: 'Name',
                        active: _sortField == 'name',
                        trailing: _sortField == 'name' ? (_sortAscending ? '↑' : '↓') : null,
                        onTap: () => setState(() {
                          if (_sortField == 'name') { _sortAscending = !_sortAscending; } else { _sortField = 'name'; _sortAscending = true; }
                        }),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: 'Number',
                        active: _sortField == 'number',
                        trailing: _sortField == 'number' ? (_sortAscending ? '↑' : '↓') : null,
                        onTap: () => setState(() {
                          if (_sortField == 'number') { _sortAscending = !_sortAscending; } else { _sortField = 'number'; _sortAscending = true; }
                        }),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: 'Level',
                        active: _sortField == 'level',
                        trailing: _sortField == 'level' ? (_sortAscending ? '↑' : '↓') : null,
                        onTap: () => setState(() {
                          if (_sortField == 'level') { _sortAscending = !_sortAscending; } else { _sortField = 'level'; _sortAscending = true; }
                        }),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: 'Condition',
                        active: _sortField == 'condition',
                        trailing: _sortField == 'condition' ? (_sortAscending ? '↑' : '↓') : null,
                        onTap: () => setState(() {
                          if (_sortField == 'condition') { _sortAscending = !_sortAscending; } else { _sortField = 'condition'; _sortAscending = true; }
                        }),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: 'Cnd',
                        active: _sortField == 'condition',
                        trailing: _sortField == 'condition' ? (_sortAscending ? '↑' : '↓') : null,
                        onTap: () => setState(() {
                          if (_sortField == 'condition') { _sortAscending = !_sortAscending; } else { _sortField = 'condition'; _sortAscending = false; }
                        }),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: _rarityFilter != null ? _capitalize(_rarityFilter!.name) : 'Rarity',
                        active: _rarityFilter != null,
                        onTap: () => _showRarityPicker(),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: _typeFilter != null ? _capitalize(_typeFilter!) : 'Type',
                        active: _typeFilter != null,
                        onTap: () => _showTypePicker(),
                      ),
                      const SizedBox(width: 6),
                      _SortChip(
                        label: '✨ Shiny',
                        active: _shinyFilter,
                        onTap: () => setState(() => _shinyFilter = !_shinyFilter),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Card grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                      final selected = inst.instanceId != null
                          ? _workingInstanceIds.contains(inst.instanceId)
                          : _workingCardIds.contains(inst.cardId);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onGridCardTap(inst),
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
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
            ),
            // Bottom buttons
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _editing = null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF74777F)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isValid ? const Color(0xFF4CAF50) : const Color(0xFF3A3A3A),
                          foregroundColor: isValid ? Colors.white : Colors.white30,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
      ),
    );
  }

  void _sortInstances(List<CardGrowth> instances) {
    // Filter by rarity
    if (_rarityFilter != null) {
      instances.removeWhere((inst) {
        final card = CardRepository.instance.cardById(inst.cardId);
        return card == null || card.rarity != _rarityFilter;
      });
    }
    // Filter by type
    if (_typeFilter != null) {
      instances.removeWhere((inst) {
        final card = CardRepository.instance.cardById(inst.cardId);
        return card == null || card.affinity != _typeFilter;
      });
    }
    // Filter by shiny
    if (_shinyFilter) {
      instances.removeWhere((inst) => !inst.shiny);
    }
    // Sort
    int cmp(CardGrowth a, CardGrowth b) {
      final ca = CardRepository.instance.cardById(a.cardId);
      final cb = CardRepository.instance.cardById(b.cardId);
      if (ca == null || cb == null) return 0;
      switch (_sortField) {
        case 'name':
          return ca.name.compareTo(cb.name);
        case 'number':
          final na = int.tryParse(ca.cardNumber) ?? 9999;
          final nb = int.tryParse(cb.cardNumber) ?? 9999;
          return na.compareTo(nb);
        case 'level':
          return a.level.compareTo(b.level);
        case 'condition':
          return a.condition.compareTo(b.condition);
        default:
          return 0;
      }
    }
    instances.sort((a, b) => _sortAscending ? cmp(a, b) : cmp(b, a));
  }

  void _showRarityPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A30),
        title: const Text('Filter by Rarity', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...CardRarity.values.map((r) => ListTile(
              leading: Icon(Icons.star, color: _rarityColor(r), size: 20),
              title: Text(_capitalize(r.name), style: const TextStyle(color: Colors.white70)),
              trailing: _rarityFilter == r ? const Icon(Icons.check, color: Color(0xFF4CAF50)) : null,
              onTap: () {
                setState(() => _rarityFilter = _rarityFilter == r ? null : r);
                Navigator.pop(ctx);
              },
            )),
            ListTile(
              leading: const Icon(Icons.clear, color: Colors.white38, size: 20),
              title: const Text('Clear Filter', style: TextStyle(color: Colors.white38)),
              onTap: () {
                setState(() => _rarityFilter = null);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTypePicker() {
    final types = <String>{};
    for (final inst in context.read<PlayerProfileController>().allCardInstances) {
      final card = CardRepository.instance.cardById(inst.cardId);
      if (card != null && card.affinity.isNotEmpty) types.add(card.affinity);
    }
    final sorted = types.toList()..sort();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A30),
        title: const Text('Filter by Type', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sorted.map((t) => GestureDetector(
              onTap: () {
                setState(() => _typeFilter = _typeFilter == t ? null : t);
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _typeFilter == t ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _typeFilter == t ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/ui/types/$t.png', width: 20, height: 20, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    const SizedBox(width: 6),
                    Text(_capitalize(t), style: TextStyle(color: _typeFilter == t ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  Color _rarityColor(CardRarity r) {
    switch (r) {
      case CardRarity.common: return Colors.grey;
      case CardRarity.uncommon: return const Color(0xFF4CAF50);
      case CardRarity.rare: return const Color(0xFF2196F3);
      case CardRarity.epic: return const Color(0xFF9C27B0);
      case CardRarity.legendary: return const Color(0xFFFFD700);
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  void _duplicateDeck() {
    final src = _editing!;
    final newDeck = Deck(
      id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
      name: '${src.name} (Copy)',
      cardIds: List<String>.from(src.cardIds),
      instanceIds: src.instanceIds != null ? List<int?>.from(src.instanceIds!) : null,
      boxImage: src.boxImage,
      featuredCardIndex: src.featuredCardIndex,
    );
    context.read<PlayerProfileController>().saveDeck(newDeck);
    if (mounted) setState(() => _editing = null);
  }

  void _showBoxPicker() {
    const allBoxes = [
      {'key': 'field_deck', 'label': 'Field Trip'},
      {'key': 'safari_deck', 'label': 'Safari Tour'},
      {'key': 'urban_deck', 'label': 'Urban Life'},
    ];
    final profile = context.read<PlayerProfileController>().profile;
    final unlocked = profile.unlockedDeckBoxes;
    final boxes = allBoxes.where((b) => unlocked.contains(b['key'])).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF282A30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deck Box', style: TextStyle(color: Colors.white, fontFamily: 'PowerGreen')),
        content: SizedBox(
          width: 340,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.82,
            ),
            itemCount: boxes.length,
            itemBuilder: (_, i) {
              final box = boxes[i];
              final selected = _editing?.boxImage == box['key'];
              final gradColors = _gradientForBox(box['key'] as String);
              return GestureDetector(
                onTap: () {
                  setState(() => _editing = _editing!.copyWith(boxImage: box['key'] as String));
                  Navigator.pop(ctx);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF282A30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? const Color(0xFFC9A44C) : const Color(0xFF1A1C20), width: selected ? 1.5 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipPath(
                          clipper: _DiagonalTopClipper(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.topRight,
                                colors: gradColors,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/Booster Pack/${box['key']}.png', width: 72, height: 52, fit: BoxFit.contain),
                          const SizedBox(height: 2),
                          Text(box['label'] as String, style: TextStyle(color: selected ? Colors.white : Colors.white54, fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                      ),
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
        color: const Color(0xFF282A30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Build New tile ──

class _BuildNewTile extends StatelessWidget {
  const _BuildNewTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -4, right: -4, top: -4, bottom: -4,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D2E35), Color(0xFF1F2027)],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF74777F), width: 2),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF282A30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1C20), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipPath(
                    clipper: _DiagonalTopClipper(),
                    child: SizedBox.expand(),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 150,
                      child: Center(
                        child: Icon(Icons.add, color: Colors.white24, size: 48),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Deck tile with press animation ──

class _DeckTile extends StatefulWidget {
  const _DeckTile({
    required this.deck,
    required this.isDefault,
    required this.boxImg,
    required this.featuredCard,
    required this.featuredIndex,
    this.onTap,
    this.onLongPress,
    required this.onMenuAction,
  });

  final Deck deck;
  final bool isDefault;
  final String boxImg;
  final TriadCard? featuredCard;
  final int featuredIndex;
  final Future<void> Function()? onTap;
  final VoidCallback? onLongPress;
  final void Function(String action) onMenuAction;

  @override
  State<_DeckTile> createState() => _DeckTileState();
}

class _DeckTileState extends State<_DeckTile> {
  bool _pressed = false;

  void _press() {
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<PlayerProfileController>();
    final boxImg = widget.boxImg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _press();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) widget.onTap?.call();
        });
      },
      onLongPress: () {
        _press();
        widget.onLongPress?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient shadow
          Positioned(
            left: -4, right: -4, top: -4, bottom: -4,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D2E35), Color(0xFF1F2027)],
                  ),
                ),
              ),
            ),
          ),
          // Outer border
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF74777F), width: 2),
              ),
            ),
          ),
          // Main container
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF282A30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1C20), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Diagonal cut with color gradient
                Positioned(
                  left: 0, right: 0, top: 0, bottom: 0,
                  child: ClipPath(
                    clipper: _DiagonalTopClipper(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.topRight,
                          colors: _DeckBuilderScreenState._gradientForBox(widget.boxImg),
                        ),
                      ),
                    ),
                  ),
                ),
                // Deck box icon watermark in the diagonal cut — same
                // treatment as a shop card's type icon watermark.
                if (deckBoxIconAsset(boxImg) != null)
                  Positioned(
                    top: 0,
                    left: 4,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.22,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Color(0xFFB0B0B8),
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            deckBoxIconAsset(boxImg)!,
                            width: 56,
                            height: 56,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Content
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: SizedBox(
                      width: 220,
                      height: 150,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Image.asset('assets/images/Booster Pack/$boxImg.png', width: 170, height: 120, fit: BoxFit.contain),
                          ),
                          if (widget.featuredCard != null)
                            Builder(builder: (_) {
                              CardGrowth? g;
                              final fi = widget.featuredIndex;
                              final instId = widget.deck.instanceIds != null && fi < widget.deck.instanceIds!.length
                                  ? widget.deck.instanceIds![fi] : null;
                              if (instId != null && instId > 0) {
                                g = ctrl.allCardInstances.where((inst) => inst.instanceId == instId).firstOrNull;
                              }
                              return Transform.translate(
                                offset: const Offset(-4, 28),
                                child: Center(
                                  child: SizedBox(
                                    width: 48, height: 48,
                                    child: TriadCardView(card: widget.featuredCard!, size: 48, growth: g),
                                  ),
                                ),
                              );
                            }),
                          Positioned(
                            bottom: 4,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0x60000000),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(widget.deck.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Color(0xFF9C9DA3), fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'PowerGreen')),
                            ),
                          ),
                        ],
                      ),
                ),
                ),
                // Inner shadow painter
                Positioned(
                  left: 0, right: 0, top: 0, bottom: 0,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _InnerShadowPainter(),
                    ),
                  ),
                ),
                // Default star badge
                if (widget.isDefault)
                  const Positioned(
                    top: 6,
                    left: 8,
                    child: Icon(Icons.star, color: Color(0xFFC9A44C), size: 16),
                  ),
                // Three-dot menu
                Positioned(
                  top: 0,
                  right: 0,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.4), size: 16),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: widget.onMenuAction,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _DiagonalTopClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = 12.0;

    final glowPaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), glowPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, glowPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), glowPaint);

    final borderPaint = Paint()
      ..color = const Color(0x99B6A2A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), borderPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, borderPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.active, this.trailing, required this.onTap});
  final String label;
  final bool active;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3A3C44) : const Color(0xFF282A30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? const Color(0xFF74777F) : const Color(0xFF1A1C20), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: active ? Colors.white : Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600)),
            if (trailing != null) ...[
              const SizedBox(width: 2),
              Text(trailing!, style: TextStyle(color: active ? Colors.white54 : Colors.white24, fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}
