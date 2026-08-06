import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../app/story_progress_controller.dart';
import '../models/card_values.dart';
import '../models/deck.dart';
import '../models/npc_trainer.dart';
import '../models/quest.dart';
import '../models/story_location.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/api_client.dart';
import '../widgets/triad_card_view.dart';
import 'battle_screen.dart';
import 'booster_pack_screen.dart';
import 'janken_screen.dart';

/// Displays the battle path for a specific story location.
///
/// Shows nodes in a vertical sequence — wild battles, trainer battles,
/// story scenes — that the player completes in order.
class RouteBattleScreen extends StatefulWidget {
  const RouteBattleScreen({super.key, required this.locationId});

  final String locationId;

  @override
  State<RouteBattleScreen> createState() => _RouteBattleScreenState();
}

class _RouteBattleScreenState extends State<RouteBattleScreen> {
  late StoryLocation _location;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = context.read<StoryProgressController>();
    _location = ctrl.locations.firstWhere((l) => l.id == widget.locationId);
    context.read<ApiClient>().updateLocation(_location.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_location.name.toUpperCase(),
            style: const TextStyle(letterSpacing: 3, fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Location background
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Image.asset(
                'assets/locations/${_location.id.replaceAll('_', '')}.png',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.darken,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1B5E20),
                        const Color(0xFF0D3311).withValues(alpha: 0.95),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Node path
          SafeArea(
            child: Consumer<StoryProgressController>(
              builder: (_, ctrl, __) {
                return _buildFocusedPath(ctrl);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Shows either a city hub (all nodes as buttons) or a route path.
  Widget _buildFocusedPath(StoryProgressController ctrl) {
    final isCity = _location.wildLevelRange.min == 0 && _location.wildLevelRange.max == 0;

    if (isCity) {
      return _buildCityHub(ctrl);
    }

    final completed = _location.nodes.where((n) => n.isCompleted).toList();
    final current = _location.nodes.firstWhere(
      (n) => n.isUnlocked && !n.isCompleted,
      orElse: () => _location.nodes.first,
    );
    final currentIdx = _location.nodes.indexOf(current);
    final allDone = _location.isFullyComplete;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 40),
      children: [
        // Title
        Center(
          child: Text(
            _location.name.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'PowerGreen',
              color: Colors.white,
              fontSize: 24,
              shadows: [
                Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        if (allDone) ...[
          _buildCompletionBanner(ctrl),
        ] else ...[
          // Completed nodes (compact)
          if (completed.isNotEmpty) ...[
            ...completed.map((n) => _buildCompactCompleted(n)),
            const SizedBox(height: 16),
          ],

          // Current active node (prominent)
          _buildActiveNode(ctrl, current, currentIdx),
        ],
      ],
    );
  }

  Widget _buildCompactCompleted(StoryNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
          const SizedBox(width: 10),
          Text(
            _nodeLabelFor(node),
            style: const TextStyle(
              fontFamily: 'PowerGreen',
              color: Colors.white,
              fontSize: 14,
              shadows: [
                Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveNode(StoryProgressController ctrl, StoryNode node, int index) {
    return _NodeCard(
      node: node,
      location: _location,
      enabled: true,
      onComplete: () => _onNodeTapped(ctrl, node),
    );
  }

  Widget _buildCompletionBanner(StoryProgressController ctrl) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber, size: 40),
              const SizedBox(height: 12),
              const Text('ROUTE COMPLETE!',
                  style: TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)),
              const SizedBox(height: 8),
              if (_location.completionUnlocks.isNotEmpty) ...[
                Text(
                  'New location unlocked:',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                ),
                const SizedBox(height: 4),
                ...(_location.completionUnlocks.map((u) => Text(
                      _humanizeLocation(u),
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.w600),
                    ))),
              ],
              const SizedBox(height: 16),
              Text(
                'All nodes can now be replayed.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _humanizeLocation(String id) {
    return id.replaceAll('_', ' ').split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  String _nodeLabelFor(StoryNode node) {
    switch (node.type) {
      case StoryNodeType.wild:
        return 'Wild Battle';
      case StoryNodeType.trainer:
        final npc = CardRepository.instance.npcs.firstWhere(
          (n) => n.id == node.npcId,
          orElse: () => CardRepository.instance.npcs.first,
        );
        return npc.name;
      case StoryNodeType.story:
        if (node.id.contains('pokemart')) return 'Poké Mart';
        if (node.id.contains('center')) return 'Pokémon Center';
        if (node.id.contains('oaks_lab') || node.id.contains('lab')) return "Oak's Lab";
        if (node.id.contains('missions')) return 'Missions';
        if (node.id.contains('house')) return 'My House';
        if (node.id.contains('route')) return 'Next Route';
        return 'Item Discovery';
      case StoryNodeType.wildBoss:
        return 'Final Encounter';
    }
  }

  Widget _buildCityHub(StoryProgressController ctrl) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 40),
      children: [
        Center(
          child: Text(
            _location.name.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'PowerGreen',
              color: Colors.white,
              fontSize: 24,
              shadows: [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // All nodes as hub buttons
        for (final node in _location.nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildHubButton(ctrl, node),
          ),
      ],
    );
  }

  Widget _buildHubButton(StoryProgressController ctrl, StoryNode node) {
    // Determine if node should be greyed out
    bool greyedOut = false;
    String? lockedReason;

    if (node.id == 'viridian_route2') {
      // Greyed out until parcel delivered
      final parcelDelivered = _location.nodes
          .firstWhere((n) => n.id == 'viridian_pokemart',
              orElse: () => node)
          .isCompleted;
      if (!parcelDelivered) {
        greyedOut = true;
        lockedReason = 'Deliver Oak\'s parcel first';
      }
    } else if (node.id == 'viridian_gym') {
      // Gym is optional for location completion — always accessible
    }

    final icon = node.isCompleted ? Icons.check_circle : _nodeIconFor(node);
    final color = greyedOut ? Colors.grey : (node.isCompleted ? Colors.greenAccent : _nodeColorFor(node));
    final label = _nodeLabelFor(node);
    final subtitle = node.isCompleted ? 'Complete' : (greyedOut ? lockedReason : _nodeSubtitleFor(node));

    return Material(
      color: Colors.black.withValues(alpha: greyedOut ? 0.25 : 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: greyedOut ? null : () => _onNodeTapped(ctrl, node),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: greyedOut ? 0.05 : 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          color: greyedOut ? Colors.grey : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        )),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                            color: greyedOut ? Colors.grey.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          )),
                  ],
                ),
              ),
              if (node.isCompleted)
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 24)
              else if (!greyedOut)
                Icon(Icons.arrow_forward, color: Colors.white.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _nodeIconFor(StoryNode node) {
    switch (node.type) {
      case StoryNodeType.wild: return Icons.grass;
      case StoryNodeType.trainer: return Icons.shield;
      case StoryNodeType.story:
        if (node.id.contains('pokemart')) return Icons.store;
        if (node.id.contains('center')) return Icons.local_hospital;
        if (node.id.contains('oaks_lab') || node.id.contains('lab')) return Icons.science;
        if (node.id.contains('missions')) return Icons.assignment;
        if (node.id.contains('house')) return Icons.home;
        if (node.id.contains('route')) return Icons.map;
        return Icons.place;
      case StoryNodeType.wildBoss: return Icons.warning;
    }
  }

  Color _nodeColorFor(StoryNode node) {
    switch (node.type) {
      case StoryNodeType.wild: return const Color(0xFF66BB6A);
      case StoryNodeType.trainer: return const Color(0xFFEF5350);
      case StoryNodeType.story: return const Color(0xFF42A5F5);
      case StoryNodeType.wildBoss: return const Color(0xFFEF5350);
    }
  }

  String? _nodeSubtitleFor(StoryNode node) {
    switch (node.type) {
      case StoryNodeType.wild: return 'Wild Battle';
      case StoryNodeType.trainer: return 'Gym Leader';
      case StoryNodeType.story:
        if (node.id.contains('pokemart')) return 'Poké Mart';
        if (node.id.contains('center')) return 'Pokémon Center';
        if (node.id.contains('oaks_lab') || node.id.contains('lab')) return "Professor Oak's Laboratory";
        if (node.id.contains('missions')) return 'Quests & Missions';
        if (node.id.contains('house')) return 'Your home';
        if (node.id.contains('route')) return 'Travel to next area';
        return null;
      case StoryNodeType.wildBoss: return null;
    }
  }

  void _onNodeTapped(StoryProgressController ctrl, StoryNode node) {
    switch (node.type) {
      case StoryNodeType.wild:
      case StoryNodeType.wildBoss:
        _startWildBattle(ctrl, node);
        break;
      case StoryNodeType.trainer:
        _startTrainerBattle(ctrl, node);
        break;
      case StoryNodeType.story:
        _showStoryScene(ctrl, node);
        break;
    }
  }

  void _startWildBattle(StoryProgressController ctrl, StoryNode node) {
    final card = _rollWildEncounter(node);
    final lvRange = _location.wildLevelRange;
    final rng = Random();

    // Build 5 individual cards with random levels and shiny chance
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
      id: 'wild_${node.id}',
      name: 'Wild ${card.speciesId}',
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
                  playerDeck: _playerDeck,
                  opponentDeck: wildDeck,
                  opponentName: 'Wild ${card.name}',
                  opponentPortrait: null,
                  opponentVictoryQuote: null,
                  opponentDefeatQuote: null,
                  playerGoesFirst: playerGoesFirst,
                  onMatchComplete: (won, {capturedCardIds}) {
                    if (won) ctrl.completeNode(_location.id, node.id);
                  },
                  onContinue: () {
                    Navigator.of(context).popUntil((route) => route.isFirst || route.settings.name == AppRoutes.storyMode);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _startTrainerBattle(StoryProgressController ctrl, StoryNode node) {
    final npc = CardRepository.instance.npcs.firstWhere(
      (n) => n.id == node.npcId,
      orElse: () => CardRepository.instance.npcs.first,
    );

    final opponentDeck = Deck(
      id: 'npc_${npc.id}',
      name: npc.name,
      cardIds: npc.cardIds,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JankenScreen(
          opponentName: npc.name,
          opponentPortrait: npc.portraitAsset,
          rules: const ['Rock', 'Paper', 'Scissors'],
          onComplete: ({required player, required opponent, required playerGoesFirst}) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => BattleScreen(
                  playerDeck: _playerDeck,
                  opponentDeck: opponentDeck,
                  opponentName: npc.name,
                  opponentPortrait: npc.portraitAsset,
                  opponentVictoryQuote: npc.victoryQuote,
                  opponentDefeatQuote: npc.defeatQuote,
                  playerGoesFirst: playerGoesFirst,
                  onMatchComplete: (won, {capturedCardIds}) {
                    if (won) ctrl.completeNode(_location.id, node.id);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showStoryScene(StoryProgressController ctrl, StoryNode node) {
    final isPallet = _location.id == 'pallet_town';
    final isViridian = _location.id == 'viridian_city';
    final profileCtrl = context.read<PlayerProfileController>();

    if (node.id == 'pallet_missions') {
      _showOakParcelQuest(ctrl, node, profileCtrl);
    } else if (node.id == 'pallet_oaks_lab') {
      profileCtrl.completeObjective('Visit Professor Oak at his lab');
      ctrl.completeNode(_location.id, node.id);
      Navigator.pushNamed(context, AppRoutes.oaksLab);
    } else if (node.id == 'pallet_house') {
      ctrl.completeNode(_location.id, node.id);
      Navigator.pushNamed(context, AppRoutes.houseDownstairs);
    } else if (node.id == 'pallet_route1') {
      ctrl.completeNode(_location.id, node.id);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RouteBattleScreen(locationId: 'route_1')),
      );
    } else if (node.id == 'viridian_pokemart') {
      if (node.isCompleted) {
        _showPokeMartShop(ctrl, node);
      } else {
        _showShopkeeperDialog(ctrl, node);
      }
    } else if (node.id == 'viridian_center') {
      _showDialog(ctrl, node,
        title: '🏥 POKÉMON CENTER',
        content: 'A warm, welcoming place to rest and heal your Pokémon.\n\n'
            'Nurse Joy smiles as you enter.\n\n'
            '"We\'re not fully staffed yet, but come back anytime!"',
        button: 'Look around');
    } else if (node.id == 'viridian_route2') {
      _showDialog(ctrl, node,
        title: '🛣️ ROUTE 2',
        content: 'The path north leads toward Viridian Forest and Pewter City.\n\n'
            'Best to finish your business in town before heading out.',
        button: 'Not yet');
    } else {
      _showDialog(ctrl, node,
        title: '📦 Item Found!',
        content: 'You found a Poké Ball along the path!\n\n'
            'It might come in handy for catching wild Pokémon.',
        button: 'Take it');
    }
  }

  void _showPokeMartShop(StoryProgressController ctrl, StoryNode node) {
    final money = context.read<PlayerProfileController>().profile.money;
    final allCards = CardRepository.instance.allCards;

    // Shop singles: some common Pokémon at various levels with random stats
    final shopSingles = <Map<String, dynamic>>[];
    final rng = Random();
    final singlesPool = ['card_pidgey_1', 'card_rattata_1', 'card_caterpie_1', 'card_weedle_1',
                         'card_spearow_1', 'card_sentret_1', 'card_oddish_1', 'card_bellsprout_1'];
    for (final id in singlesPool.take(6)) {
      final card = CardRepository.instance.cardById(id);
      if (card == null) continue;
      final level = 3 + rng.nextInt(3); // level 3-5
      final bonus = CardValues(
        north: rng.nextInt(3), south: rng.nextInt(3),
        east: rng.nextInt(3), west: rng.nextInt(3),
      );
      shopSingles.add({
        'card': card.copyWith(values: card.values.plusBonus(bonus), baseLevel: level),
        'level': level,
        'price': 80 + level * 30 + bonus.total * 10,
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 550, maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Icons.store, color: Colors.greenAccent),
                const SizedBox(width: 8),
                const Text('POKÉ MART', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const Spacer(),
                Text('₽ $money', style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              // Booster pack
              _buildBoosterPack(money),
              const SizedBox(height: 4),
              const Text('Singles', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in shopSingles)
                      _ShopCardItem(
                        card: item['card'] as TriadCard,
                        level: item['level'] as int,
                        price: item['price'] as int,
                        canAfford: money >= (item['price'] as int),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Leave shop', style: TextStyle(color: Colors.white54)),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoosterPack(int money) {
    final canAfford = money >= 800;
    return Material(
      color: Colors.amber.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canAfford ? () {
          Navigator.of(context).pop(); // close shop dialog
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BoosterPackScreen(boosterName: 'field_trip')));
        } : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 44, height: 56,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Center(child: Text('?', style: TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Field Trip Booster', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              Text('5 random cards, chance for rare!', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ])),
            Text('₽ 800', style: TextStyle(color: canAfford ? const Color(0xFFC9A44C) : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  void _showShopkeeperDialog(StoryProgressController ctrl, StoryNode node) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Oak-style trainer sprite
              Image.asset('assets/trainers/npc/professor_oak.png', height: 120, width: 120),
              const SizedBox(height: 12),
              const Text('POKÉ MART CLERK',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text(
                '"Oh, are you from Pallet Town?"\n\n'
                'The shopkeeper pulls out a small package.\n\n'
                '"This parcel came for Professor Oak. Would you mind\n'
                'delivering it? It\'s been sitting here for weeks!"',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ctrl.completeNode(_location.id, node.id);
                    // Mark "Visit the PokéMart in Viridian City" quest objective
                    context.read<PlayerProfileController>()
                        .completeObjective('Visit the PokéMart in Viridian City');
                    // Also mark "Travel to Viridian City" if not already done
                    context.read<PlayerProfileController>()
                        .completeObjective('Travel to Viridian City');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Take the parcel',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOakParcelQuest(StoryProgressController ctrl, StoryNode node, PlayerProfileController profileCtrl) {
    final quest = profileCtrl.activeQuest;
    final questActive = quest?.id == 'oaks_parcel';

    if (!questActive) {
      // Start the quest
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📋 OAK\'S PARCEL',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 12),
                const Text(
                  'Professor Oak has a task for you.\n\n'
                  '"I ordered a special parcel, but it hasn\'t arrived yet.\n'
                  'Could you check the Poké Mart in Viridian City for me?"\n\n'
                  'Deliver his parcel and return to Oak.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      profileCtrl.startQuest(QuestData.oaksParcel);
                      ctrl.completeNode(_location.id, node.id);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Accept Quest', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (quest!.completed) {
      // Quest already completed
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A14),
          title: const Text('✅ Quest Complete!', style: TextStyle(color: Colors.white)),
          content: const Text('You already delivered Oak\'s parcel.\n\nHe thanks you for your help!',
              style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.greenAccent))),
          ],
        ),
      );
    } else {
      // Quest in progress — show status
      final objCount = quest.doneCount;
      final totalObj = quest.objectives.length;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A14),
          title: const Text('📋 Oak\'s Parcel', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Progress: $objCount/$totalObj', style: const TextStyle(color: Colors.amber)),
              const SizedBox(height: 8),
              for (final obj in quest.objectives)
                Row(children: [
                  Icon(obj.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: obj.completed ? Colors.greenAccent : Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Text(obj.description,
                      style: TextStyle(color: obj.completed ? Colors.white54 : Colors.white70, fontSize: 13)),
                ]),
              if (quest.allObjectivesDone) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      profileCtrl.completeObjective('Return the parcel to Professor Oak');
                    },
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                    child: const Text('Deliver Parcel to Oak'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: Colors.white54))),
          ],
        ),
      );
    }
  }

  void _showDialog(StoryProgressController ctrl, StoryNode node,
      {required String title, required String content, required String button}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A3A14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(
          content,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.completeNode(_location.id, node.id);
            },
            child: Text(button,
                style: const TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  /// Roll a random wild encounter from the node's encounter table.
  TriadCard _rollWildEncounter(StoryNode node) {
    final table = node.encounterTable ?? [];
    if (table.isEmpty) {
      // Fallback: return a common Pokémon
      return CardRepository.instance.cardById('pidgey') ??
          TriadCard.fallback();
    }

    final totalWeight = table.fold<int>(0, (sum, e) => sum + e.weight);
    var roll = Random().nextInt(totalWeight);
    for (final entry in table) {
      roll -= entry.weight;
      if (roll < 0) {
        final baseCard = CardRepository.instance.cardById(entry.cardId);
        if (baseCard == null) continue;

        // Apply level range
        final lvRange = _location.wildLevelRange;
        final level = lvRange.min + Random().nextInt(lvRange.max - lvRange.min + 1);

        // Rare encounters get a level bonus
        final adjustedLevel = entry.rarity == EncounterRarity.rare
            ? min(level + 1 + Random().nextInt(2), lvRange.max + 2)
            : entry.rarity == EncounterRarity.uncommon
                ? min(level + Random().nextInt(1), lvRange.max + 1)
                : level;

        // Boss nodes use max level + 1
        final finalLevel = node.type == StoryNodeType.wildBoss
            ? lvRange.max + 1
            : adjustedLevel;

        // Shiny chance: ~1/4096 base, slightly boosted for rare encounters
        final shinyRoll = Random().nextInt(4096);
        final isShiny = shinyRoll == 0 ||
            (entry.rarity == EncounterRarity.rare && shinyRoll < 4);

        return baseCard.copyWith(
          shiny: isShiny || baseCard.shiny,
        );
      }
    }

    return CardRepository.instance.cardById(table.first.cardId) ??
        TriadCard.fallback();
  }

  Deck get _playerDeck {
    final profile = context.read<PlayerProfileController>().profile;
    // Use the player's active/default deck
    final deck = profile.defaultDeck;
    if (deck != null) return deck;

    // Fallback: first valid deck
    return profile.decks.firstWhere(
      (d) => d.isValid,
      orElse: () => profile.decks.first,
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.location,
    required this.enabled,
    required this.onComplete,
  });

  final StoryNode node;
  final StoryLocation location;
  final bool enabled;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white : Colors.grey;
    final bgColor = enabled
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.3);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onComplete : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              // Node type icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _nodeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_nodeIcon, color: _nodeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nodeLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_nodeSubtitle != null)
                      Text(
                        _nodeSubtitle!,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (node.isCompleted)
                const Icon(Icons.check_circle,
                    color: Colors.greenAccent, size: 24)
              else if (enabled)
                Icon(Icons.play_arrow,
                    color: Colors.white.withValues(alpha: 0.6), size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Color get _nodeColor {
    switch (node.type) {
      case StoryNodeType.wild:
        return const Color(0xFF66BB6A);
      case StoryNodeType.trainer:
        return const Color(0xFF42A5F5);
      case StoryNodeType.story:
        return const Color(0xFFFFCA28);
      case StoryNodeType.wildBoss:
        return const Color(0xFFEF5350);
    }
  }

  IconData get _nodeIcon {
    switch (node.type) {
      case StoryNodeType.wild:
        return Icons.grass;
      case StoryNodeType.trainer:
        return Icons.person;
      case StoryNodeType.story:
        return Icons.card_giftcard;
      case StoryNodeType.wildBoss:
        return Icons.warning;
    }
  }

  String get _nodeLabel {
    switch (node.type) {
      case StoryNodeType.wild:
        return 'Wild Battle';
      case StoryNodeType.trainer:
        final npc = CardRepository.instance.npcs.firstWhere(
          (n) => n.id == node.npcId,
          orElse: () => CardRepository.instance.npcs.first,
        );
        return npc.name;
      case StoryNodeType.story:
        return 'Item Discovery';
      case StoryNodeType.wildBoss:
        return '⚠ Final Encounter';
    }
  }

  String? get _nodeSubtitle {
    switch (node.type) {
      case StoryNodeType.wild:
        return null; // Just "Wild Battle" — no level range
      case StoryNodeType.trainer:
        return 'Trainer Battle';
      case StoryNodeType.story:
        return 'Story Scene';
      case StoryNodeType.wildBoss:
        return 'Strong wild Pokémon';
    }
  }
}
class _ShopItem extends StatelessWidget {
  const _ShopItem({required this.cardId, required this.label, required this.price, required this.canAfford});
  final String cardId;
  final String label;
  final int price;
  final bool canAfford;

  @override
  Widget build(BuildContext context) {
    final card = CardRepository.instance.cardById(cardId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: canAfford ? () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchased! (coming soon)'), backgroundColor: Colors.green)); } : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              if (card != null) ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 48, height: 48, child: Image.asset(card.image, fit: BoxFit.cover))),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
              Text('P ', style: TextStyle(color: canAfford ? const Color(0xFFC9A44C) : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
      ),
    );
  }
}
class _ShopCardItem extends StatelessWidget {
  const _ShopCardItem({required this.card, required this.level, required this.price, required this.canAfford});
  final TriadCard card;
  final int level;
  final int price;
  final bool canAfford;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: canAfford ? () {
            Navigator.of(context).pop(); // close shop first
            Navigator.of(context).pop(); // close shop first
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Purchased ' + card.name + ' Lv.' + level.toString() + '!'), backgroundColor: Colors.green),
            );
          } : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(width: 56, height: 56, child: TriadCardView(card: card, size: 56))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(card.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
                    child: Text('Lv.' + level.toString(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
                ]),
              ])),
              Text(
                '\u20BD ' + price.toString(),
                style: TextStyle(color: canAfford ? const Color(0xFFC9A44C) : Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
