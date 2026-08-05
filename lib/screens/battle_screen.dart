import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../game/battle_hud.dart';
import '../game/triad_game.dart';
import '../models/card_owner.dart';
import '../models/deck.dart';
import '../models/match_state.dart';
import '../models/triad_card.dart';
import '../services/match_service.dart';
import '../widgets/battle_header_bar.dart';
import '../widgets/battle_log_panel.dart';
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
  });

  final Deck playerDeck;
  final Deck opponentDeck;
  final String opponentName;
  final String? opponentPortrait;
  final String? opponentVictoryQuote;
  final String? opponentDefeatQuote;
  final bool? playerGoesFirst;
  final void Function(bool playerWon)? onMatchComplete;
  final VoidCallback? onContinue;
  /// Pre-built opponent cards (for wild battles with random stats).
  /// When provided, these are used instead of looking up from [opponentDeck].
  final List<TriadCard>? opponentCards;

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final MatchState _matchState;
  late final BattleHud _hud;
  late final TriadGame _game;
  late final String _playerName;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _playerName = context.read<PlayerProfileController>().profile.trainerName ?? 'You';
    super.initState();
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
    );
  }

  @override
  void dispose() {
    _hud.dispose();
    super.dispose();
  }

  void _onMatchComplete(MatchState state) {
    if (_navigated || !mounted) return;
    _navigated = true;
    final playerWon = state.scoreFor(CardOwner.player) > state.scoreFor(CardOwner.opponent);
    widget.onMatchComplete?.call(playerWon);

    // Check for captured shiny opponent cards — use opponentCards for wild battles,
    // or check board state for shiny flags
    final capturedShiny = <TriadCard>[];
    final capturedNormal = <TriadCard>[];
    final rng = Random();
    final prebuiltOpponent = widget.opponentDeck.opponentCards;

    if (prebuiltOpponent != null) {
      // For wild battles: capture any flipped opponent cards
      for (final cell in state.cells) {
        final c = cell.card;
        if (c != null && c.owner == CardOwner.player) {
          // 10% base catch chance for normal cards
          if (rng.nextInt(100) < 10) {
            capturedNormal.add(c);
            print('[CAPTURE] Player captured normal! cardId=${c.id} level=${c.baseLevel}');
          }
        }
      }
      // Also check for shiny capture (existing logic)
      final hasShiny = prebuiltOpponent.any((c) => c.shiny);
      if (hasShiny) {
        // Check if player captured any opponent card (same species)
        final speciesId = prebuiltOpponent.first.id;
        final capturedAny = state.cells.any((cell) =>
          cell.card != null &&
          cell.card!.owner == CardOwner.player &&
          cell.card!.id == speciesId);
        if (capturedAny && rng.nextBool()) {
          final shinyCard = prebuiltOpponent.firstWhere((c) => c.shiny);
          final level = shinyCard.baseLevel ?? 1;
          print('[CAPTURE] Player captured shiny! cardId=${shinyCard.id} level=$level');
          capturedShiny.add(shinyCard);
        }
      }
    } else {
      // For regular battles: check board for flipped shiny opponent cards
      for (final cell in state.cells) {
        final c = cell.card;
        if (c != null && c.owner == CardOwner.player && c.shiny &&
            widget.opponentDeck.cardIds.contains(c.id)) {
          if (rng.nextBool()) {
            capturedShiny.add(c);
          }
        }
      }
    }

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
        ),
      ),
    );
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
              'assets/ui/battle_bg.png',
              fit: BoxFit.cover,
            ),
          ),
          // Black bar at very top (status bar area)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black,
              height: MediaQuery.of(context).padding.top,
            ),
          ),
          SafeArea(
            child: Column(
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
                    color: Colors.black,
                    child: BattleLogPanel(entries: _hud.log),
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
