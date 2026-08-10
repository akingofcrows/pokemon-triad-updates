import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../game/battle_hud.dart';
import '../game/triad_game.dart';
import '../models/card_owner.dart';
import '../models/consumable_item.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../services/audio_service.dart';
import '../services/item_repository.dart';
import '../game/systems/capture_system.dart' show RuleSet;
import '../models/triad_card.dart';
import '../services/match_service.dart';
import '../widgets/battle_header_bar.dart';
import '../widgets/battle_log_panel.dart';
import '../widgets/home_style_panel.dart';
import '../widgets/item_card.dart';
import 'results_screen.dart';

/// Hosts the Flame [TriadGame] for one match, then navigates to
/// [ResultsScreen] once it completes.
class BattleScreen extends StatefulWidget {
  const BattleScreen({
    super.key,
    required this.playerDeck,
    required this.opponentDeck,
    required this.opponentName,
    this.opponentPortrait,
    this.opponentVictoryQuote,
    this.opponentDefeatQuote,
    this.playerGoesFirst,
    this.onMatchComplete,
    this.onContinue,
    this.opponentCards,
    this.rules = RuleSet.basic,
    this.background = 'assets/ui/battle_bg.png',
  });

  final Deck playerDeck;
  final Deck opponentDeck;
  final String opponentName;
  final String? opponentPortrait;
  final String? opponentVictoryQuote;
  final String? opponentDefeatQuote;
  final bool? playerGoesFirst;
  final void Function(bool playerWon, {List<String>? capturedCardIds})? onMatchComplete;
  final VoidCallback? onContinue;
  /// Pre-built opponent cards (for wild battles with random stats).
  /// When provided, these are used instead of looking up from [opponentDeck].
  final List<TriadCard>? opponentCards;
  final RuleSet rules;
  final String background;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final MatchState _matchState;
  late final BattleHud _hud;
  late final TriadGame _game;
  late final String _playerName;
  bool _navigated = false;
  bool _itemSheetOpen = false;
  TriadCard? _itemCapturedCard;

  @override
  void initState() {
    super.initState();
    _playerName = context.read<PlayerProfileController>().profile.trainerName ?? 'You';
    // Background music disabled for now
    _matchState = MatchService().createMatch(
      playerDeck: widget.playerDeck,
      opponentDeck: widget.opponentDeck,
      playerInstances: context.read<PlayerProfileController>().allCardInstances,
      playerGoesFirst: widget.playerGoesFirst,
    );
    _hud = BattleHud();
    _game = TriadGame(
      state: _matchState,
      onMatchComplete: _onMatchComplete,
      hud: _hud,
      playerName: _playerName,
      opponentName: widget.opponentName,
      isWildBattle: widget.opponentName.startsWith('Wild '),
      rules: widget.rules,
      onItemCaptured: _onItemCaptured,
      onItemConsumed: _onItemConsumed,
      trainerLevel: context.read<PlayerProfileController>().trainerLevel,
    );
  }

  @override
  void dispose() {
    // Only stop BGM if the battle was abandoned (back button), not if it ended normally.
    // When battle ends normally, _onMatchComplete handles the BGM transition.
    if (!_navigated) AudioService().stopBgm();
    _hud.dispose();
    super.dispose();
  }

  Future<void> _onMatchComplete(MatchState state) async {
    if (_navigated || !mounted) return;
    _navigated = true;
    final playerWon = state.scoreFor(CardOwner.player) > state.scoreFor(CardOwner.opponent);

    // Only pokéball captures now — no more automatic end-of-battle captures.
    final capturedShiny = <TriadCard>[];
    final capturedNormal = <TriadCard>[];

    // Notify caller with captured card IDs (pokéball only)
    final allCapturedIds = <String>[
      if (_itemCapturedCard != null) _itemCapturedCard!.id,
    ];
    widget.onMatchComplete?.call(playerWon, capturedCardIds: allCapturedIds);

    AudioService().stopBgm();
    await Future.delayed(const Duration(milliseconds: 200));
    AudioService().playBgm('sound/victory.ogg', volume: 0.5);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          finalState: state,
          opponentName: widget.opponentName,
          playerDeck: widget.playerDeck,
          opponentDeck: widget.opponentDeck,
          opponentPortrait: widget.opponentPortrait,
          opponentVictoryQuote: widget.opponentVictoryQuote,
          opponentDefeatQuote: widget.opponentDefeatQuote,
          onContinue: widget.onContinue,
          onMatchComplete: widget.onMatchComplete,
          opponentCards: widget.opponentCards,
          capturedShinyCards: capturedShiny,
          capturedCards: capturedNormal,
          itemCapturedCard: _itemCapturedCard,
        ),
      ),
    );
  }

  /// Called by TriadGame when a pokéball successfully captures a card mid-battle.
  void _onItemCaptured(TriadCard capturedCard) {
    setState(() {
      _itemCapturedCard = capturedCard;
    });
  }

  /// Called by TriadGame when a pokéball is actually thrown (consume it).
  void _onItemConsumed(String itemId) {
    context.read<PlayerProfileController>().useConsumable(itemId);
  }

  void _showItemSheet() {
    if (_itemSheetOpen) return;
    _itemSheetOpen = true;
    final profileCtrl = context.read<PlayerProfileController>();
    final repo = ItemRepository();
    final balls = repo.pokeballs;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF33343C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final ownedBalls = balls.where((b) => profileCtrl.itemCount(b.id) > 0).toList();
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.backpack, color: Color(0xFF42A5F5)),
                const SizedBox(width: 8),
                const Text('BATTLE ITEMS',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.bold, letterSpacing: 2)),
              ]),
              const SizedBox(height: 16),
              if (!widget.opponentName.startsWith('Wild '))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Pokéballs can only be used in wild battles!',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              if (ownedBalls.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('You have no battle items.\nOpen boosters or visit the Poké Mart!',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              if (ownedBalls.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final ball in ownedBalls)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ItemCard(
                            imageAsset: ball.imageAsset,
                            count: profileCtrl.itemCount(ball.id),
                            size: 80,
                            enabled: widget.opponentName.startsWith('Wild '),
                            onTap: () {
                      if (!_game.enterTargetingMode(ball)) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No recently flipped cards to target!'),
                              duration: Duration(seconds: 1)),
                        );
                      } else {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Tap a glowing card to throw ${ball.name}!'),
                              duration: const Duration(seconds: 2)),
                        );
                      }
                    },
                  ),
                ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).whenComplete(() => _itemSheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Battle background image
          Positioned.fill(
            child: Image.asset(
              widget.background,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B5E20), Color(0xFF0D3311)],
                  ),
                ),
              ),
            ),
          ),
          // Status bar backdrop — matches the home screen's dark chrome.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xFF2D2E35),
              height: MediaQuery.of(context).padding.top,
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    ListenableBuilder(
                      listenable: _hud,
                      builder: (context, _) => BattleHeaderBar(
                        playerName: _playerName,
                        opponentName: widget.opponentName,
                        playerScore: _hud.playerScore,
                        opponentScore: _hud.opponentScore,
                        isPlayerTurn: _hud.isPlayerTurn,
                      ),
                    ),
                    Expanded(child: GameWidget(game: _game)),
                    ListenableBuilder(
                      listenable: _hud,
                      builder: (context, _) => Container(
                        color: const Color(0xFF2D2E35),
                        child: BattleLogPanel(entries: _hud.log),
                      ),
                    ),
                  ],
                ),
                // Bag button — floating bottom-right above the log (player turn + wild battle only)
                Positioned(
                  right: 16,
                  bottom: 100,
                  child: ListenableBuilder(
                    listenable: _hud,
                    builder: (context, _) {
                      if (!widget.opponentName.startsWith('Wild ') ||
                          !_hud.isPlayerTurn) {
                        return _itemCapturedCard != null
                            ? _CapturedOverlay(card: _itemCapturedCard!)
                            : const SizedBox.shrink();
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_itemCapturedCard != null)
                            _CapturedOverlay(card: _itemCapturedCard!),
                          _BagButton(onTap: _showItemSheet),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bag button ──

class _BagButton extends StatelessWidget {
  const _BagButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: HomeStylePanel(
        width: 48,
        height: 48,
        borderRadius: 14,
        child: Center(child: Icon(Icons.backpack, color: Colors.white.withValues(alpha: 0.7), size: 24)),
      ),
    );
  }
}


// ── Captured overlay popup ──

class _CapturedOverlay extends StatefulWidget {
  const _CapturedOverlay({required this.card});
  final TriadCard card;

  @override
  State<_CapturedOverlay> createState() => _CapturedOverlayState();
}

class _CapturedOverlayState extends State<_CapturedOverlay> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final _anim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.scale(
        scale: _anim.value,
        child: child,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4CAF50), width: 2.5),
          boxShadow: [
            BoxShadow(color: const Color(0xFF4CAF50).withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 2),
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.catching_pokemon, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GOTCHA!', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(widget.card.name, style: const TextStyle(color: Color(0xFFA5D6A7), fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}
