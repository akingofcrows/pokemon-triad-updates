import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../game/cards/card_visuals.dart';
import '../models/card_growth.dart';
import '../models/card_set.dart';
import '../models/card_values.dart';
import '../models/condition.dart';
import '../models/evolution_chain.dart';
import '../models/pokemon_leveling.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/audio_service.dart';
import '../services/sprite_downloader.dart';
import '../widgets/card_damage_overlay.dart';
import '../widgets/condition_badge.dart';
import '../widgets/evolution_animation.dart';
import '../widgets/mint_shimmer.dart';
import '../widgets/tilt_card.dart';
import '../widgets/toast.dart';
import '../widgets/triad_card_view.dart';

enum _SortMode { number, rarity, type, level, name, condition }

const _affinities = [
  'normal',
  'fire',
  'water',
  'electric',
  'grass',
  'ice',
  'fighting',
  'poison',
  'ground',
  'flying',
  'psychic',
  'bug',
  'rock',
  'ghost',
  'dragon',
  'dark',
  'steel',
  'fairy',
];

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  String _selectedSetId = 'all';
  _SortMode _sortMode = _SortMode.number;
  bool _sortAscending = true;
  CardRarity? _rarityFilter;
  String? _typeFilter;

  // Instances currently mid-flip after evolving on this screen, keyed by
  // instanceId — while present, the grid tile shows a flip transition from
  // the old card to the new one instead of snapping straight to the new art.
  final Map<int, _PendingFlip> _flippingInstances = {};

  // Multi-select batch sell state
  bool _selectMode = false;
  final Set<int> _selectedInstanceIds = {};
  bool _batchSelling = false;

  @override
  Widget build(BuildContext context) {
    final repository = CardRepository.instance;
    final controller = context.watch<PlayerProfileController>();
    final cardGrowth = controller.cardGrowth;
    final instances = controller.allCardInstances;
    final sets = repository.sets;
    final selectedSet = sets.firstWhere(
      (s) => s.id == _selectedSetId,
      orElse: () => sets.first,
    );

    // "all" is a virtual set meaning "no filter" — its cardIds is
    // deliberately empty rather than a duplicated list of every card id.
    var owned = selectedSet.id == 'all'
        ? instances.toList()
        : instances.where((i) => selectedSet.cardIds.contains(i.cardId)).toList();
    // Remove instances with missing card data
    owned = owned.where((i) => repository.cardById(i.cardId) != null).toList();
    // Apply type/rarity filters
    if (_typeFilter != null) {
      owned = owned.where((i) {
        final c = repository.cardById(i.cardId);
        return c != null && c.affinity == _typeFilter;
      }).toList();
    }
    if (_rarityFilter != null) {
      owned = owned.where((i) {
        final c = repository.cardById(i.cardId);
        return c != null && c.rarity == _rarityFilter;
      }).toList();
    }
    // Sort by selected mode
    final asc = _sortAscending;
    switch (_sortMode) {
      case _SortMode.name:
        owned.sort((a, b) {
          final ca = repository.cardById(a.cardId);
          final cb = repository.cardById(b.cardId);
          if (ca == null || cb == null) return 0;
          return asc ? ca.name.compareTo(cb.name) : cb.name.compareTo(ca.name);
        });
      case _SortMode.number:
        owned.sort((a, b) {
          final ca = repository.cardById(a.cardId);
          final cb = repository.cardById(b.cardId);
          if (ca == null || cb == null) return 0;
          return asc
              ? ca.cardNumber.compareTo(cb.cardNumber)
              : cb.cardNumber.compareTo(ca.cardNumber);
        });
      case _SortMode.level:
        owned.sort(
          (a, b) =>
              asc ? a.level.compareTo(b.level) : b.level.compareTo(a.level),
        );
      case _SortMode.condition:
        owned.sort(
          (a, b) => asc
              ? a.condition.compareTo(b.condition)
              : b.condition.compareTo(a.condition),
        );
      case _SortMode.rarity:
        owned.sort((a, b) {
          final ca = repository.cardById(a.cardId);
          final cb = repository.cardById(b.cardId);
          if (ca == null || cb == null) return 0;
          return asc
              ? _rarityWeight(ca.rarity).compareTo(_rarityWeight(cb.rarity))
              : _rarityWeight(cb.rarity).compareTo(_rarityWeight(ca.rarity));
        });
      case _SortMode.type:
        owned.sort((a, b) {
          final ca = repository.cardById(a.cardId);
          final cb = repository.cardById(b.cardId);
          if (ca == null || cb == null) return 0;
          final cmp = asc
              ? ca.affinity.compareTo(cb.affinity)
              : cb.affinity.compareTo(ca.affinity);
          if (cmp != 0) return cmp;
          return asc ? ca.name.compareTo(cb.name) : cb.name.compareTo(ca.name);
        });
    }

    void selectSort(_SortMode mode, {bool defaultAsc = true}) {
      setState(() {
        if (_sortMode == mode) {
          _sortAscending = !_sortAscending;
        } else {
          _sortMode = mode;
          _sortAscending = defaultAsc;
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(
        backgroundColor: const Color(0xFF282A30),
        title: _selectMode
            ? Text('${_selectedInstanceIds.length} selected')
            : const Text('Collection'),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
              )
            : null,
        actions: [
          if (_selectMode) ...[
            if (_selectedInstanceIds.length == owned.length)
              TextButton(
                onPressed: () => setState(() => _selectedInstanceIds.clear()),
                child: const Text('Deselect All', style: TextStyle(color: Colors.white70)),
              )
            else
              TextButton(
                onPressed: () => setState(() {
                  for (final inst in owned) {
                    if (inst.instanceId != null) {
                      _selectedInstanceIds.add(inst.instanceId!);
                    }
                  }
                }),
                child: const Text('Select All', style: TextStyle(color: Colors.white70)),
              ),
          ] else ...[
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _SetSelector(
                sets: sets,
                selectedSetId: _selectedSetId,
                onChanged: _selectMode
                    ? (_) {} // no-op in select mode
                    : (id) => setState(() => _selectedSetId = id),
              ),
              const SizedBox(height: 8),
              if (!_selectMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            _SortChip(label: 'Name', active: _sortMode == _SortMode.name, ascending: _sortMode == _SortMode.name ? _sortAscending : null, onTap: () => selectSort(_SortMode.name)),
                            _SortChip(label: 'Num', active: _sortMode == _SortMode.number, ascending: _sortMode == _SortMode.number ? _sortAscending : null, onTap: () => selectSort(_SortMode.number)),
                            _SortChip(label: 'Lv', active: _sortMode == _SortMode.level, ascending: _sortMode == _SortMode.level ? _sortAscending : null, onTap: () => selectSort(_SortMode.level, defaultAsc: false)),
                            _SortChip(label: 'Cnd', active: _sortMode == _SortMode.condition, ascending: _sortMode == _SortMode.condition ? _sortAscending : null, onTap: () => selectSort(_SortMode.condition)),
                            _SortChip(label: _rarityFilter != null ? _capitalize(_rarityFilter!.name) : 'Rarity', active: _sortMode == _SortMode.rarity || _rarityFilter != null, onTap: () => _showRarityModal()),
                            _SortChip(label: _typeFilter != null ? _capitalize(_typeFilter!) : 'Type', icon: _typeFilter != null ? Image.asset(typeIconAsset(_typeFilter!), width: 14, height: 14) : null, active: _sortMode == _SortMode.type || _typeFilter != null, onTap: () => _showTypeModal()),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${owned.length} cards', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    (_selectMode ? 80 : 12) + MediaQuery.of(context).padding.bottom,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 0, crossAxisSpacing: 3, childAspectRatio: 0.72),
                  itemCount: owned.length,
                  itemBuilder: (context, index) {
                    final instance = owned[index];
                    final pending = instance.instanceId != null
                        ? _flippingInstances[instance.instanceId]
                        : null;
                    final card =
                        pending?.to ?? repository.cardById(instance.cardId);
                    if (card == null) return const SizedBox.shrink();
                    final instId = instance.instanceId;
                    final isSelected = instId != null && _selectedInstanceIds.contains(instId);
                    return _CardTile(
                      key: ValueKey(instance.instanceId),
                      onTap: () {
                        AudioService().playSfx('sound/pop-ui.mp3');
                        if (_selectMode) {
                          _toggleSelection(instId);
                        } else {
                          _showCardDetail(context, card, instance);
                        }
                      },
                      onLongPress: () {
                        if (!_selectMode) {
                          _enterSelectMode(instId);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                          if (pending != null)
                            _CardFlipTile(
                              key: ValueKey('flip_${instance.instanceId}'),
                              fromCard: pending.from,
                              toCard: pending.to,
                              growth: instance,
                              size: 85,
                              dataReady: pending.dataReady,
                              onDone: () {
                                if (mounted)
                                  setState(
                                    () => _flippingInstances.remove(
                                      instance.instanceId,
                                    ),
                                  );
                              },
                            )
                          else
                            TriadCardView(card: card, size: 85, growth: instance, showNewBadge: instance.instanceId != null && context.read<PlayerProfileController>().isNewInstance(instance.instanceId!),),
                          // Selection overlay
                          if (_selectMode)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.amber.withValues(alpha: 0.3)
                                      : Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: isSelected
                                      ? Border.all(color: Colors.amber, width: 2.5)
                                      : null,
                                ),
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: isSelected
                                          ? Colors.amber
                                          : Colors.white38,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                          const SizedBox(height: 1),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0x60000000), borderRadius: BorderRadius.circular(4)),
                              child: Text('${card.name} Lv.${instance.level}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 9, fontWeight: FontWeight.w800, fontFamily: 'PowerGreen')),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // ── Batch sell bottom bar ──
          if (_selectMode && _selectedInstanceIds.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBatchSellBar(controller, owned),
            ),
        ],
      ),
    );
  }

  void _toggleSelection(int? instId) {
    if (instId == null) return;
    setState(() {
      if (_selectedInstanceIds.contains(instId)) {
        _selectedInstanceIds.remove(instId);
        if (_selectedInstanceIds.isEmpty) {
          _selectMode = false;
        }
      } else {
        _selectedInstanceIds.add(instId);
      }
    });
  }

  void _enterSelectMode(int? instId) {
    setState(() {
      _selectMode = true;
      if (instId != null) {
        _selectedInstanceIds.add(instId);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedInstanceIds.clear();
    });
  }

  int _sellPrice(CardGrowth growth, TriadCard card) {
    final shinyMult = (growth.shiny == true) ? 3 : 1;
    final conditionMult = sellValueMultiplierForTier(growth.conditionTier);
    return (card.worth * shinyMult * conditionMult).round();
  }

  Widget _buildBatchSellBar(PlayerProfileController ctrl, List<CardGrowth> owned) {
    final selectedInstances = owned
        .where((i) => i.instanceId != null && _selectedInstanceIds.contains(i.instanceId))
        .toList();
    var totalPrice = 0;
    for (final inst in selectedInstances) {
      final card = CardRepository.instance.cardById(inst.cardId);
      if (card != null) {
        totalPrice += _sellPrice(inst, card);
      }
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.amber.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selectedInstances.length} cards selected',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  'Sell for ₽$totalPrice',
                  style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC9A44C),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: Colors.grey.shade700,
              ),
              onPressed: _batchSelling
                  ? null
                  : () => _batchSell(ctrl, selectedInstances, totalPrice),
              child: _batchSelling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Sell Selected', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _batchSell(
    PlayerProfileController ctrl,
    List<CardGrowth> selected,
    int totalPrice,
  ) async {
    setState(() => _batchSelling = true);
    var soldCount = 0;
    for (final inst in selected) {
      if (inst.instanceId == null) continue;
      final card = CardRepository.instance.cardById(inst.cardId);
      if (card == null) continue;
      final price = _sellPrice(inst, card);
      final ok = await ctrl.sellCardInstance(inst.instanceId!, price);
      if (ok) soldCount++;
    }
    _exitSelectMode();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Toast.show(context, text: '₽$totalPrice Obtained!', imagePath: '__money__');
      });
    }
  }

  List<TriadCard> _sortedCards(
    List<TriadCard> cards,
    Map<String, CardGrowth> cardGrowth,
  ) {
    final sorted = cards.toList();
    switch (_sortMode) {
      case _SortMode.name:
        sorted.sort((a, b) => a.name.compareTo(b.name));
      case _SortMode.number:
        sorted.sort((a, b) {
          final typeCmp = _cardTypeRank(a).compareTo(_cardTypeRank(b));
          if (typeCmp != 0) return typeCmp;
          return _compareNumberParts(a.cardNumber, b.cardNumber);
        });
      case _SortMode.level:
        sorted.sort((a, b) {
          final lvA = cardGrowth[a.id]?.level ?? 1;
          final lvB = cardGrowth[b.id]?.level ?? 1;
          final lvCmp = lvB.compareTo(lvA); // highest level first
          if (lvCmp != 0) return lvCmp;
          return _compareNumberParts(a.cardNumber, b.cardNumber);
        });
      case _SortMode.rarity:
        sorted.sort((a, b) => a.rarity.index.compareTo(b.rarity.index));
      case _SortMode.type:
        sorted.sort((a, b) {
          final cmp = a.affinity.compareTo(b.affinity);
          return cmp != 0 ? cmp : a.name.compareTo(b.name);
        });
      case _SortMode.condition:
        sorted.sort((a, b) {
          final cA = cardGrowth[a.id]?.condition ?? 100;
          final cB = cardGrowth[b.id]?.condition ?? 100;
          return cA.compareTo(cB); // worst condition first
        });
    }
    return sorted;
  }

  void _showRarityModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Filter by Rarity',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RarityTile(
              null,
              'All rarities',
              selected: _rarityFilter == null,
              onTap: () {
                setState(() {
                  _rarityFilter = null;
                  _sortMode = _SortMode.number;
                });
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            for (final r in CardRarity.values)
              _RarityTile(
                r,
                _capitalize(r.name),
                selected: _rarityFilter == r,
                onTap: () {
                  setState(() {
                    _rarityFilter = r;
                    _sortMode = _SortMode.rarity;
                  });
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTypeModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Filter by Type',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _typeFilter = null;
                    _sortMode = _SortMode.number;
                  });
                  Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(
                  backgroundColor: _typeFilter == null
                      ? Colors.amber.withValues(alpha: 0.3)
                      : Colors.white12,
                ),
                child: const Text(
                  'All',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _affinities
                  .map(
                    (t) => GestureDetector(
                      onTap: () {
                        setState(() {
                          _typeFilter = t;
                          _sortMode = _SortMode.type;
                        });
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _typeFilter == t
                              ? Colors.amber.withValues(alpha: 0.3)
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                          border: _typeFilter == t
                              ? Border.all(color: Colors.amber, width: 2)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Image.asset(
                          typeIconAsset(t),
                          width: 28,
                          height: 28,
                          errorBuilder: (_, __, ___) => Text(
                            t.substring(0, 3),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  int _cardTypeRank(TriadCard card) =>
      card.cardType == TriadCardType.pokemon ? 0 : 1;

  int _rarityWeight(CardRarity r) => r.index;

  /// Compares two card numbers like "001-1" and "002" by splitting on
  /// non-digits and comparing each numeric segment in order, with shorter
  /// sequences sorting before longer ones that share the same prefix
  /// (so "001" < "001-1" < "002").
  int _compareNumberParts(String a, String b) {
    final partsA = a
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map(int.parse)
        .toList();
    final partsB = b
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map(int.parse)
        .toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final cmp = partsA[i].compareTo(partsB[i]);
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }

  void _showCardDetail(
    BuildContext context,
    TriadCard card,
    CardGrowth? growth,
  ) {
    final effectiveValues = growth == null
        ? card.values
        : card.values.plusBonus(growth.bonusValues);
    final level = growth?.level ?? 1;
    final evolutions = card.cardType == TriadCardType.pokemon
        ? CardRepository.instance
              .evolutionsFrom(card.id)
              .where((e) => level >= e.level)
              .toList()
        : const <EvolutionChain>[];
    final trainerName = context
        .read<PlayerProfileController>()
        .profile
        .trainerName;
    final ctrl = context.read<PlayerProfileController>();
    final isShiny = growth?.shiny == true;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var detailTilt = Offset.zero;
          return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          child: _detailFrame(affinity: card.affinity, child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ── Header row ──
                Row(children: [
                  // Card number badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1C20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text('#${card.cardNumber}', style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                  const Spacer(),
                  // Shiny badge
                  if (isShiny)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFF8B6914)]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('✨', style: TextStyle(fontSize: 11)),
                        SizedBox(width: 3),
                        Text('SHINY', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ]),
                    ),
                  // Favorite
                  GestureDetector(
                    onTap: () {
                      final iid = growth?.instanceId;
                      if (iid == null) return;
                      ctrl.toggleFavorite(iid);
                      setDialogState(() {});
                    },
                    child: Builder(builder: (_) {
                      final iid = growth?.instanceId;
                      final fav = iid != null && ctrl.isFavorite(iid);
                      return Icon(fav ? Icons.star : Icons.star_border, color: fav ? const Color(0xFFC9A44C) : Colors.white24, size: 22);
                    }),
                  ),
                ]),
                const SizedBox(height: 12),
                // ── Card image ──
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      TiltCard(
                        onTiltChanged: (o) => setDialogState(() => detailTilt = o),
                        damage: growth == null ? 0.0 : (kMaxCondition - growth.condition) / kMaxCondition,
                        child: Builder(
                          builder: (ctx) {
                            Widget cardStack = Stack(
                              clipBehavior: Clip.none,
                              children: [
                                TriadCardView(card: card, size: 150, growth: growth, holoTilt: detailTilt),
                                if (growth != null && growth.conditionTier == ConditionTier.mint)
                                  const Positioned.fill(child: MintShimmer()),
                              ],
                            );
                            // Clip the whole card stack around damage holes so shimmer
                            // doesn't bleed through torn/burned areas.
                            if (growth != null && growth.conditionTier != ConditionTier.mint) {
                              final seed = stableCardSeed(card.id, growth.instanceId);
                              final (tearCount, burnCount) = damageHoleCountsForTier(growth.conditionTier, seed);
                              if (tearCount > 0 || burnCount > 0) {
                                final holes = computeDamageHoles(
                                  size: const Size.square(150),
                                  seed: seed,
                                  tearCount: tearCount,
                                  burnCount: burnCount,
                                  wear: (kMaxCondition - growth.condition) / kMaxCondition,
                                );
                                if (holes.isNotEmpty) {
                                  cardStack = ClipPath(clipper: CardFaceHoleClipper(holes: holes), child: cardStack);
                                }
                              }
                            }
                            return cardStack;
                          },
                        ),
                      ),
                      if (growth != null)
                        Positioned(left: -88, top: 48, child: _conditionStamp(growth.conditionTier)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Name + level ──
                Text('${card.name}  Lv.$level', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, decoration: TextDecoration.none), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                // ── Type + Rarity row ──
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _rarityBadge(card.rarity, holo: card.holo),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF1A1C20), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Image.asset(typeIconAsset(card.affinity), width: 18, height: 18),
                      const SizedBox(width: 6),
                      Text(_capitalize(card.affinity), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                    ]),
                  ),
                ]),
                // ── XP bar ──
                if (card.cardType == TriadCardType.pokemon) ...[
                  const SizedBox(height: 14),
                  ..._buildXpBar(growth),
                ],
                // ── Condition ──
                if (growth != null && growth.condition < kMaxCondition) ...[
                  const SizedBox(height: 12),
                  ConditionDetail(condition: growth.condition, effectSummary: conditionEffectSummary(effectiveValues, growth.condition)),
                ],
                const SizedBox(height: 16),
                // ── NSEW stats ──
                _detailStatsRow(effectiveValues, growth, card.affinity),
                const SizedBox(height: 14),
                // ── Evolution chain ──
                if (card.cardType == TriadCardType.pokemon)
                  _buildEvolutionChain(card, context.read<PlayerProfileController>().cardGrowth, isShiny: isShiny),
                if (card.cardType == TriadCardType.pokemon) const SizedBox(height: 8),
                // ── OT / Obtained ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF1A1C20), borderRadius: BorderRadius.circular(8)),
                  child: Column(children: [
                    Text('OT: ${trainerName ?? '—'}', style: const TextStyle(color: Colors.white54, fontSize: 12, decoration: TextDecoration.none)),
                    Text('Obtained: ${growth?.humanizedSource ?? '—'}', style: const TextStyle(color: Colors.white54, fontSize: 12, decoration: TextDecoration.none)),
                  ]),
                ),
                const SizedBox(height: 12),
                // ── Evolve buttons ──
                for (final evo in evolutions) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _detailButton(
                      label: 'Evolve → ${CardRepository.instance.cardById(evo.to)?.name ?? evo.to}',
                      color: const Color(0xFF4CAF50),
                      onTap: () async {
                        final toCard = CardRepository.instance.cardById(evo.to);
                        final confirm = await showDialog<bool>(
                          context: dialogContext,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Confirm Evolution'),
                            content: Text('Evolve ${card.name}${isShiny ? ' ✨Shiny' : ''} (Lv.${growth?.level ?? 1}) into ${toCard?.name ?? evo.to}?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evolve!')),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        Navigator.pop(dialogContext);
                        if (toCard == null) {
                          context.read<PlayerProfileController>().evolveCard(card.id, evo.to, instanceId: growth?.instanceId);
                          return;
                        }
                        final evolveFuture = context.read<PlayerProfileController>().evolveCard(card.id, evo.to, instanceId: growth?.instanceId);
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => EvolutionAnimation(
                            fromCard: card.copyWith(shiny: isShiny),
                            toCard: toCard.copyWith(shiny: isShiny),
                            fromBonuses: growth?.bonusValues,
                            toBonusesFuture: evolveFuture,
                            onComplete: () => Navigator.pop(context),
                          ),
                        )).then((_) {
                          if (!context.mounted) return;
                          final instId = growth?.instanceId;
                          if (instId != null) {
                            setState(() {
                              _flippingInstances[instId] = _PendingFlip(
                                from: card.copyWith(shiny: isShiny),
                                to: toCard.copyWith(shiny: isShiny),
                                dataReady: evolveFuture,
                              );
                            });
                          }
                        });
                      },
                    ),
                  ),
                ],
                // ── Sell + Close ──
                Row(children: [
                  if (growth != null)
                    Expanded(child: _detailButton(
                      label: 'Sell ₽${_sellPrice(growth, card)}',
                      color: const Color(0xFFC9A44C),
                      onTap: () async {
                        final instId = growth.instanceId;
                        if (instId == null) return;
                        final price = _sellPrice(growth, card);
                        final sold = await ctrl.sellCardInstance(instId, price);
                        if (sold && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            Toast.showStacked(context, items: [
                              {'text': '1× ${card.name} Card Sold!', 'icon': TriadCardView(card: card, size: 44, showCondition: false)},
                              {'text': '₽$price Obtained!', 'imagePath': '__money__'},
                            ]);
                          });
                        }
                      },
                    )),
                  if (growth != null) const SizedBox(width: 10),
                  Expanded(child: _detailButton(
                    label: 'Close',
                    onTap: () => Navigator.pop(dialogContext),
                  )),
                ]),
              ]),
            ),
          )),
      );
  },
  ),
);
  }

  Widget _detailButton({required String label, Color? color, required VoidCallback onTap}) {
    final c = color ?? Colors.white24;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: c.withValues(alpha: 0.15),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Text(label, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
        ),
      ),
    );
  }

  Widget _detailStatsRow(CardValues values, CardGrowth? growth, String affinity) {
    final accent = _detailAccent(affinity);
    return Row(children: [
      _detailStat('N', values.north, bonus: growth?.bonusNorth ?? 0, accent: accent),
      _detailStat('S', values.south, bonus: growth?.bonusSouth ?? 0, accent: accent),
      _detailStat('E', values.east, bonus: growth?.bonusEast ?? 0, accent: accent),
      _detailStat('W', values.west, bonus: growth?.bonusWest ?? 0, accent: accent),
    ]);
  }

  Widget _detailStat(String label, int value, {int bonus = 0, required Color accent}) {
    final hasBonus = bonus > 0;
    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w800, decoration: TextDecoration.none)),
        const SizedBox(height: 2),
        Text('$value', style: TextStyle(color: hasBonus ? Colors.greenAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
        if (hasBonus)
          Text('+$bonus', style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
      ]),
    ));
  }

  Color _detailAccent(String affinity) {
    switch (affinity.toLowerCase()) {
      case 'fire': return const Color(0xFFF44B1A);
      case 'water': return const Color(0xFF3DA5E0);
      case 'grass': return const Color(0xFF5CBF60);
      case 'electric': return const Color(0xFFF0D830);
      case 'psychic': return const Color(0xFFE83A88);
      case 'ice': return const Color(0xFF5CE8F0);
      case 'dragon': return const Color(0xFF9050E0);
      case 'dark': return const Color(0xFF705080);
      case 'fairy': return const Color(0xFFF090D0);
      case 'fighting': return const Color(0xFFE07030);
      case 'flying': return const Color(0xFFA0B8F0);
      case 'ghost': return const Color(0xFF9060C0);
      case 'ground': return const Color(0xFFE0A830);
      case 'poison': return const Color(0xFFC060E0);
      case 'rock': return const Color(0xFFC0A858);
      case 'bug': return const Color(0xFFA0D050);
      case 'steel': return const Color(0xFFB8B8C8);
      default: return const Color(0xFFC8C0A0);
    }
  }

  List<Color> _detailGradient(String affinity) {
    const bg = Color(0xFF282A30);
    return [bg, _detailAccent(affinity)];
  }

  Widget _detailFrame({required Widget child, String? affinity}) {
    final grad = _detailGradient(affinity ?? '');
    final typeIconPath = affinity != null ? typeIconAsset(affinity) : null;
    final inner = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF282A30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A1C20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned.fill(child: ClipPath(
          clipper: _DiagonalTopClipper(),
          child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.topRight, colors: grad))),
        )),
        if (typeIconPath != null)
          Positioned(top: 0, left: 4, child: IgnorePointer(child: Opacity(opacity: 0.12, child: Image.asset(typeIconPath, width: 80, height: 80, errorBuilder: (_, __, ___) => const SizedBox.shrink())))),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DetailShadowPainter()))),
        child,
      ]),
    );
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(left: -4, right: -4, top: -4, bottom: -4, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2), child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2D2E35), Color(0xFF1F2027)]))))),
      inner,
    ]);
  }

  /// Rubber-stamp showing a card's actual Condition tier (GDD §2), replacing
  /// the old hardcoded "MINT" — the label and color now track whatever
  /// tier the card is really in.
  Widget _conditionStamp(ConditionTier tier) {
    final color = colorForConditionTier(tier);
    return Transform.rotate(
      angle: -0.15,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tier.label.toUpperCase(),
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, decoration: TextDecoration.none),
        ),
      ),
    );
  }

  Widget _rarityBadge(CardRarity rarity, {bool holo = false}) {
    const star = Icon(Icons.star, size: 16, color: Colors.white);
    Widget stars;
    switch (rarity) {
      case CardRarity.common:
        stars = star;
      case CardRarity.uncommon:
        stars = Row(mainAxisSize: MainAxisSize.min, children: [star, const SizedBox(width: 2), star]);
      case CardRarity.rare:
        stars = Column(mainAxisSize: MainAxisSize.min, children: [
          star,
          Row(mainAxisSize: MainAxisSize.min, children: [star, const SizedBox(width: 2), star]),
        ]);
      case CardRarity.epic:
        stars = Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [star, const SizedBox(width: 2), star]),
          Row(mainAxisSize: MainAxisSize.min, children: [star, const SizedBox(width: 2), star]),
        ]);
      case CardRarity.legendary:
        stars = Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star, size: 18, color: Color(0xFFFFCA28)),
          const SizedBox(width: 3),
          const Text('L', style: TextStyle(color: Color(0xFFFFCA28), fontSize: 13, fontWeight: FontWeight.w900, decoration: TextDecoration.none)),
        ]);
    }
    if (holo) return _HoloShimmer(child: stars);
    return stars;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Maps a [speciesId] (e.g. "bulbasaur") to its extracted sprite path.
  Future<String> _frontSpritePath(String speciesId) async {
    final base = await SpriteDownloader.instance.frontPath;
    return '$base/${speciesId.toUpperCase()}.png';
  }

  Widget _spriteOrPlaceholder(String? speciesId) {
    if (speciesId == null)
      return const Icon(Icons.help_outline, color: Colors.white24);
    return FutureBuilder<String>(
      future: _frontSpritePath(speciesId),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) return const SizedBox.shrink();
        final file = File(path);
        if (!file.existsSync()) {
          return Icon(
            Icons.catching_pokemon,
            color: Colors.white24.withValues(alpha: 0.4),
            size: 28,
          );
        }
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.catching_pokemon,
            color: Colors.white24.withValues(alpha: 0.4),
            size: 28,
          ),
        );
      },
    );
  }

  /// XP needed to advance from [level] to level+1 (cubic Pokémon formula).
  static int _xpForLevel(
    int level, {
    XpGrowthRate rate = XpGrowthRate.mediumFast,
  }) {
    return xpForNextLevel(level, rate: rate);
  }

  /// Cumulative XP needed to reach [level].
  static int _cumulativeXpForLevel(
    int level, {
    XpGrowthRate rate = XpGrowthRate.mediumFast,
  }) {
    return xpToReachLevel(level, rate: rate);
  }

  List<Widget> _buildXpBar(CardGrowth? growth) {
    if (growth == null) {
      return [
        const Text('No XP data', style: TextStyle(color: Colors.white54)),
      ];
    }
    final level = growth.level;
    final totalXp = growth.xp;
    // XP earned within the current level (total minus cumulative threshold for this level)
    final xpInLevelRaw = totalXp - _cumulativeXpForLevel(level);
    final needed = _xpForLevel(level);
    // Cap display: if server curve differs, don't show overflow numbers
    final xpInLevel = xpInLevelRaw.clamp(0, needed);
    final progress = needed > 0 ? (xpInLevel / needed).clamp(0.0, 1.0) : 1.0;
    return [
      Row(
        children: [
          Text(
            'Lv.$level',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4CAF50),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$xpInLevel / $needed XP',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    ];
  }

  Widget _statColumn(String label, int value, {int bonus = 0}) {
    final hasBonus = bonus > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: hasBonus ? Colors.greenAccent : Colors.white70,
                fontSize: 16,
                fontWeight: hasBonus ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (hasBonus)
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.arrow_upward,
                  color: Colors.greenAccent,
                  size: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEvolutionChain(
    TriadCard viewedCard,
    Map<String, CardGrowth> cardGrowth, {
    bool isShiny = false,
  }) {
    final line = CardRepository.instance.evolutionLineFor(viewedCard.id);
    if (line.isStandalone) return const SizedBox.shrink();

    final repository = CardRepository.instance;
    final nodes = <Widget>[];

    Widget node(String cardId, {bool highlight = false}) {
      final c = repository.cardById(cardId);
      // If viewing a non-shiny card, don't show shiny versions of relatives
      CardGrowth? effectiveGrowth = cardGrowth[cardId];
      if (!isShiny && effectiveGrowth?.shiny == true) {
        effectiveGrowth = null;
      }
      if (isShiny &&
          (effectiveGrowth == null || effectiveGrowth.shiny != true)) {
        effectiveGrowth = CardGrowth(
          cardId: cardId,
          xp: 0,
          level: 1,
          bonusNorth: effectiveGrowth?.bonusNorth ?? 0,
          bonusSouth: effectiveGrowth?.bonusSouth ?? 0,
          bonusEast: effectiveGrowth?.bonusEast ?? 0,
          bonusWest: effectiveGrowth?.bonusWest ?? 0,
          shiny: true,
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: highlight
                  ? Colors.amber.withValues(alpha: 0.15)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: highlight
                  ? Border.all(color: Colors.amber, width: 2)
                  : Border.all(color: Colors.white24, width: 1),
            ),
            child: c != null
                ? TriadCardView(card: c, size: 44, growth: effectiveGrowth)
                : const Icon(
                    Icons.help_outline,
                    color: Colors.white24,
                    size: 24,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            c?.name ?? cardId,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
        ],
      );
    }

    Widget arrow(int level) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lv.$level',
              style: const TextStyle(fontSize: 9, color: Colors.amber),
            ),
            const Icon(Icons.arrow_forward, size: 16),
          ],
        ),
      );
    }

    for (final step in line.ancestors) {
      nodes.add(node(step.cardId));
      nodes.add(arrow(step.level));
    }
    nodes.add(node(viewedCard.id, highlight: true));
    for (final step in line.descendants) {
      nodes.add(arrow(step.level));
      nodes.add(node(step.cardId));
    }
    for (final branch in line.branchOptions) {
      nodes.add(arrow(branch.level));
      nodes.add(node(branch.cardId));
    }

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: nodes),
      ),
    );
  }

  static const Icon _starIcon = Icon(Icons.star, size: 16, color: Colors.amber);

  Widget _buildRarityDisplay(CardRarity rarity) {
    final label = Text(
      _capitalize(rarity.name),
      style: const TextStyle(color: Colors.white70),
    );
    switch (rarity) {
      case CardRarity.common:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [_starIcon, const SizedBox(width: 6), label],
        );
      case CardRarity.uncommon:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [_starIcon, _starIcon, const SizedBox(width: 6), label],
        );
      case CardRarity.rare:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _starIcon,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_starIcon, _starIcon],
                ),
              ],
            ),
            const SizedBox(width: 6),
            label,
          ],
        );
      case CardRarity.epic:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_starIcon, _starIcon],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_starIcon, _starIcon],
                ),
              ],
            ),
            const SizedBox(width: 6),
            label,
          ],
        );
      case CardRarity.legendary:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: const Text(
                'L',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 6),
            label,
          ],
        );
    }
  }
}

/// Old/new card pair for an instance whose grid tile is mid-flip.
class _PendingFlip {
  _PendingFlip({required this.from, required this.to, this.dataReady});
  final TriadCard from;
  final TriadCard to;

  /// Resolves once the real evolve call has landed — the flip tile waits
  /// for this too, not just its own animation, before handing back to the
  /// plain grid view (which reads the card from provider state).
  final Future<void>? dataReady;
}

/// Flips a grid tile from the pre-evolution card to the post-evolution card,
/// like a card being turned over.
class _CardFlipTile extends StatefulWidget {
  const _CardFlipTile({
    super.key,
    required this.fromCard,
    required this.toCard,
    required this.growth,
    required this.size,
    required this.onDone,
    this.dataReady,
  });

  final TriadCard fromCard;
  final TriadCard toCard;
  final CardGrowth growth;
  final double size;
  final VoidCallback onDone;
  final Future<void>? dataReady;

  @override
  State<_CardFlipTile> createState() => _CardFlipTileState();
}

class _CardFlipTileState extends State<_CardFlipTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 700),
        )..addStatusListener((status) async {
          if (status != AnimationStatus.completed) return;
          if (widget.dataReady != null) await widget.dataReady;
          if (mounted) widget.onDone();
        });
    _preloadAndStart();
  }

  /// Warms the image cache for both faces before turning the card — without
  /// this, the "to" card's art can still be mid-decode when the flip
  /// reaches the halfway point, so it briefly repaints the old art.
  Future<void> _preloadAndStart() async {
    final shiny = widget.growth.shiny == true;
    await Future.wait([
      TriadCardView.preloadAssets(widget.fromCard, shiny: shiny),
      TriadCardView.preloadAssets(widget.toCard, shiny: shiny),
    ]);
    if (mounted) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final angle = _ctrl.value * math.pi; // 0 -> pi over the whole flip
        final showBack = angle > math.pi / 2;
        // Un-mirror the back face so its content isn't drawn backwards.
        final displayAngle = showBack ? angle - math.pi : angle;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(displayAngle),
          // Both faces stay mounted for the whole flip (just toggled via
          // Offstage) so the "to" card's art starts loading from frame one
          // instead of only kicking off once the flip crosses the midpoint
          // — otherwise it briefly repaints the old art after the swap.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Offstage(
                offstage: showBack,
                child: TriadCardView(
                  key: ValueKey('flip_from_${widget.fromCard.id}'),
                  card: widget.fromCard,
                  size: widget.size,
                  growth: widget.growth,
                ),
              ),
              Offstage(
                offstage: !showBack,
                child: TriadCardView(
                  key: ValueKey('flip_to_${widget.toCard.id}'),
                  card: widget.toCard,
                  size: widget.size,
                  growth: widget.growth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.ascending,
    this.icon,
  });

  final String label;
  final bool active;
  final bool? ascending; // null = not active, true=↑, false=↓
  final Widget? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3A3C44) : const Color(0xFF282A30),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? const Color(0xFF74777F) : const Color(0xFF1A1C20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 4)],
              Text(label, style: TextStyle(color: active ? Colors.white : Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600, fontSize: 12)),
              if (ascending != null) ...[const SizedBox(width: 2), Icon(ascending! ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: active ? Colors.white54 : Colors.white24)],
            ],
          ),
        ),
      ),
    );
  }
}

class _RarityTile extends StatelessWidget {
  final CardRarity? rarity;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RarityTile(
    this.rarity,
    this.label, {
    required this.selected,
    required this.onTap,
  });

  IconData? _rarityIcon(CardRarity? r) {
    switch (r) {
      case CardRarity.common:
        return Icons.star_border;
      case CardRarity.uncommon:
        return Icons.star_half;
      case CardRarity.rare:
        return Icons.star;
      case CardRarity.epic:
        return Icons.diamond;
      case CardRarity.legendary:
        return Icons.auto_awesome;
      default:
        return null;
    }
  }

  Color _rarityColor(CardRarity? r) {
    switch (r) {
      case CardRarity.common:
        return Colors.grey;
      case CardRarity.uncommon:
        return Colors.green;
      case CardRarity.rare:
        return Colors.blue;
      case CardRarity.epic:
        return Colors.purple;
      case CardRarity.legendary:
        return Colors.amber;
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _rarityIcon(rarity);
    final color = _rarityColor(rarity);
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white12,
          foregroundColor: selected ? color : Colors.white70,
        ),
        child: Row(
          children: [
            if (icon != null)
              Icon(icon, size: 20, color: selected ? color : Colors.white54),
            if (icon != null) const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatefulWidget {
  const _CardTile({super.key, required this.onTap, this.onLongPress, required this.child});
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  @override State<_CardTile> createState() => _CardTileState();
}
class _CardTileState extends State<_CardTile> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
  late final _scale = Tween(begin: 1.0, end: 0.92).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  @override void initState() { super.initState(); _ctrl.addStatusListener((s) { if (s == AnimationStatus.completed) _ctrl.reverse(); }); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _ctrl.forward(), onTapUp: (_) => Future.delayed(const Duration(milliseconds: 50), () { if (mounted) _ctrl.reverse(); }), onTapCancel: () => _ctrl.reverse(),
    onTap: widget.onTap, onLongPress: widget.onLongPress,
    child: AnimatedBuilder(animation: _scale, builder: (_, c) => Transform.scale(scale: _scale.value, child: c), child: widget.child),
  );
}

String? _setIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('field')) return 'assets/images/Booster Pack/fieldicon.png';
  if (lower.contains('safari')) return 'assets/images/Booster Pack/safariicon.png';
  if (lower.contains('urban')) return 'assets/images/Booster Pack/urbanicon.png';
  if (lower.contains('kanto')) return 'assets/images/Booster Pack/fieldicon.png';
  return null;
}

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: sets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final set = sets[index];
          final selected = set.id == selectedSetId;
          final iconPath = _setIcon(set.name);
          return GestureDetector(
            onTap: () => onChanged(set.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF3A3C44) : const Color(0xFF282A30),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? const Color(0xFF74777F) : const Color(0xFF1A1C20)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (iconPath != null) ...[
                  Image.asset(iconPath, width: 20, height: 20),
                  const SizedBox(width: 6),
                ],
                Text(set.name, style: TextStyle(color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ── Card detail painter helpers ──

class _DiagonalTopClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.55);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.22);
    path.close();
    return path;
  }
  @override bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DetailShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = 14.0;
    final glowPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), glowPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, glowPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), glowPaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HoloShimmer extends StatefulWidget {
  final Widget child;
  const _HoloShimmer({required this.child});
  @override State<_HoloShimmer> createState() => _HoloShimmerState();
}

class _HoloShimmerState extends State<_HoloShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override void initState() { super.initState(); _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(); }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final hue = (_ctrl.value * 360) % 360;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [HSLColor.fromAHSL(1, hue, 0.9, 0.6).toColor(), HSLColor.fromAHSL(1, (hue + 180) % 360, 0.9, 0.6).toColor()],
          ).createShader(bounds),
          child: widget.child,
        );
      },
    );
  }
}
