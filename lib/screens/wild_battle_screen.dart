import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/story_progress_controller.dart';
import '../models/card_values.dart';
import '../models/deck.dart';
import '../models/story_location.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import 'battle_screen.dart';
import 'janken_screen.dart';
import 'oaks_lab_screen.dart';
import 'route_battle_screen.dart';

class WildBattleLocationScreen extends StatefulWidget {
  const WildBattleLocationScreen({super.key});

  @override
  State<WildBattleLocationScreen> createState() => _WildBattleLocationScreenState();
}

class _WildBattleLocationScreenState extends State<WildBattleLocationScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: notifyListeners() fires after _loadRoutes() within initialize(),
    // which triggers context.watch<> rebuild. Don't await — _syncProgress() may hang.
    context.read<StoryProgressController>().initialize();
  }

  static const _imageMap = {
    'pallet_town': 'assets/locations/pallet.png',
    'route_1': 'assets/locations/route1.png',
    'viridian_city': 'assets/locations/viridian.png',
    'route_22': 'assets/locations/kanto.png',
    'route_2': 'assets/locations/route2.png',
    'viridian_forest': 'assets/locations/viridianforest.png',
    'pewter_city': 'assets/locations/oakslab.png',
    'route_3': 'assets/locations/kanto.png',
    'mt_moon': 'assets/locations/route2.png',
    'route_4': 'assets/locations/kanto.png',
    'cerulean_city': 'assets/locations/oakslab.png',
    'route_24': 'assets/locations/kanto.png',
    'route_25': 'assets/locations/kanto.png',
    'route_5': 'assets/locations/kanto.png',
    'route_6': 'assets/locations/kanto.png',
    'vermilion_city': 'assets/locations/oakslab.png',
    'route_11': 'assets/locations/kanto.png',
    'route_9': 'assets/locations/kanto.png',
    'route_10': 'assets/locations/kanto.png',
    'rock_tunnel': 'assets/locations/kanto.png',
    'lavender_town': 'assets/locations/oakslab.png',
    'route_8': 'assets/locations/kanto.png',
    'route_7': 'assets/locations/kanto.png',
    'celadon_city': 'assets/locations/oakslab.png',
    'route_16': 'assets/locations/kanto.png',
    'route_17': 'assets/locations/kanto.png',
    'route_18': 'assets/locations/kanto.png',
    'fuchsia_city': 'assets/locations/oakslab.png',
    'route_15': 'assets/locations/kanto.png',
    'route_14': 'assets/locations/kanto.png',
    'route_13': 'assets/locations/kanto.png',
    'route_12': 'assets/locations/kanto.png',
    'saffron_city': 'assets/locations/oakslab.png',
    'route_19': 'assets/locations/kanto.png',
    'route_20': 'assets/locations/kanto.png',
    'seafoam_islands': 'assets/locations/kanto.png',
    'cinnabar_island': 'assets/locations/oakslab.png',
    'pokemon_mansion': 'assets/locations/kanto.png',
    'route_21': 'assets/locations/kanto.png',
    'route_23': 'assets/locations/kanto.png',
    'victory_road': 'assets/locations/kanto.png',
    'indigo_plateau': 'assets/locations/oakslab.png',
  };

  String _imageFor(String id) => _imageMap[id] ?? 'assets/locations/kanto.png';

  bool _hasWildEncounters(StoryLocation loc) {
    for (final node in loc.nodes) {
      if ((node.type == StoryNodeType.wild || node.type == StoryNodeType.wildBoss) &&
          node.encounterTable != null && node.encounterTable!.isNotEmpty) return true;
    }
    return false;
  }

  List<String> _speciesFrom(StoryLocation loc) {
    final cardIds = <String>{};
    for (final node in loc.nodes) {
      if (node.encounterTable != null) {
        for (final entry in node.encounterTable!) { cardIds.add(entry.cardId); }
      }
    }
    return cardIds.map((cid) {
      final card = CardRepository.instance.cardById(cid);
      return card?.name ?? cid.replaceAll('card_', '').replaceAll('_1', '');
    }).toList();
  }

  bool _isRoute(StoryLocation loc) => _hasWildEncounters(loc) && loc.wildLevelRange.max > 0;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<StoryProgressController>();
    final pCtrl = context.watch<PlayerProfileController>();
    final trainerLevel = pCtrl.trainerLevel;
    final all = ctrl.locations;
    final unlocked = ctrl.unlockedLocations;

    // Parse unlock requirement: "trainerLevel:N" → N
    int? _requiredLevel(StoryLocation loc) {
      final req = loc.unlockRequirement;
      if (req == null) return null;
      final m = RegExp(r'trainerLevel:(\d+)').firstMatch(req);
      return m != null ? int.tryParse(m.group(1)!) : null;
    }

    if (all.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF141414),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A), elevation: 0,
          title: const Text('CHOOSE A LOCATION', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 3)),
          centerTitle: true,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A), elevation: 0,
        title: const Text('CHOOSE A LOCATION', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 3)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: all.length,
        itemBuilder: (ctx, i) {
          final loc = all[i];
          final reqLv = _requiredLevel(loc);
          final lvLocked = reqLv != null && trainerLevel < reqLv;
          final locked = !unlocked.contains(loc.id) || lvLocked;
          final isRoute = _isRoute(loc);
          final species = _speciesFrom(loc);
          final lv = loc.wildLevelRange.max > 0 ? '${loc.wildLevelRange.min}–${loc.wildLevelRange.max}' : null;
          // Extract town facility info from nodes
          bool hasGym = false, hasMart = false, hasCenter = false, hasLab = false;
          String? gymNpcId;
          for (final n in loc.nodes) {
            if (n.npcId != null) { hasGym = true; gymNpcId = n.npcId; }
            if (n.id.contains('pokemart') || n.id.contains('mart')) hasMart = true;
            if (n.id.contains('center')) hasCenter = true;
            if (n.id.contains('oaks_lab') || n.id.contains('lab')) hasLab = true;
          }
          return _LocationCard(id: loc.id, name: loc.name, imageAsset: _imageFor(loc.id),
            species: species, levelRange: lv, locked: locked, isRoute: isRoute,
            hasGym: hasGym, hasMart: hasMart, hasCenter: hasCenter, hasLab: hasLab, gymNpcId: gymNpcId,
            lockReason: lvLocked ? 'Requires Trainer Level $reqLv' : null,
            reqLevel: reqLv);
        },
      ),
    );
  }
}

// ── Location card ──

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.id, required this.name, required this.imageAsset, required this.species, required this.levelRange, required this.locked, required this.isRoute, this.hasGym = false, this.hasMart = false, this.hasCenter = false, this.hasLab = false, this.gymNpcId, this.lockReason, this.reqLevel});
  final String id, name, imageAsset;
  final List<String> species;
  final String? levelRange, lockReason;
  final int? reqLevel;
  final bool locked, isRoute, hasGym, hasMart, hasCenter, hasLab;
  final String? gymNpcId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: locked
            ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lockReason ?? 'Locked \u2014 complete the previous location first.'), duration: const Duration(seconds: 1)))
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => WildBattleDetailScreen(locationId: id, locationName: name, imageAsset: imageAsset, species: species, levelRange: levelRange, hasGym: hasGym, hasMart: hasMart, hasCenter: hasCenter, hasLab: hasLab, gymNpcId: gymNpcId))),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E1E1E), Color(0xFF181818)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: locked ? const Color(0xFF333333) : const Color(0xFF444444)),
          ),
          child: Row(children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
              child: ColorFiltered(
                colorFilter: locked ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: Image.asset(imageAsset, width: 100, height: 90, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 100, height: 90, color: Colors.white.withValues(alpha: 0.05), child: const Icon(Icons.landscape, color: Colors.white24))),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(name, style: TextStyle(color: locked ? Colors.white38 : Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                    child: Text(isRoute ? 'ROUTE' : 'TOWN', style: TextStyle(color: locked ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.5), fontSize: 9, fontWeight: FontWeight.w700))),
                  if (locked) ...[const SizedBox(width: 8), const Icon(Icons.lock, color: Colors.white24, size: 16)],
                ]),
                const SizedBox(height: 6),
                if (locked && lockReason != null)
                  Text(lockReason!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600))
                else if (locked)
                  Text('Complete previous location to unlock', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12))
                  else if (!locked && !isRoute)
                    const SizedBox.shrink()
                else if (!locked && !isRoute)
                  Text('Pok\u00e9 Mart \u2022 Pok\u00e9mon Center', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                if (reqLevel != null && !locked) ...[
                  const SizedBox(height: 2),
                  Text('Required: TL $reqLevel', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                ],
              ]),
            )),
            Padding(padding: const EdgeInsets.only(right: 12), child: Icon(locked ? Icons.lock : Icons.chevron_right, color: locked ? Colors.white12 : Colors.white38)),
          ]),
        ),
      ),
    );
  }
}

// ── Location detail screen ──

class WildBattleDetailScreen extends StatelessWidget {
  const WildBattleDetailScreen({super.key, required this.locationId, required this.locationName, required this.imageAsset, required this.species, required this.levelRange, this.hasGym = false, this.hasMart = false, this.hasCenter = false, this.hasLab = false, this.gymNpcId});
  final String locationId, locationName, imageAsset;
  final List<String> species;
  final String? levelRange;
  final bool hasGym, hasMart, hasCenter, hasLab;
  final String? gymNpcId;

  @override
  Widget build(BuildContext context) {
    final total = species.length;
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A), elevation: 0,
        title: Text(locationName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 4)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.asset(imageAsset, width: double.infinity, height: 140, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(height: 140, color: Colors.white.withValues(alpha: 0.05), child: const Icon(Icons.landscape, color: Colors.white24, size: 48)))),
          const SizedBox(height: 20),
          if (species.isNotEmpty) ...[
            // Species Found
            _buildSpeciesFound(context, species, levelRange),
            const SizedBox(height: 20),
            _BattleModeButton(icon: Icons.shuffle, label: 'Random Wild Battle', subtitle: 'Face a random $locationName Pokémon.', color: const Color(0xFF4CAF50), onTap: () => _startRandomWildBattle(context, locationId, locationName)),
            const SizedBox(height: 10),
            _BattleModeButton(icon: Icons.search, label: 'Species Hunt', subtitle: 'Target a Pok\u00e9mon you\'ve discovered.', color: const Color(0xFF42A5F5), onTap: () => _speciesPicker(context, species)),
            const SizedBox(height: 10),
            _BattleModeButton(icon: Icons.whatshot, label: 'Strong Encounter', subtitle: 'Higher-level Pokémon, better rewards.', color: const Color(0xFFFF7043), onTap: () => _startRandomWildBattle(context, locationId, locationName)),
            const SizedBox(height: 10),
            _BattleModeButton(icon: Icons.auto_awesome, label: 'Shiny Hunt', subtitle: 'Slightly improved shiny odds.', color: const Color(0xFFFFCA28), onTap: () => _startRandomWildBattle(context, locationId, locationName)),
            const Spacer(),
          ] else ...[
            const SizedBox(height: 8),
            if (hasGym) ...[
              _BattleModeButton(icon: Icons.emoji_events, label: 'Gym Leader', subtitle: gymNpcId != null ? 'Challenge ${gymNpcId![0].toUpperCase()}${gymNpcId!.substring(1)} to earn a badge.' : 'Challenge the Gym Leader.', color: const Color(0xFFFFCA28), onTap: () => _snack(context, 'Gym Battle — Coming soon!')),
              const SizedBox(height: 10),
            ],
            if (hasLab) ...[
              _BattleModeButton(icon: Icons.science, label: "Oak's Lab", subtitle: 'Visit Professor Oak for research and quests.', color: const Color(0xFF66BB6A), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OaksLabScreen()))),
              const SizedBox(height: 10),
            ],
            if (hasCenter) ...[
              _BattleModeButton(icon: Icons.local_hospital, label: 'Pokémon Center', subtitle: 'Heal your Pokémon and rest.', color: const Color(0xFFEF5350), onTap: () => _snack(context, 'Pokémon Center — Coming soon!')),
              const SizedBox(height: 10),
            ],
            if (hasMart) ...[
              _BattleModeButton(icon: Icons.store, label: 'Poké Mart', subtitle: 'Buy cards, boosters, and consumables.', color: const Color(0xFF42A5F5), onTap: () => _snack(context, 'Poké Mart — Coming soon!')),
              const SizedBox(height: 10),
            ],
            _BattleModeButton(icon: Icons.assignment, label: 'Missions', subtitle: 'Pick up quests and earn rewards.', color: const Color(0xFFAB47BC), onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => RouteBattleScreen(locationId: locationId)));
            }),
            const Spacer(),
          ],
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  static void _startRandomWildBattle(BuildContext context, String locationId, String locationName) {
    final storyCtrl = context.read<StoryProgressController>();
    final profileCtrl = context.read<PlayerProfileController>();
    final location = storyCtrl.locations.firstWhere((l) => l.id == locationId);

    // Find the first wild node with an encounter table
    StoryNode? wildNode;
    for (final node in location.nodes) {
      if (node.encounterTable != null && node.encounterTable!.isNotEmpty) {
        wildNode = node;
        break;
      }
    }

    if (wildNode == null) {
      _snack(context, 'No wild encounters at this location.');
      return;
    }

    // Get player deck
    final profile = profileCtrl.profile;
    Deck? playerDeck = profile.defaultDeck;
    playerDeck ??= profile.decks.where((d) => d.isValid).firstOrNull;
    if (playerDeck == null) {
      _snack(context, 'You need a 5-card deck before battling.');
      return;
    }

    // Roll a random encounter (weighted)
    final card = _rollEncounter(wildNode.encounterTable!);
    final lvRange = location.wildLevelRange;
    final rng = Random();

    // Mark this card as seen in the Pokédex
    profileCtrl.markCardSeen(card.id);

    // Build 5 wild cards with random levels and shiny chance
    final wildCards = <TriadCard>[];
    for (var i = 0; i < 5; i++) {
      final level = lvRange.min + rng.nextInt(lvRange.max - lvRange.min + 1);
      final isShiny = rng.nextInt(16) == 0;

      // Base stats: same as the card (no bonus for levels <= 5).
      // Level > 5: 10% chance per extra level of +1 to a random direction.
      var bonusN = 0, bonusS = 0, bonusE = 0, bonusW = 0;
      final extraLevels = level - 5;
      for (var j = 0; j < extraLevels; j++) {
        if (rng.nextInt(10) == 0) {
          switch (rng.nextInt(4)) {
            case 0: bonusN++; break;
            case 1: bonusS++; break;
            case 2: bonusE++; break;
            case 3: bonusW++; break;
          }
        }
      }
      final bonus = CardValues(north: bonusN, south: bonusS, east: bonusE, west: bonusW);

      wildCards.add(card.copyWith(
        values: card.values.plusBonus(bonus),
        shiny: isShiny || card.shiny,
        baseLevel: level,
      ));
    }

    final wildDeck = Deck(
      id: 'wild_${locationId}_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Wild ${card.name}',
      cardIds: List.filled(5, card.id),
      opponentCards: wildCards,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JankenScreen(
          opponentName: 'Wild ${card.name}',
          opponentPortrait: 'pokeball.png',
          opponentCardImage: card.image,
          rules: const ['Rock', 'Paper', 'Scissors'],
          onComplete: ({required player, required opponent, required playerGoesFirst}) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BattleScreen(
                  playerDeck: playerDeck!,
                  opponentDeck: wildDeck,
                  opponentName: 'Wild ${card.name}',
                  opponentPortrait: null,
                  opponentVictoryQuote: null,
                  opponentDefeatQuote: null,
                  playerGoesFirst: playerGoesFirst,
                  opponentCards: wildCards,
                  onMatchComplete: (won) {
                    if (won) {
                      final storyCtrl = context.read<StoryProgressController>();
                      final loc = storyCtrl.locations.firstWhere((l) => l.id == locationId);
                      for (final node in loc.nodes) {
                        if (node.type == StoryNodeType.wild && !node.isCompleted) {
                          storyCtrl.completeNode(locationId, node.id);
                          break;
                        }
                      }
                    }
                  },
                  onContinue: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static TriadCard _rollEncounter(List<WildEncounterEntry> table) {
    final totalWeight = table.fold<int>(0, (sum, e) => sum + e.weight);
    var roll = Random().nextInt(totalWeight);
    for (final entry in table) {
      roll -= entry.weight;
      if (roll < 0) {
        return CardRepository.instance.cardById(entry.cardId) ??
            TriadCard.fallback();
      }
    }
    return CardRepository.instance.cardById(table.first.cardId) ??
        TriadCard.fallback();
  }

  static void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));

  static Widget _buildSpeciesFound(BuildContext context, List<String> species, String? levelRange) {
    final profileCtrl = context.read<PlayerProfileController>();
    final ownedCards = profileCtrl.profile.ownedCardIds;
    final seenCards = profileCtrl.seenCardIds;
    final repo = CardRepository.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Species Found', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: species.map((name) {
              final cardId = 'card_${name.toLowerCase()}_1';
              final card = repo.cardById(cardId);
              final captured = card != null && ownedCards.contains(cardId);
              final seen = card != null && seenCards.contains(cardId);
              final iconPath = 'assets/images/icons/${name.toUpperCase()}.png';
              final label = seen ? '$name${levelRange != null ? ' (lvl $levelRange)' : ''}' : '???';
              final labelColor = captured ? Colors.white : seen ? Colors.white54 : Colors.white24;

              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: captured ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: captured ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: ColorFiltered(
                          colorFilter: captured
                              ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                              : seen
                                  ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                                  : const ColorFilter.matrix(<double>[
                                      0.0, 0.0, 0.0, 0.0, 0.0,
                                      0.0, 0.0, 0.0, 0.0, 0.0,
                                      0.0, 0.0, 0.0, 0.0, 0.0,
                                      0.0, 0.0, 0.0, 1.0, 0.0,
                                    ]),
                          child: Image.asset(iconPath, width: 36, height: 36, fit: BoxFit.cover, alignment: Alignment.topLeft,
                            errorBuilder: (_, __, ___) => const Icon(Icons.help_outline, color: Colors.white12, size: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  static void _speciesPicker(BuildContext context, List<String> species) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1A1A2E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (_) {
      return Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CHOOSE SPECIES', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 3)),
        const SizedBox(height: 16),
        ...species.map((s) => ListTile(leading: const Icon(Icons.catching_pokemon, color: Colors.white54), title: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right, color: Colors.white24), onTap: () { Navigator.pop(context); _snack(context, '$s hunt \u2014 Coming soon!'); })),
      ]));
    });
  }
}

// ── Helpers ──

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
      child: Column(children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
      ]),
    ));
  }
}

class _BattleModeButton extends StatelessWidget {
  const _BattleModeButton({required this.icon, required this.label, required this.subtitle, required this.color, this.locked = false, this.lockLabel, this.onTap});
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final bool locked;
  final String? lockLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = locked;
    return GestureDetector(
      onTap: disabled ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Locked \u2014 complete location objectives to unlock.'), duration: Duration(seconds: 1))) : onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: disabled ? Colors.white.withValues(alpha: 0.03) : color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: disabled ? Colors.white.withValues(alpha: 0.06) : color.withValues(alpha: 0.25))),
        child: Row(children: [
          Icon(icon, color: disabled ? Colors.white.withValues(alpha: 0.2) : color, size: 26), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: TextStyle(color: disabled ? Colors.white.withValues(alpha: 0.3) : color, fontSize: 15, fontWeight: FontWeight.w700)),
              if (disabled && lockLabel != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)), child: Text(lockLabel!, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.w700)))],
            ]),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: disabled ? Colors.white.withValues(alpha: 0.15) : color.withValues(alpha: 0.6), fontSize: 12)),
          ])),
          if (!disabled) Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}
