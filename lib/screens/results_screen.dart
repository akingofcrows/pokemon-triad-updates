import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../game/systems/score_system.dart';
import '../models/card_growth.dart';
import '../models/card_owner.dart';
import '../models/condition.dart';
import '../models/deck.dart';
import '../models/growth_update.dart';
import '../models/match_growth_result.dart';
import '../models/match_state.dart';
import '../models/pending_evolution.dart';
import '../models/pokemon_leveling.dart';
import '../models/triad_card.dart';
import '../models/xp_system.dart';
import '../services/card_repository.dart';
import '../services/audio_service.dart';
import '../widgets/condition_badge.dart';
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
    this.itemCapturedCard,
  });

  final MatchState finalState;
  final String opponentName;
  final Deck playerDeck;
  final Deck opponentDeck;
  final String? opponentPortrait;
  final String? opponentVictoryQuote;
  final String? opponentDefeatQuote;
  final VoidCallback? onContinue;
  final void Function(bool playerWon, {List<String>? capturedCardIds})? onMatchComplete;
  final List<TriadCard>? opponentCards;
  final List<TriadCard>? capturedShinyCards;
  final List<TriadCard>? capturedCards;
  /// A card captured mid-battle via pokéball (shown separately).
  final TriadCard? itemCapturedCard;

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
  late final AnimationController _rewardCtrl;
  late final Animation<double> _rewardAnim;
  late final AnimationController _cardRevealCtrl;
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
    _rewardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rewardAnim = CurvedAnimation(parent: _rewardCtrl, curve: Curves.easeOutCubic);
    _cardRevealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (_outcome != MatchOutcome.draw && widget.opponentPortrait != null) {
      _overlayCtrl.forward();
    } else {
      _showOverlay = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recordResult());
  }

  @override
  void dispose() {
    _overlayCtrl.dispose();
    _rewardCtrl.dispose();
    _cardRevealCtrl.dispose();
    super.dispose();
  }

  void _dismissOverlay() {
    _overlayCtrl.reverse().then((_) {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  Map<String, dynamic> _cardToCaptureMap(TriadCard c) {
    final template = CardRepository.instance.cardById(c.id);
    final v = c.values;
    final map = {'cardId': c.id, 'level': c.baseLevel ?? 1,
      'bonusNorth': v.north - (template?.values.north ?? 0),
      'bonusSouth': v.south - (template?.values.south ?? 0),
      'bonusEast': v.east - (template?.values.east ?? 0),
      'bonusWest': v.west - (template?.values.west ?? 0),
      'shiny': c.shiny,
      'condition': c.condition};
    return map;
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
      ...?widget.capturedShinyCards?.map((c) => _cardToCaptureMap(c)),
      ...?widget.capturedCards?.map((c) => _cardToCaptureMap(c)),
      if (widget.itemCapturedCard != null)
        _cardToCaptureMap(widget.itemCapturedCard!),
    ];
    if (capturedCards.isNotEmpty) {
      print('[CAPTURE] results sending capturedCards: $capturedCards');
    }
    // Calculate opponent total power for trainer XP scaling
    final opponentCards = widget.opponentDeck.opponentCards ?? widget.opponentCards ?? [];
    final opponentTotalPower = opponentCards.fold<int>(0, (sum, c) => sum + c.values.total);

    final result = await context
        .read<PlayerProfileController>()
        .recordMatchResult(
          _outcome,
          captureXp: widget.finalState.captureXpByInstanceId,
          captureCounts: widget.finalState.captureCountByCardId,
          deckCardIds: widget.playerDeck?.cardIds,
          deckInstanceIds: widget.playerDeck?.instanceIds,
          cardXpBreakdown: cardXpBreakdown,
          conditionLoss: widget.finalState.conditionLossByInstanceId,
          capturedCards: capturedCards,
          opponentTotalPower: opponentTotalPower,
        );
    if (!mounted) return;
    setState(() => _growthResult = result);
    // Animate rewards and card reveals
    _rewardCtrl.forward();
    _cardRevealCtrl.forward();

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
          : (ctrl.allCardInstances
                .where((g) => g.cardId == cardId)
                .toList()
              ..sort((a, b) {
                if (a.shiny != b.shiny) return a.shiny ? -1 : 1;
                return b.level.compareTo(a.level);
              }))
              .firstOrNull;
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
    final ctrl = context.read<PlayerProfileController>();
    final growth = instanceId != null
        ? ctrl.allCardInstances.where((g) => g.instanceId == instanceId).firstOrNull
        : null;
    final isShiny = growth?.shiny == true;
    final evolveFuture = ctrl.evolveCard(
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
        _growthResult = null;
      });
      // Re-fetch card data from server (do NOT re-POST match result —
      // that would double-count XP for every card in the match).
      await _refreshGrowthOnly();
    }
  }

  Future<void> _refreshGrowthOnly() async {
    try {
      await context.read<PlayerProfileController>().refreshCardGrowth();
      // Build a minimal growth result from the freshly-fetched instances
      final ctrl = context.read<PlayerProfileController>();
      final growthUpdates = <GrowthUpdate>[];
      for (final xp in widget.finalState.cardXp.values) {
        final inst = ctrl.allCardInstances
            .where((i) => i.instanceId == xp.instanceId)
            .firstOrNull;
        if (inst != null) {
          growthUpdates.add(GrowthUpdate(
            cardId: inst.cardId,
            leveledUp: false, // already handled in the initial POST
            newLevel: inst.level,
            xpGained: 0, // don't double-count
            instanceId: inst.instanceId,
          ));
        }
      }
      if (mounted) {
        setState(() {
          _growthResult = MatchGrowthResult(
            growth: growthUpdates,
            pendingEvolutions: _growthResult?.pendingEvolutions ?? [],
          );
        });
      }
    } catch (_) {
      // Silently ignore — the original _growthResult data is still valid enough
    }
  }

  // ── XP per card from breakdown ──────────────────────────────────────

  int _xpForCard(String cardId, {int? instanceId}) {
    // Try server data first, fall back to local MatchState.cardXp
    final growth = _growthResult;
    if (growth != null) {
      if (instanceId != null && instanceId > 0) {
        final match = growth.growth
            .where((g) => g.instanceId == instanceId)
            .firstOrNull;
        if (match != null) return match.xpGained;
      }
      return growth.growth
          .where((g) => g.cardId == cardId)
          .fold(0, (s, g) => s + g.xpGained);
    }
    // Use local cardXp from the match — available immediately
    final instId = instanceId ?? _instanceIdForCard(cardId);
    if (instId != null) {
      return widget.finalState.cardXp[instId]?.totalXp ?? 0;
    }
    return 0;
  }

  int? _instanceIdForCard(String cardId) {
    final instIds = widget.playerDeck?.instanceIds;
    final cardIds = widget.playerDeck?.cardIds ?? <String>[];
    for (var i = 0; i < cardIds.length; i++) {
      if (cardIds[i] == cardId && instIds != null && i < instIds.length) {
        return instIds[i];
      }
    }
    return null;
  }

  bool _cardLeveledUp(String cardId, {int? instanceId}) {
    final growth = _growthResult?.growth;
    if (growth == null) return false;
    if (instanceId != null && instanceId > 0) {
      return growth.any((g) => g.instanceId == instanceId && g.leveledUp);
    }
    return growth.any((g) => g.cardId == cardId && g.leveledUp);
  }

  int _newLevelFor(String cardId) {
    final g = _growthResult?.growth
        .where((g) => g.cardId == cardId)
        .firstOrNull;
    return g?.newLevel ?? 1;
  }

  String? _statBumpedFor(String cardId, {int? instanceId}) {
    final growth = _growthResult?.growth;
    if (growth == null) return null;
    if (instanceId != null && instanceId > 0) {
      return growth
          .where((g) => g.instanceId == instanceId)
          .firstOrNull
          ?.statBumped;
    }
    return growth
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
      backgroundColor: const Color(0xFF2D2E35),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_rewardCtrl, _cardRevealCtrl]),
          builder: (context, _) {
            final moneyT = _rewardAnim.value;
            final cardT = Curves.easeOutCubic.transform(
              (_cardRevealCtrl.value).clamp(0.0, 1.0),
            );
            final displayMoney = (moneyReward * moneyT).round();
            return Stack(
              children: [
                _buildResultsContent(
                  playerScore,
                  opponentScore,
                  isWin,
                  growth,
                  pendingEvolutions,
                  moneyReward,
                  animatedMoney: displayMoney,
                  moneyT: moneyT,
                  cardT: cardT,
                ),
                if (_showOverlay) _buildTrainerOverlay(isWin),
              ],
            );
          },
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
    int moneyReward, {
    int animatedMoney = 0,
    double moneyT = 0,
    double cardT = 0,
  }) {
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
    final hasCaptures = widget.itemCapturedCard != null ||
        (widget.capturedCards != null && widget.capturedCards!.isNotEmpty) ||
        (widget.capturedShinyCards != null && widget.capturedShinyCards!.isNotEmpty);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // ═══════════════════════════════════════════════════
              // HEADER — Victory / Defeat title + stats
              // ═══════════════════════════════════════════════════
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      titleColor.withValues(alpha: 0.15),
                      titleColor.withValues(alpha: 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: titleColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Transform.scale(
                      scale: 0.85 + 0.15 * moneyT,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          letterSpacing: 4,
                          shadows: isWin
                              ? [Shadow(color: titleColor.withValues(alpha: 0.4), blurRadius: 24)]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$playerScore — $opponentScore  ${widget.opponentName}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Stats row: ₽ + Trainer XP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isWin && moneyReward > 0) ...[
                          _StatPill(
                            icon: Icons.monetization_on,
                            color: const Color(0xFFC9A44C),
                            label: '₽$animatedMoney',
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (growth != null && growth.trainerXpEarned > 0)
                          _StatPill(
                            icon: Icons.person,
                            color: Colors.cyan,
                            label: '+${growth.trainerXpEarned} XP',
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ═══════════════════════════════════════════════════
              // CARD SHOWCASE — Horizontal scrollable card row
              // ═══════════════════════════════════════════════════
              if (widget.playerDeck != null && widget.playerDeck!.cardIds.isNotEmpty) ...[
                _buildSectionLabel('BATTLE DECK', Icons.style),
                const SizedBox(height: 10),
                _buildCardShowcase(growth, cardT),
                const SizedBox(height: 16),
              ],

              // ═══════════════════════════════════════════════════
              // REWARDS — Captures + Evolutions
              // ═══════════════════════════════════════════════════
              if (hasCaptures || pendingEvolutions.isNotEmpty) ...[
                _buildSectionLabel('REWARDS', Icons.card_giftcard),
                const SizedBox(height: 10),
                _buildRewardsPanel(pendingEvolutions),
                const SizedBox(height: 16),
              ],

              // ═══════════════════════════════════════════════════
              // EXPANDED BREAKDOWN (shown when a card is tapped)
              // ═══════════════════════════════════════════════════
              if (_expandedCardIndex != null) ...[
                _buildXpBreakdown(_expandedCardIndex!),
                const SizedBox(height: 12),
              ],

              // ═══════════════════════════════════════════════════
              // ACTIONS
              // ═══════════════════════════════════════════════════
              if (widget.onContinue != null) ...[
                _GlassButton(
                  onTap: () {
                    AudioService().stopBgm();
                    widget.onContinue?.call();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Continue', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: _GlassButton(
                      onTap: () {
                        AudioService().stopBgm();
                        _rematch(context);
                      },
                      child: const Text('Rematch', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassButton(
                      onTap: () {
                        AudioService().stopBgm();
                        Navigator.popUntil(context, ModalRoute.withName(AppRoutes.home));
                      },
                      child: const Text('Back', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.35)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  /// Horizontal showcase of deck cards with full art and XP bars.
  Widget _buildCardShowcase(MatchGrowthResult? growth, double cardT) {
    final cardCount = widget.playerDeck!.cardIds.length;
    final cardWidth = 140.0;
    final totalWidth = cardCount * (cardWidth + 12) - 12;
    final hasData = growth != null;

    return SizedBox(
      height: 250,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth < 300 ? 300 : totalWidth,
          child: Row(
            children: List.generate(cardCount, (i) {
              final cardId = widget.playerDeck!.cardIds[i];
              final card = CardRepository.instance.cardById(cardId);
              if (card == null) return const SizedBox.shrink();
              final instId = widget.playerDeck!.instanceIds != null &&
                      i < widget.playerDeck!.instanceIds!.length
                  ? widget.playerDeck!.instanceIds![i]
                  : null;
              final xp = _xpForCard(cardId, instanceId: instId);
              final leveledUp = _cardLeveledUp(cardId, instanceId: instId);
              final cardGrowth = _growthForSlot(cardId, instId);
              final statBump = _statBumpedFor(cardId, instanceId: instId);
              final conditionLoss = hasData && instId != null
                  ? widget.finalState.conditionLossByInstanceId[instId] ?? 0
                  : 0;
              final displayCard = cardGrowth?.shiny == true
                  ? card.copyWith(shiny: true)
                  : card;

              // Staggered reveal delay
              final staggerDelay = (i * 0.1).clamp(0.0, 1.0);
              final cardReveal = ((cardT - staggerDelay) / 0.2).clamp(0.0, 1.0);

              return Padding(
                padding: EdgeInsets.only(right: i < cardCount - 1 ? 12 : 0),
                child: _buildShowcaseCard(
                  displayCard,
                  cardGrowth,
                  hasData ? xp : 0,
                  hasData ? leveledUp : false,
                  statBump,
                  conditionLoss,
                  cardReveal,
                  cardWidth,
                  () => setState(() {
                    _expandedCardIndex =
                        _expandedCardIndex == i ? null : i;
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildShowcaseCard(
    TriadCard card,
    CardGrowth? growth,
    int xpGained,
    bool leveledUp,
    String? statBumped,
    int conditionLoss,
    double reveal,
    double width,
    VoidCallback onTap,
  ) {
    final postXp = growth?.xp ?? 0;
    final oldXp = xpGained > 0 ? (postXp - xpGained).clamp(0, postXp) : postXp;
    final oldLevel = levelFromXp(oldXp).level;
    final hasXp = xpGained > 0;

    final newCondition = growth?.condition ?? kMaxCondition;
    final oldCondition = conditionLoss > 0
        ? (newCondition + conditionLoss).clamp(newCondition, kMaxCondition)
        : newCondition;
    final newTier = tierForCondition(newCondition);
    final oldTier = tierForCondition(oldCondition);
    final tierWorsened = conditionLoss > 0 && newTier.index > oldTier.index;
    final conditionColor = colorForConditionTier(newTier);

    return Transform.scale(
      scale: 0.85 + 0.15 * reveal,
      child: Opacity(
        opacity: reveal.clamp(0.0, 1.0),
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: width,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: leveledUp
                        ? const Color(0xFFFFB300).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                const SizedBox(height: 10),
                // Card art
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: TriadCardView(
                      card: card,
                      size: 80,
                      growth: growth,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Card name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    card.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Level badge
                _LevelBadge(level: oldLevel, shiny: growth?.shiny == true),
                const SizedBox(height: 4),
                // Condition change (GDD §31-32)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 11, color: conditionColor),
                    const SizedBox(width: 3),
                    Text(
                      conditionLoss > 0 ? '$oldCondition → $newCondition' : '$newCondition',
                      style: TextStyle(color: conditionColor, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (tierWorsened) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: conditionColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'NOW ${newTier.label.toUpperCase()}',
                      style: TextStyle(color: conditionColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                // XP bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _AnimatedXpBar(
                    currentXp: oldXp,
                    gainedXp: xpGained,
                    currentLevel: oldLevel,
                  ),
                ),
                const SizedBox(height: 4),
                // Badge area — fixed height so all cards are uniform
                SizedBox(
                  height: 36,
                  child: hasXp
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+$xpGained XP',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (leveledUp) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${statBumped != null ? "$statBumped ▲ " : ""}LEVEL UP!',
                                style: const TextStyle(
                                  color: Color(0xFFFFB300),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // Level-up glow overlay
          if (leveledUp)
            Positioned.fill(
              child: IgnorePointer(
                child: _LevelUpGlow(),
              ),
            ),
        ],
      ),
    ),
  ),
    );
  }

  /// Combined rewards panel: captures + evolution prompts.
  Widget _buildRewardsPanel(List<PendingEvolution> pendingEvolutions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pokéball capture
          if (widget.itemCapturedCard != null) ...[
            _buildCaptureRow(
              widget.itemCapturedCard!,
              icon: Icons.catching_pokemon,
              color: const Color(0xFF42A5F5),
              label: 'Pokéball Catch',
            ),
          ],
          // Regular captures
          if (widget.capturedCards != null &&
              widget.capturedCards!.isNotEmpty) ...[
            if (widget.itemCapturedCard != null)
              const Divider(color: Colors.white12, height: 20),
            for (final c in widget.capturedCards!)
              _buildCaptureRow(
                c,
                icon: Icons.catching_pokemon,
                color: const Color(0xFF4CAF50),
                label: 'Captured!',
              ),
          ],
          // Shiny captures
          if (widget.capturedShinyCards != null &&
              widget.capturedShinyCards!.isNotEmpty) ...[
            if (widget.itemCapturedCard != null ||
                (widget.capturedCards != null && widget.capturedCards!.isNotEmpty))
              const Divider(color: Colors.white12, height: 20),
            for (final c in widget.capturedShinyCards!)
              _buildCaptureRow(
                c,
                icon: Icons.auto_awesome,
                color: const Color(0xFFC9A44C),
                label: '⭐ SHINY',
              ),
          ],
          // Evolutions
          if (pendingEvolutions.isNotEmpty) ...[
            if (widget.itemCapturedCard != null ||
                (widget.capturedCards != null && widget.capturedCards!.isNotEmpty) ||
                (widget.capturedShinyCards != null && widget.capturedShinyCards!.isNotEmpty))
              const Divider(color: Colors.white12, height: 20),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14,
                    color: Colors.green.shade300),
                const SizedBox(width: 6),
                Text(
                  'Ready to Evolve',
                  style: TextStyle(
                    color: Colors.green.shade300,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final e in pendingEvolutions)
              _buildEvolutionPrompt(e),
          ],
        ],
      ),
    );
  }

  Widget _buildCaptureRow(TriadCard card, {
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: TriadCardView(card: card, size: 40),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card.name,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Get per-source XP breakdown for a card from MatchState.cardXp + server bonus.
  Map<String, int> _cardBreakdown(String cardId) {
    final result = <String, int>{};
    for (final xp in widget.finalState.cardXp.values) {
      if (xp.cardId == cardId) {
        result.addAll(xp.breakdown);
      }
    }
    // Include server bonus XP if available
    final bonus = _growthResult?.bonusXp[cardId] ?? 0;
    if (bonus > 0) {
      result['Win Bonus'] = bonus;
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
                        child: _buildResultsContent(0, 0, true, null, [], 0, moneyT: 0, cardT: 0),
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
    AudioService().playBgm('sound/battle_wild.ogg', volume: 0.05);
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
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _anim = _buildAnim();
    // If there's already XP to show, animate right away.
    // Otherwise, hold at start until data arrives.
    if (widget.gainedXp > 0) {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedXpBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gainedXp != oldWidget.gainedXp) {
      _anim = _buildAnim();
      _ctrl.reset();
      _ctrl.forward();
    }
  }

  Animation<double> _buildAnim() {
    return Tween<double>(
      begin: _startFrac(),
      end: _endFrac(),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  double _startFrac() {
    final oldXp = widget.currentXp;
    final actualLevel = levelFromXp(oldXp).level;
    final xpStartOfLevel = xpToReachLevel(actualLevel);
    final xpNextLevel = xpToReachLevel(actualLevel + 1);
    final xpInLevel = oldXp - xpStartOfLevel;
    final xpNeeded = xpNextLevel - xpStartOfLevel;
    return xpNeeded > 0 ? (xpInLevel / xpNeeded).clamp(0.0, 1.0) : 0.0;
  }

  double _endFrac() {
    final newXp = widget.currentXp + widget.gainedXp;
    final oldLevel = levelFromXp(widget.currentXp).level;
    final newLevel = levelFromXp(newXp).level;
    if (newLevel > oldLevel) {
      // Leveled up — bar fills to 1.0 then the build method handles the new-level display
      return 1.0;
    }
    final xpStartOfLevel = xpToReachLevel(oldLevel);
    final xpNextLevel = xpToReachLevel(oldLevel + 1);
    final xpNeeded = xpNextLevel - xpStartOfLevel;
    final xpAtEnd = newXp - xpStartOfLevel;
    return xpNeeded > 0 ? (xpAtEnd / xpNeeded).clamp(0.0, 1.0) : 0.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oldXp = widget.currentXp;
    final newXp = oldXp + widget.gainedXp;
    final oldLevel = levelFromXp(oldXp).level;
    final newLevel = widget.gainedXp > 0
        ? levelFromXp(newXp).level
        : oldLevel;
    final didLevelUp = newLevel > oldLevel;

    // After level-up, show XP range for the NEW level
    final displayLevel = didLevelUp ? newLevel : oldLevel;
    final xpStartOfLevel = xpToReachLevel(displayLevel);
    final xpNextLevel = xpToReachLevel(displayLevel + 1);
    final xpNeeded = xpNextLevel - xpStartOfLevel;
    // XP within the display level
    final xpInDisplayLevel = (newXp - xpStartOfLevel).clamp(0, xpNeeded);

    final startFrac = _startFrac();

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final currentFrac = _anim.value;

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
                            color: didLevelUp && _ctrl.value > 0.8
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
                      'Lv.$oldLevel → Lv.$newLevel',
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
                  '$xpInDisplayLevel / $xpNeeded',
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

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Golden sparkle particles for level-up celebration on showcase cards.
class _LevelUpGlow extends StatefulWidget {
  const _LevelUpGlow();

  @override
  State<_LevelUpGlow> createState() => _LevelUpGlowState();
}

class _LevelUpGlowState extends State<_LevelUpGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
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
      builder: (_, __) => CustomPaint(
        painter: _LevelUpGlowPainter(progress: _ctrl.value),
      ),
    );
  }
}

class _LevelUpGlowPainter extends CustomPainter {
  _LevelUpGlowPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i < 10; i++) {
      final x = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final y = baseY - (progress * 2.5 + i * 0.12 % 1.0) * size.height * 0.6;
      final life = ((progress * 3 + i * 0.14) % 1.0);
      final alpha = (life < 0.3 ? life / 0.3 : (1.0 - life) / 0.7).clamp(0.0, 1.0);
      final sz = 2.0 + alpha * 3.5;
      // Diamond shape (rotated square)
      final path = Path()
        ..moveTo(x, y - sz)
        ..lineTo(x + sz * 0.45, y)
        ..lineTo(x, y + sz)
        ..lineTo(x - sz * 0.45, y)
        ..close();
      // White fill
      fillPaint.color = Colors.white.withValues(alpha: alpha * 0.75);
      canvas.drawPath(path, fillPaint);
      // Bright core
      if (alpha > 0.4) {
        fillPaint.color = Colors.white.withValues(alpha: (alpha - 0.4) * 1.2 * 0.5);
        final innerSz = sz * 0.4;
        final innerPath = Path()
          ..moveTo(x, y - innerSz)
          ..lineTo(x + innerSz * 0.45, y)
          ..lineTo(x, y + innerSz)
          ..lineTo(x - innerSz * 0.45, y)
          ..close();
        canvas.drawPath(innerPath, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LevelUpGlowPainter old) => old.progress != progress;
}

/// Small stat pill used in the header (₽, Trainer XP).
class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Level badge displayed on showcase cards.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, this.shiny = false});
  final int level;
  final bool shiny;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: shiny
            ? const Color(0xFFC9A44C).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: shiny
            ? Border.all(color: const Color(0xFFC9A44C).withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lv.$level',
            style: TextStyle(
              color: shiny ? const Color(0xFFC9A44C) : Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (shiny) ...[
            const SizedBox(width: 3),
            const Text('✦', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 10)),
          ],
        ],
      ),
    );
  }
}
