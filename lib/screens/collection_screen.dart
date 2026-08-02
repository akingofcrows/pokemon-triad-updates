import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../game/cards/card_visuals.dart';
import '../models/card_growth.dart';
import '../models/card_set.dart';
import '../models/evolution_chain.dart';
import '../models/pokemon_leveling.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/sprite_downloader.dart';
import '../widgets/evolution_animation.dart';
import '../widgets/triad_card_view.dart';

enum _SortMode { number, rarity, type, level, name }

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

    final setCardIds = selectedSet.cardIds.toSet();
    var owned = instances.where((i) => setCardIds.contains(i.cardId)).toList();
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
          return asc
              ? ca.affinity.compareTo(cb.affinity)
              : cb.affinity.compareTo(ca.affinity);
        });
    }

    void selectSort(_SortMode mode, {bool defaultAsc = true}) {
      setState(() {
        if (_sortMode == mode) {
          _sortAscending = !_sortAscending;
        } else {
          _sortMode = mode;
          _sortAscending = defaultAsc;
          if (mode != _SortMode.rarity) _rarityFilter = null;
          if (mode != _SortMode.type) _typeFilter = null;
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        actions: [
          _SortChip(
            label: 'Name',
            active: _sortMode == _SortMode.name,
            ascending: _sortMode == _SortMode.name ? _sortAscending : null,
            onTap: () => selectSort(_SortMode.name),
          ),
          _SortChip(
            label: 'Num',
            active: _sortMode == _SortMode.number,
            ascending: _sortMode == _SortMode.number ? _sortAscending : null,
            onTap: () => selectSort(_SortMode.number),
          ),
          _SortChip(
            label: 'Lv',
            active: _sortMode == _SortMode.level,
            ascending: _sortMode == _SortMode.level ? _sortAscending : null,
            onTap: () => selectSort(_SortMode.level, defaultAsc: false),
          ),
          _SortChip(
            label: _rarityFilter != null
                ? _capitalize(_rarityFilter!.name)
                : 'Rarity',
            active: _sortMode == _SortMode.rarity || _rarityFilter != null,
            onTap: () => _showRarityModal(),
          ),
          _SortChip(
            label: _typeFilter != null ? _capitalize(_typeFilter!) : 'Type',
            icon: _typeFilter != null
                ? Image.asset(
                    typeIconAsset(_typeFilter!),
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )
                : null,
            active: _sortMode == _SortMode.type || _typeFilter != null,
            onTap: () => _showTypeModal(),
          ),
          const SizedBox(width: 4),
        ],
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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${owned.length} cards',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: owned.length,
              itemBuilder: (context, index) {
                final instance = owned[index];
                final pending = instance.instanceId != null
                    ? _flippingInstances[instance.instanceId]
                    : null;
                final card =
                    pending?.to ?? repository.cardById(instance.cardId);
                if (card == null) return const SizedBox.shrink();
                return GestureDetector(
                  key: ValueKey(instance.instanceId),
                  onTap: () => _showCardDetail(context, card, instance),
                  child: Stack(
                    children: [
                      if (pending != null)
                        _CardFlipTile(
                          key: ValueKey('flip_${instance.instanceId}'),
                          fromCard: pending.from,
                          toCard: pending.to,
                          growth: instance,
                          size: 100,
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
                        TriadCardView(card: card, size: 100, growth: instance),
                      if (card.cardType == TriadCardType.pokemon)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Lv.${instance.level}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 2,
                                    offset: Offset(1, 1),
                                  ),
                                ],
                              ),
                            ),
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
    );
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
        sorted.sort((a, b) => a.affinity.compareTo(b.affinity));
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

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${card.name} (Lv.$level) - #${card.cardNumber}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            final instanceId = growth?.instanceId;
                            if (instanceId == null) return;
                            final added = ctrl.toggleFavorite(instanceId);
                            setDialogState(() {});
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  added
                                      ? 'Added to favorites!'
                                      : 'Removed from favorites',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Builder(
                            builder: (ctx) {
                              final iid = growth?.instanceId;
                              final fav = iid != null && ctrl.isFavorite(iid);
                              return Icon(
                                fav ? Icons.star : Icons.star_border,
                                color: fav
                                    ? const Color(0xFFC9A44C)
                                    : Colors.white38,
                                size: 24,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shiny indicator
                  if (growth?.shiny == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.red, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Shiny',
                            style: TextStyle(
                              color: Colors.red.shade300,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Card image
                  Center(
                    child: TriadCardView(card: card, size: 140, growth: growth),
                  ),
                  const SizedBox(height: 12),
                  // Type icon + name → right
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _capitalize(card.affinity),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 6),
                      Image.asset(
                        typeIconAsset(card.affinity),
                        width: 20,
                        height: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Rarity display
                  Row(children: [_buildRarityDisplay(card.rarity)]),
                  const SizedBox(height: 6),
                  // XP bar (Pokémon only)
                  if (card.cardType == TriadCardType.pokemon) ...[
                    const SizedBox(height: 10),
                    ..._buildXpBar(growth),
                  ],
                  const SizedBox(height: 14),
                  // NSEW — bold letters, numbers centered below, bonuses in green
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _statColumn(
                          'N',
                          effectiveValues.north,
                          bonus: growth?.bonusNorth ?? 0,
                        ),
                        const SizedBox(width: 24),
                        _statColumn(
                          'S',
                          effectiveValues.south,
                          bonus: growth?.bonusSouth ?? 0,
                        ),
                        const SizedBox(width: 24),
                        _statColumn(
                          'E',
                          effectiveValues.east,
                          bonus: growth?.bonusEast ?? 0,
                        ),
                        const SizedBox(width: 24),
                        _statColumn(
                          'W',
                          effectiveValues.west,
                          bonus: growth?.bonusWest ?? 0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Evolution line — always at bottom, centered
                  if (card.cardType == TriadCardType.pokemon)
                    _buildEvolutionChain(
                      card,
                      context.read<PlayerProfileController>().cardGrowth,
                      isShiny: growth?.shiny == true,
                    ),
                  if (card.cardType == TriadCardType.pokemon)
                    const SizedBox(height: 8),
                  // OT / Obtained
                  Text(
                    'OT: ${trainerName ?? '—'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  Text(
                    'Obtained: ${growth?.humanizedSource ?? '—'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  // Evolve buttons
                  for (final evo in evolutions)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton(
                        onPressed: () async {
                          final toCard = CardRepository.instance.cardById(
                            evo.to,
                          );
                          debugPrint(
                            '[EVOLVE] collection: cardId=${card.id} toId=${evo.to} instanceId=${growth?.instanceId}',
                          );

                          // Confirm dialog to prevent evolving the wrong instance
                          final shinyLabel = (growth?.shiny == true)
                              ? ' ✨Shiny'
                              : '';
                          final confirm = await showDialog<bool>(
                            context: dialogContext,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Confirm Evolution'),
                              content: Text(
                                'Evolve ${card.name}$shinyLabel (Lv.${growth?.level ?? 1}) '
                                'into ${toCard?.name ?? evo.to}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Evolve!'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;

                          Navigator.pop(dialogContext);
                          if (toCard == null) {
                            context.read<PlayerProfileController>().evolveCard(
                              card.id,
                              evo.to,
                              instanceId: growth?.instanceId,
                            );
                            return;
                          }
                          // Kick the real evolve off now, in parallel with
                          // the animation — it needs the whole ~5s
                          // strobe/flash/slam runway anyway before the
                          // evolved card's real (post-loss) bonus is ever
                          // shown, and the collection grid's flip tile
                          // waits on this same future before handing back
                          // to the plain grid view.
                          final evolveFuture = context
                              .read<PlayerProfileController>()
                              .evolveCard(
                                card.id,
                                evo.to,
                                instanceId: growth?.instanceId,
                              );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (ctx) => EvolutionAnimation(
                                fromCard: card.copyWith(
                                  shiny: growth?.shiny == true,
                                ),
                                toCard: toCard.copyWith(
                                  shiny: growth?.shiny == true,
                                ),
                                fromBonuses: growth?.bonusValues,
                                toBonusesFuture: evolveFuture,
                                onComplete: () => Navigator.pop(ctx),
                              ),
                            ),
                          ).then((_) {
                            if (!context.mounted) return;
                            final instId = growth?.instanceId;
                            if (instId != null) {
                              setState(() {
                                _flippingInstances[instId] = _PendingFlip(
                                  from: card.copyWith(
                                    shiny: growth?.shiny == true,
                                  ),
                                  to: toCard.copyWith(
                                    shiny: growth?.shiny == true,
                                  ),
                                  dataReady: evolveFuture,
                                );
                              });
                            }
                          });
                        },
                        child: Text(
                          'Evolve into ${CardRepository.instance.cardById(evo.to)?.name ?? evo.to}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Center(
                    child: SizedBox(
                      width: 160,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(dialogContext),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white.withValues(alpha: 0.12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 1.2,
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
      // Use owned growth or create a synthetic shiny one for preview
      CardGrowth? effectiveGrowth = cardGrowth[cardId];
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active
            ? Colors.amber.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 4)],
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.amber : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (ascending != null)
                  Icon(
                    ascending! ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: active ? Colors.amber : Colors.white54,
                  ),
              ],
            ),
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
          return ChoiceChip(
            label: Text(set.name),
            selected: selected,
            onSelected: (_) => onChanged(set.id),
          );
        },
      ),
    );
  }
}
