import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../game/systems/score_system.dart';
import '../models/card_growth.dart';
import '../models/card_owner.dart';
import '../models/deck.dart';
import '../models/match_growth_result.dart';
import '../models/match_state.dart';
import '../models/pending_evolution.dart';
import '../models/pokemon_leveling.dart';
import '../models/triad_card.dart';
import '../models/xp_system.dart';
import '../services/card_repository.dart';
import '../widgets/evolution_animation.dart';
import '../widgets/trainer_sprite_stack.dart';
import '../widgets/triad_card_view.dart';
import 'battle_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.finalState,
    required this.opponentName,
    required this.playerDeck,
    required this.opponentDeck,
    this.opponentPortrait,
    this.opponentVictoryQuote,
    this.opponentDefeatQuote,
    this.onContinue,
    this.onMatchComplete,
    this.opponentCards,
    this.capturedShinyCards,
    this.capturedCards,
  });

  final MatchState finalState;
  final String opponentName;
  final Deck playerDeck;
  final Deck opponentDeck;
  final String? opponentPortrait;
  final String? opponentVictoryQuote;
  final String? opponentDefeatQuote;
  final VoidCallback? onContinue;
  final void Function(bool playerWon)? onMatchComplete;
  final List<TriadCard>? opponentCards;
  final List<TriadCard>? capturedShinyCards;
  final List<TriadCard>? capturedCards;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with TickerProviderStateMixin {
  late final MatchOutcome _outcome;
  bool _recorded = false;
  bool _showOverlay = true;
  MatchGrowthResult? _growthResult;
  final Set<String> _resolvedEvolutions = {};
  int? _expandedCardIndex;
  late final AnimationController _overlayCtrl;
  late final Animation<double> _overlayFade;
  int _visibleCards = 0;

  @override
  void initState() {
    super.initState();
    _outcome = ScoreSystem.outcomeFor(widget.finalState, CardOwner.player);
    _overlayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _overlayFade = CurvedAnimation(parent: _overlayCtrl, curve: Curves.easeOut);
    // Only show overlay on win/loss against NPC (skip for draw)
    if (_outcome != MatchOutcome.draw && widget.opponentPortrait != null) {
      _overlayCtrl.forward();
    } else {
      _showOverlay = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordResult());
    _startReveal();
  }

  void _startReveal() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Timer.periodic(const Duration(milliseconds: 600), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _visibleCards++;
          if (_visibleCards >= widget.playerDeck!.cardIds.length) {
            t.cancel();
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _overlayCtrl.dispose();
    super.dispose();
  }

  void _dismissOverlay() {
    _overlayCtrl.reverse().then((_) {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  Future<void> _recordResult() async {
    if (_recorded || !mounted) return;
    _recorded = true;
    final cardXpBreakdown = <int, Map<String, dynamic>>{};
    for (final xp in widget.finalState.cardXp.values) {
      cardXpBreakdown[xp.instanceId] = xp.toJson();
    }
    debugPrint(
      '[XP] results: cardXp has ${widget.finalState.cardXp.length} entries, captureXp=${widget.finalState.captureXpByInstanceId}',
    );
    if (widget.finalState.cardXp.isNotEmpty) {
      debugPrint(
        '[XP] results: first entry totalXp=${widget.finalState.cardXp.values.first.totalXp}',
      );
    }
    final capturedCards = <Map<String, dynamic>>[
      ...?widget.capturedShinyCards
          ?.map((c) => {'cardId': c.id, 'level': c.baseLevel ?? 1}),
      ...?widget.capturedCards
          ?.map((c) => {'cardId': c.id, 'level': c.baseLevel ?? 1}),
    ];
    if (capturedCards.isNotEmpty) {
      print('[CAPTURE] results sending capturedCards: $capturedCards');
    }
    final result = await context
        .read<PlayerProfileController>()
        .recordMatchResult(
          _outcome,
          captureXp: widget.finalState.captureXpByInstanceId,
          captureCounts: widget.finalState.captureCountByCardId,
          deckCardIds: widget.playerDeck?.cardIds,
          deckInstanceIds: widget.playerDeck?.instanceIds,
          cardXpBreakdown: cardXpBreakdown,
          capturedCards: capturedCards,
        );
    if (!mounted) return;
    setState(() => _growthResult = result);

    // Client-side evolution check: if the server didn't report pending evolutions,
    // check locally based on card levels vs evolution requirements.
    _checkLocalEvolutions();
  }

  /// Checks deck cards against evolution chains and adds any eligible
  /// evolutions to the pending list (client-side fallback).
  void _checkLocalEvolutions() {
    final repo = CardRepository.instance;
    final ctrl = context.read<PlayerProfileController>();
    final localEvolutions = <PendingEvolution>[];
    final cardIds = widget.playerDeck?.cardIds ?? <String>[];
    final instanceIds = widget.playerDeck?.instanceIds;

    for (var i = 0; i < cardIds.length; i++) {
      final cardId = cardIds[i];
      final instId = instanceIds != null && i < instanceIds.length
          ? instanceIds[i]
          : null;
      // Find the specific instance that fought in this battle
      final growth = instId != null
          ? ctrl.allCardInstances
                .where((g) => g.instanceId == instId)
                .firstOrNull
          : ctrl.cardGrowth[cardId];
      if (growth == null) continue;
      final chains = repo.evolutionsFrom(cardId);
      for (final chain in chains) {
        if (growth.level >= chain.level) {
          localEvolutions.add(
            PendingEvolution(
              cardId: cardId,
              toId: chain.to,
              level: chain.level,
              instanceId: instId,
            ),
          );
        }
      }
    }

    if (localEvolutions.isNotEmpty) {
      final existingIds =
          _growthResult?.pendingEvolutions.map((e) => e.cardId).toSet() ?? {};
      for (final evo in localEvolutions) {
        if (!existingIds.contains(evo.cardId)) {
          _growthResult?.pendingEvolutions.add(evo);
        }
      }
      setState(() {}); // refresh to show evolution prompts
    }
  }

  Future<void> _evolve(String cardId, String toId, {int? instanceId}) async {
    debugPrint(
      '[EVOLVE] results: cardId=$cardId toId=$toId instanceId=$instanceId',
    );
    final fromCard = CardRepository.instance.cardById(cardId);
    final toCard = CardRepository.instance.cardById(toId);
    if (fromCard == null || toCard == null) {
      // Fallback: evolve without animation
      await context.read<PlayerProfileController>().evolveCard(
        cardId,
        toId,
        instanceId: instanceId,
      );
      if (!mounted) return;
      setState(() => _resolvedEvolutions.add(cardId));
      return;
    }

    // Kick the real evolve off now, in parallel with the animation — it
    // needs the whole strobe/flash/slam runway anyway before the evolved
    // card's real (post-loss) bonus is ever shown.
    final growth = context.read<PlayerProfileController>().cardGrowth[cardId];
    final isShiny = growth?.shiny == true;
    final evolveFuture = context.read<PlayerProfileController>().evolveCard(
      cardId,
      toId,
      instanceId: instanceId,
    );
    final didEvolve = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => EvolutionAnimation(
          fromCard: fromCard.copyWith(shiny: isShiny),
          toCard: toCard.copyWith(shiny: isShiny),
          fromBonuses: growth?.bonusValues,
          toBonusesFuture: evolveFuture,
          onComplete: () => Navigator.pop(ctx, true),
        ),
      ),
    );

    if (didEvolve == true && mounted) {
      await evolveFuture;
      if (!mounted) return;
      setState(() {
        _resolvedEvolutions.add(cardId);
        // Refresh growth data so XP/lvl/stats update for evolved card
        _growthResult = null;
      });
      // Re-record to get fresh data from server
      _recorded = false;
      await _recordResult();
    }
  }

  // ── XP per card from breakdown ──────────────────────────────────────

  int _xpForCard(String cardId) {
    final growth = _growthResult;
    if (growth == null) return 0;
    return growth.growth
        .where((g) => g.cardId == cardId)
        .fold(0, (s, g) => s + g.xpGained);
  }

  bool _cardLeveledUp(String cardId) {
    return _growthResult?.growth.any(
          (g) => g.cardId == cardId && g.leveledUp,
        ) ??
        false;
  }

  int _newLevelFor(String cardId) {
    final g = _growthResult?.growth
        .where((g) => g.cardId == cardId)
        .firstOrNull;
    return g?.newLevel ?? 1;
  }

  String? _statBumpedFor(String cardId) {
    return _growthResult?.growth
        .where((g) => g.cardId == cardId)
        .firstOrNull
        ?.statBumped;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.finalState;
    final playerScore = state.scoreFor(CardOwner.player);
    final opponentScore = state.scoreFor(CardOwner.opponent);
    final isWin = _outcome == MatchOutcome.win;
    final growth = _growthResult;
    final pendingEvolutions =
        (growth?.pendingEvolutions ?? const <PendingEvolution>[])
            .where((e) => !_resolvedEvolutions.contains(e.cardId))
            .toList();

    final isWildBattle = widget.opponentName.startsWith('Wild ');

    // Money reward on victory — wild battles give no money
    final moneyReward = (isWin && !isWildBattle)
        ? 50 + (playerScore - opponentScore) * 20
        : 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Results content ──────────────────────────────────
            _buildResultsContent(
              playerScore,
              opponentScore,
              isWin,
              growth,
              pendingEvolutions,
              moneyReward,
            ),

            // ── NPC trainer dialogue overlay (win or loss) ─────
            if (_showOverlay) _buildTrainerOverlay(isWin),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsContent(
    int playerScore,
    int opponentScore,
    bool isWin,
    MatchGrowthResult? growth,
    List<PendingEvolution> pendingEvolutions,
    int moneyReward,
  ) {
    final title = isWin
        ? 'VICTORY!'
        : _outcome == MatchOutcome.draw
        ? 'DRAW'
        : 'DEFEAT';
    final titleColor = isWin
        ? const Color(0xFFC9A44C)
        : _outcome == MatchOutcome.draw
        ? Colors.grey
        : const Color(0xFFE57373);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              // Victory / Defeat / Draw
              Text(
                title,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$playerScore — $opponentScore  ${widget.opponentName}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              if (isWin && moneyReward > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '₽',
                      style: TextStyle(
                        color: Color(0xFFC9A44C),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+$moneyReward',
                      style: const TextStyle(
                        color: Color(0xFFC9A44C),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              // Trainer XP
              if (growth != null && growth.trainerXpEarned > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.cyan.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text(
                      '+${growth.trainerXpEarned} Trainer XP',
                      style: TextStyle(
                        color: Colors.cyan.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // ── Deck cards with XP bars ──────────────────────────
              if (widget.playerDeck != null) ...[
                Text(
                  'Card XP',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(widget.playerDeck!.cardIds.length, (i) {
                  if (i >= _visibleCards) return const SizedBox.shrink();
                  final cardId = widget.playerDeck!.cardIds[i];
                  final card = CardRepository.instance.cardById(cardId);
                  if (card == null) return const SizedBox.shrink();
                  final instId = widget.playerDeck!.instanceIds != null &&
                          i < widget.playerDeck!.instanceIds!.length
                      ? widget.playerDeck!.instanceIds![i]
                      : null;
                  final xp = _xpForCard(cardId);
                  final leveledUp = _cardLeveledUp(cardId);
                  final newLevel = _newLevelFor(cardId);
                  final breakdown = _cardBreakdown(cardId);
                  final growth = _growthForSlot(cardId, instId);
                  final statBump = _statBumpedFor(cardId);
                  final displayCard = growth?.shiny == true
                      ? card.copyWith(shiny: true)
                      : card;
                  return AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 400),
                    child: _buildCardXpRow(
                      displayCard,
                      growth,
                      xp,
                      leveledUp,
                      newLevel,
                      breakdown,
                      statBump,
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // ── Expanded card breakdown ──────────────────────────
              if (_expandedCardIndex != null) ...[
                _buildXpBreakdown(_expandedCardIndex!),
                const SizedBox(height: 12),
              ],

              // ── Evolutions ────────────────────────────────────────
              if (pendingEvolutions.isNotEmpty) ...[
                Text(
                  'Ready to Evolve!',
                  style: TextStyle(
                    color: Colors.green.shade300,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                for (final e in pendingEvolutions) _buildEvolutionPrompt(e),
                const SizedBox(height: 12),
              ],

              // ── Captured Shiny ────────────────────────────────────
              if (widget.capturedShinyCards != null &&
                  widget.capturedShinyCards!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A44C).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFC9A44C).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            color: Color(0xFFC9A44C),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Shiny Pokémon obtained!',
                            style: TextStyle(
                              color: Colors.amber.shade300,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...widget.capturedShinyCards!.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: TriadCardView(card: c, size: 48),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                c.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFC9A44C,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '⭐ SHINY',
                                  style: TextStyle(
                                    color: Color(0xFFC9A44C),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Buttons ───────────────────────────────────────────
              if (widget.onContinue != null) ...[
                SizedBox(
                  width: 200,
                  child: FilledButton.icon(
                    onPressed: widget.onContinue,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Continue on'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: 200,
                child: OutlinedButton(
                  onPressed: () => _rematch(context),
                  child: const Text('Rematch'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: OutlinedButton(
                  onPressed: () => Navigator.popUntil(
                    context,
                    ModalRoute.withName(AppRoutes.home),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Get per-source XP breakdown for a card from MatchState.cardXp.
  Map<String, int> _cardBreakdown(String cardId) {
    final result = <String, int>{};
    for (final xp in widget.finalState.cardXp.values) {
      if (xp.cardId == cardId) {
        result.addAll(xp.breakdown);
      }
    }
    return result;
  }

  /// Find the CardGrowth for a specific card slot using its instance ID.
  CardGrowth? _growthForSlot(String cardId, int? instanceId) {
    try {
      final instances = context.read<PlayerProfileController>().allCardInstances;
      if (instanceId != null && instanceId > 0) {
        return instances.where((i) => i.instanceId == instanceId).firstOrNull;
      }
      return instances.where((i) => i.cardId == cardId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Find the CardGrowth for a cardId from the player's instances.
  CardGrowth? _growthForCardId(String cardId) {
    try {
      final controller = context.read<PlayerProfileController>();
      return controller.allCardInstances
              .where((i) => i.cardId == cardId && i.shiny == true)
              .firstOrNull ??
          controller.allCardInstances
              .where((i) => i.cardId == cardId)
              .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Compact card result with XP badge and level-up indicator.
  Widget _buildCardXpRow(
    TriadCard card,
    CardGrowth? growth,
    int xpGained,
    bool leveledUp,
    int newLevel,
    Map<String, int> breakdown,
    String? statBumped,
  ) {
    final hasXp = xpGained > 0;
    // Use pre-battle XP (growth.xp already includes this battle's gain after refresh)
    final postXp = growth?.xp ?? 0;
    final oldXp = hasXp ? (postXp - xpGained).clamp(0, postXp) : postXp;
    final newXp = postXp;
    final oldLevel = levelFromXp(oldXp).level;
    final actualNewLevel = hasXp ? levelFromXp(newXp).level : oldLevel;
    final didLevelUp = actualNewLevel > oldLevel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            // Card thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 48,
                child: TriadCardView(card: card, size: 48, growth: growth),
              ),
            ),
            const SizedBox(width: 12),
            // Name + level + XP bar
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasXp)
                        Text(
                          '+$xpGained XP',
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Lv.$oldLevel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                      if (didLevelUp) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LEVEL UP!',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (statBumped != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF42A5F5,
                              ).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$statBumped ▲',
                              style: const TextStyle(
                                color: Color(0xFF42A5F5),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward,
                          size: 12,
                          color: Color(0xFFFFB300),
                        ),
                        Text(
                          'Lv.$actualNewLevel',
                          style: const TextStyle(
                            color: Color(0xFFFFB300),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '$oldXp XP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (hasXp) ...[
                    const SizedBox(height: 4),
                    _AnimatedXpBar(
                      currentXp: oldXp,
                      gainedXp: xpGained,
                      currentLevel: oldLevel,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Per-source XP breakdown for a single card.
  Widget _buildXpBreakdown(int index) {
    final cardId = widget.playerDeck!.cardIds[index];
    final card = CardRepository.instance.cardById(cardId);
    final breakdown = _cardBreakdown(cardId);
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFC9A44C).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${card?.name ?? cardId}  —  ${breakdown.values.fold(0, (a, b) => a + b)} XP',
            style: const TextStyle(
              color: Color(0xFFC9A44C),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in breakdown.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '+${entry.value}',
                    style: const TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// NPC trainer overlay shown on win or loss with context-appropriate dialogue.
  Widget _buildTrainerOverlay(bool isWin) {
    final dialogue = isWin
        ? (widget.opponentVictoryQuote ?? '"I can\'t believe I lost..."')
        : (widget.opponentDefeatQuote ?? '"Better luck next time, Trainer!"');
    return GestureDetector(
      onTap: _dismissOverlay,
      child: AnimatedBuilder(
        animation: _overlayFade,
        builder: (context, child) {
          return Opacity(
            opacity: _overlayFade.value,
            child: Container(
              color: Colors.black.withValues(alpha: 0.7 * _overlayFade.value),
              child: Stack(
                children: [
                  IgnorePointer(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Opacity(
                        opacity: 0.4,
                        child: _buildResultsContent(0, 0, true, null, [], 0),
                      ),
                    ),
                  ),
                  if (widget.opponentPortrait != null)
                    Positioned(
                      bottom: 100,
                      left: 0,
                      right: 0,
                      child: Image.asset(
                        widget.opponentPortrait!,
                        height: 180,
                        fit: BoxFit.contain,
                      ),
                    ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F0E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF8B7355),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dialogue.replaceAll('\\n', '\n'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF3E2723),
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '— ${widget.opponentName}',
                            style: const TextStyle(
                              color: Color(0xFF5D4037),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'tap to continue',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.3),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildEvolutionPrompt(PendingEvolution evo) {
    final fromCard = CardRepository.instance.cardById(evo.cardId);
    final toCard = CardRepository.instance.cardById(evo.toId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '${fromCard?.name ?? evo.cardId} can evolve into ${toCard?.name ?? evo.toId}!',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () =>
                _evolve(evo.cardId, evo.toId, instanceId: evo.instanceId),
            child: const Text('Evolve'),
          ),
        ],
      ),
    );
  }

  void _rematch(BuildContext context) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          playerDeck: widget.playerDeck,
          opponentDeck: widget.opponentDeck,
          opponentName: widget.opponentName,
          opponentPortrait: widget.opponentPortrait,
          opponentVictoryQuote: widget.opponentVictoryQuote,
          opponentDefeatQuote: widget.opponentDefeatQuote,
          onMatchComplete: widget.onMatchComplete,
          onContinue: widget.onContinue,
          opponentCards: widget.opponentCards,
        ),
      ),
    );
  }
}

class _AnimatedXpBar extends StatefulWidget {
  const _AnimatedXpBar({
    required this.currentXp,
    required this.gainedXp,
    required this.currentLevel,
  });

  final int currentXp;
  final int gainedXp;
  final int currentLevel;

  @override
  State<_AnimatedXpBar> createState() => _AnimatedXpBarState();
}

class _AnimatedXpBarState extends State<_AnimatedXpBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _anim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the XP curve to get level thresholds for the card's actual level
    final oldXp = widget.currentXp;
    final newXp = oldXp + widget.gainedXp;
    final actualLevel = levelFromXp(oldXp).level;
    final newActualLevel = widget.gainedXp > 0
        ? levelFromXp(newXp).level
        : actualLevel;
    final didLevelUp = newActualLevel > actualLevel;

    // Find the XP range for the bar: from the start of the current level
    // to the XP needed for the next level
    final xpStartOfLevel = xpToReachLevel(actualLevel);
    final xpNextLevel = xpToReachLevel(actualLevel + 1);
    final xpInLevel = oldXp - xpStartOfLevel;
    final xpNeeded = xpNextLevel - xpStartOfLevel;

    final startFrac = xpNeeded > 0
        ? (xpInLevel / xpNeeded).clamp(0.0, 1.0)
        : 0.0;
    final endFrac = xpNeeded > 0
        ? ((xpInLevel + widget.gainedXp) / xpNeeded).clamp(0.0, 1.0)
        : 0.0;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final t = _anim.value;
        final currentFrac = startFrac + (endFrac - startFrac) * t;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.1)),
                    if (startFrac > 0)
                      FractionallySizedBox(
                        widthFactor: startFrac,
                        child: Container(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                        ),
                      ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: currentFrac.clamp(0.0, 1.0),
                          child: Container(
                            color: didLevelUp && t > 0.8
                                ? const Color(0xFFFFB300)
                                : const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '$oldXp',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                  ),
                ),
                if (didLevelUp) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'Lv.$actualLevel → Lv.$newActualLevel',
                      style: const TextStyle(
                        color: Color(0xFFFFB300),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '$newXp / $xpNextLevel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
