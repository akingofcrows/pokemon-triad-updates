import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_set.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

/// Opens a booster pack — tap to rip the top off, then tap through a
/// stacked deck of 5 cards with manual reveal and fly-away animation.
class BoosterPackScreen extends StatefulWidget {
  const BoosterPackScreen({
    super.key,
    this.boosterName = 'field_trip',
    this.inventoryName,
    this.onDone,
    this.packCount = 1,
  });
  final String boosterName;
  final String? inventoryName;
  final VoidCallback? onDone;
  /// Number of packs to open in one session (cards = packCount × 5).
  final int packCount;

  @override
  State<BoosterPackScreen> createState() => _BoosterPackScreenState();
}

class _BoosterPackScreenState extends State<BoosterPackScreen>
    with TickerProviderStateMixin {
  final List<_BoosterCard> _cards = [];
  bool _saved = false;
  int _phase = 0; // 0=idle, 1=peeling, 2=stack, 3=all-revealed

  // ── Peel + pack shrink ──
  late AnimationController _peelCtrl;
  late Animation<double> _peelProgress;
  late Animation<double> _packShrink;
  late Animation<double> _peelFade;

  // ── Card stack: flip + fly ──
  int _stackIndex = 0;           // which card is on top (0–4)
  bool _topRevealed = false;     // is the top card face-up?
  final List<AnimationController> _flyCtrls = [];
  final List<Animation<double>> _flyOffsets = [];

  @override
  void initState() {
    super.initState();
    _generateCards();

    _peelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _peelProgress = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _peelCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)),
    );
    _peelFade = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _peelCtrl, curve: const Interval(0.5, 0.8, curve: Curves.easeOut)),
    );
    _packShrink = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _peelCtrl, curve: const Interval(0.6, 0.9, curve: Curves.easeIn)),
    );

    _peelCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _phase = 2);
      }
    });

    // Pre-create fly controllers for all cards
    final total = widget.packCount * 5;
    for (var i = 0; i < total; i++) {
      final fc = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
      );
      final fo = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: fc, curve: Curves.easeInBack),
      );
      _flyCtrls.add(fc);
      _flyOffsets.add(fo);
      fc.addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() {
            if (_stackIndex < total - 1) {
              _stackIndex++;
              _topRevealed = false;
            } else {
              _phase = 3;
            }
          });
        }
      });
    }
  }

  void _generateCards() {
    final rng = Random();
    // Pull from the booster's set if available
    final setId = _boosterSetId();
    final allCards = CardRepository.instance.allCards;
    List<TriadCard> pool;
    if (setId != null) {
      final setCardIds = CardRepository.instance.sets
          .firstWhere((s) => s.id == setId, orElse: () => CardSet(id: '', name: '', description: '', cardIds: []))
          .cardIds;
      pool = allCards.where((c) => setCardIds.contains(c.id)).toList();
      if (pool.isEmpty) pool = allCards;
    } else {
      pool = allCards.where((c) =>
        c.cardType == TriadCardType.pokemon &&
        !c.id.startsWith('card_trainer')).toList();
    }

    // Trainer cards: 10% chance per slot to pull a trainer instead of a Pokémon
    final trainerPool = allCards
        .where((c) => c.cardType == TriadCardType.trainer)
        .toList();

    // Track which card IDs we've already pulled in this booster to avoid
    // marking a duplicate as "new" incorrectly.
    final seenInThisBooster = <String>{};
    final everOwned = context.read<PlayerProfileController>().everOwnedCardIds;

    final totalCards = widget.packCount * 5;
    for (var i = 0; i < totalCards; i++) {
      final isTrainer = trainerPool.isNotEmpty && rng.nextInt(100) < 10;
      TriadCard card;
      int level;
      bool isShiny;
      int bonusN = 0, bonusS = 0, bonusE = 0, bonusW = 0;

      if (isTrainer) {
        card = trainerPool[rng.nextInt(trainerPool.length)];
        level = 1;
        isShiny = false; // trainers can't be shiny
      } else {
        final roll = rng.nextInt(100);
        List<TriadCard> tier;
        if (roll < 60) {
          tier = pool.where((c) => c.rarity == CardRarity.common).toList();
        } else if (roll < 90) {
          tier = pool.where((c) => c.rarity == CardRarity.uncommon).toList();
        } else if (roll < 98) {
          tier = pool.where((c) => c.rarity == CardRarity.rare).toList();
        } else {
          tier = pool.where((c) => c.rarity == CardRarity.epic || c.rarity == CardRarity.legendary).toList();
        }
        if (tier.isEmpty) tier = pool;

        card = tier[rng.nextInt(tier.length)];
        level = 1 + rng.nextInt(5);
        isShiny = rng.nextInt(64) == 0;
        final bonus = CardValues(
          north: rng.nextInt(3), south: rng.nextInt(3),
          east: rng.nextInt(3), west: rng.nextInt(3),
        );
        bonusN = bonus.north;
        bonusS = bonus.south;
        bonusE = bonus.east;
        bonusW = bonus.west;
        card = card.copyWith(values: card.values.plusBonus(bonus), shiny: isShiny, baseLevel: level);
      }

      // Holo / reverse holo: only apply to cards that are marked holo in cards.json
      // 30% chance to be reverse holo instead of regular holo
      if (card.holo) {
        final isReverseHolo = rng.nextInt(100) < 30;
        card = card.copyWith(reverseHolo: isReverseHolo);
      }

      // Card is "new" only the first time it appears in this booster
      // and the player has never owned it before.
      final isNewForPlayer = !everOwned.contains(card.id) && !seenInThisBooster.contains(card.id);
      seenInThisBooster.add(card.id);

      _cards.add(_BoosterCard(
        card: card,
        level: level,
        isShiny: isShiny,
        bonusNorth: bonusN,
        bonusSouth: bonusS,
        bonusEast: bonusE,
        bonusWest: bonusW,
        isNew: isNewForPlayer,
      ));
    }
  }

  void _startRip() {
    if (_phase != 0) return;
    setState(() => _phase = 1);
    _peelCtrl.forward();
  }

  void _onStackTap() {
    if (_phase != 2) return;
    if (!_topRevealed) {
      // Reveal the top card
      setState(() => _topRevealed = true);
    } else {
      // Fly the revealed card off north
      _flyCtrls[_stackIndex].forward();
    }
  }

  Future<void> _saveAndClose() async {
    if (_saved) return;
    _saved = true;
    // Consume the booster(s) from inventory
    if (widget.inventoryName != null) {
      for (var p = 0; p < widget.packCount; p++) {
        context.read<PlayerProfileController>().openBoosterFromInventory(widget.inventoryName!);
      }
    }
    try {
      await context.read<PlayerProfileController>().addBoosterCards(
        _cards.map((c) => {
          'cardId': c.card.id,
          'level': c.level,
          'isShiny': c.isShiny,
          'bonusNorth': c.bonusNorth,
          'bonusSouth': c.bonusSouth,
          'bonusEast': c.bonusEast,
          'bonusWest': c.bonusWest,
        }).toList(),
      );
    } catch (_) {}
    if (mounted) {
      Navigator.pop(context);
      // If chaining, trigger the next booster after this screen is popped
      widget.onDone?.call();
    }
  }

  String get _packImagePath {
    switch (widget.boosterName) {
      case 'safari':
        return 'assets/images/Booster Pack/safari.png';
      case 'urban':
        return 'assets/images/Booster Pack/urban.png';
      case 'kanto':
        return 'assets/images/Booster Pack/kanto.png';
      default:
        return 'assets/images/Booster Pack/field.png';
    }
  }

  String get _snippedImagePath {
    switch (widget.boosterName) {
      case 'safari':
        return 'assets/images/Booster Pack/safari_snipped.png';
      case 'urban':
        return 'assets/images/Booster Pack/urban_snipped.png';
      case 'kanto':
        return 'assets/images/Booster Pack/kanto_snipped.png';
      case 'gold':
        return 'assets/images/Booster Pack/gold_snipped.png';
      case 'silver':
        return 'assets/images/Booster Pack/silver_snipped.png';
      case 'johto':
        return 'assets/images/Booster Pack/johto_snipped.png';
      default:
        return 'assets/images/Booster Pack/field_snipped.png';
    }
  }

  String _displayName() {
    switch (widget.boosterName) {
      case 'safari':
        return 'Safari Tour Booster';
      case 'urban':
        return 'Urban Life Booster';
      case 'kanto':
        return 'Kanto Collection';
      default:
        return 'Field Trip Booster';
    }
  }

  String? _boosterSetId() {
    // Look up the set ID from boosters.json for this booster
    switch (widget.boosterName) {
      case 'field_trip':
        return 'field_trip';
      case 'safari':
        return 'safari_tour';
      case 'urban':
        return 'urban_life';
      case 'kanto':
        return 'base';
      default:
        return null;
    }
  }

  static const _packW = 180.0;
  static const _cardSize = 128.0;

  @override
  void dispose() {
    _peelCtrl.dispose();
    for (final c in _flyCtrls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      body: SafeArea(
        child: Stack(
          children: [
            // ── Title ──
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: Text(
                  _displayName().toUpperCase(),
                  style: TextStyle(
                    color: _phase >= 2 ? Colors.amber : Colors.amber.withValues(alpha: 0.5),
                    fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3,
                  ),
                ),
              ),
            ),

            // ── Stacked cards (phase 2) ──
            if (_phase >= 2 && _phase < 3)
              GestureDetector(
                onTap: _onStackTap,
                child: Center(
                  child: SizedBox(
                    width: _cardSize + 40, height: _cardSize + 80,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Cards underneath the top one (max 4 visible, smaller, fanned)
                        for (var j = 1; j <= 4 && _stackIndex + j < _cards.length; j++)
                          Positioned(
                            bottom: 0,
                            child: Transform.rotate(
                              angle: j * 0.04,
                              child: Container(
                                width: (_cardSize - j * 6).clamp(20.0, _cardSize),
                                height: (_cardSize - j * 6).clamp(20.0, _cardSize),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: const DecorationImage(
                                    image: AssetImage('assets/ui/card_back.png'),
                                    fit: BoxFit.cover,
                                  ),
                                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 4, offset: const Offset(0, 2))],
                                ),
                              ),
                            ),
                          ),
                        // Top card — flips on tap, flies away on second tap
                        AnimatedBuilder(
                          key: ValueKey(_stackIndex),
                          animation: _flyOffsets[_stackIndex],
                          builder: (context, _) {
                            final fly = _flyOffsets[_stackIndex].value;
                            // Only show the card being flown if it's still in the stack;
                            // once _stackIndex advances, this card is gone.
                            return Positioned(
                              bottom: 0,
                              child: Opacity(
                                opacity: (1 - fly).clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, -fly * 800), // fly upward (north)
                                  child: Transform.scale(
                                    scale: 1 - fly * 0.3,
                                    child: _TriadFlipCard(
                                      card: _cards[_stackIndex].card,
                                      size: _cardSize,
                                      revealed: _topRevealed,
                                      isShiny: _cards[_stackIndex].isShiny,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Tap prompt during stack phase ──
            if (_phase == 2)
              Positioned(
                bottom: 80, left: 0, right: 0,
                child: Center(
                  child: Text(
                    _topRevealed ? 'TAP TO CONTINUE' : 'TAP TO REVEAL',
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.7),
                      fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2,
                    ),
                  ),
                ),
              ),

            // ── Pack + peel (phases 0–1) ──
            if (_phase < 2)
              Center(
                child: AnimatedBuilder(
                  animation: _peelCtrl,
                  builder: (context, _) {
                    final peel = _peelProgress.value;
                    final fade = _peelFade.value;
                    final shrink = _packShrink.value;

                    return GestureDetector(
                      onTap: _phase == 0 ? _startRip : null,
                      child: SizedBox(
                        width: _packW + 80, height: 360,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // ── Pack image ──
                            Positioned(
                              bottom: 0,
                              child: Opacity(
                                opacity: shrink.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: 0.6 + shrink * 0.4,
                                  child: Image.asset(_packImagePath, width: _packW, fit: BoxFit.contain),
                                ),
                              ),
                            ),

                            // ── Snipped top — peels off with curl effect ──
                            if (peel > 0.01)
                              Positioned(
                                top: 0,
                                child: Opacity(
                                  opacity: fade,
                                  child: Transform(
                                    alignment: Alignment.centerLeft,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.001) // perspective
                                      ..rotateY(-peel * 0.5)   // curl back
                                      ..translate(peel * 40.0), // slide right
                                    child: ClipRect(
                                      clipper: _PeelClipper(peel),
                                      child: Image.asset(_snippedImagePath, width: _packW, fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                              ),

                            // ── Tap prompt ──
                            if (_phase == 0)
                              Positioned(
                                bottom: -40, left: 0, right: 0,
                                child: Center(
                                  child: Text(
                                    'TAP TO OPEN',
                                    style: TextStyle(
                                      color: Colors.amber.withValues(alpha: 0.8),
                                      fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 3,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Summary grid (phase 3) ──
            if (_phase >= 3)
              Positioned.fill(
                top: 65,
                bottom: 80,
                child: SingleChildScrollView(
                  child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        '${_cards.length} cards collected!',
                        style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.68,
                      ),
                        itemCount: _cards.length,
                        itemBuilder: (context, i) {
                          final c = _cards[i];
                          final isRare = c.card.rarity == CardRarity.rare ||
                              c.card.rarity == CardRarity.epic ||
                              c.card.rarity == CardRarity.legendary;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  TriadCardView(card: c.card, size: 100),
                                  if (c.isNew)
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: Image.asset('assets/ui/new.png', width: 28, height: 28),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 100,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(5),
                                  border: isRare
                                      ? Border.all(color: const Color(0xFFC9A44C).withValues(alpha: 0.4), width: 1)
                                      : null,
                                ),
                                child: Text(
                                  '${c.card.name} Lvl.${c.level}',
                                  style: TextStyle(
                                    color: isRare ? const Color(0xFFC9A44C) : Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
              ),

            // ── Save button ──
            if (_phase >= 3)
              Positioned(
                bottom: 24, left: 24, right: 24,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveAndClose,
                    child: const Text('Add to Collection'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reveals the snipped top piece from left to right as [fraction] goes 0→1.
class _PeelClipper extends CustomClipper<Rect> {
  _PeelClipper(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => oldClipper is _PeelClipper && oldClipper.fraction != fraction;
}

class _BoosterCard {
  final TriadCard card;
  final int level;
  final bool isShiny;
  final int bonusNorth;
  final int bonusSouth;
  final int bonusEast;
  final int bonusWest;
  final bool isNew;
  const _BoosterCard({
    required this.card,
    required this.level,
    required this.isShiny,
    required this.bonusNorth,
    required this.bonusSouth,
    required this.bonusEast,
    required this.bonusWest,
    this.isNew = false,
  });
}

/// True 3D card flip — Y-axis rotation with perspective,
/// switching from back image to [TriadCardView] at the halfway point.
/// If [isShiny], plays a sparkle shimmer animation after the flip completes.
class _TriadFlipCard extends StatefulWidget {
  const _TriadFlipCard({
    required this.card,
    required this.size,
    required this.revealed,
    this.isShiny = false,
  });
  final TriadCard card;
  final double size;
  final bool revealed;
  final bool isShiny;

  @override
  State<_TriadFlipCard> createState() => _TriadFlipCardState();
}

class _TriadFlipCardState extends State<_TriadFlipCard>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _flip;
  late AnimationController _sparkleCtrl;
  late Animation<double> _sparkleAnim;
  late AnimationController _slamCtrl;
  late Animation<double> _slamScale;
  bool _sparkled = false;
  bool _slammed = false;

  bool get _isSpecial => widget.card.rarity == CardRarity.rare ||
      widget.card.rarity == CardRarity.epic ||
      widget.card.rarity == CardRarity.legendary ||
      widget.card.holo;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _flip = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.revealed) _ctrl.value = 1.0;

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (widget.isShiny && !_sparkled) {
          _sparkled = true;
          _sparkleCtrl.repeat();
        }
        if (_isSpecial && !_slammed) {
          _slammed = true;
          _slamCtrl.forward();
        }
      }
    });

    _slamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    // Slam intensity: legendary > epic > holo > rare
    final slamPeak = widget.card.rarity == CardRarity.legendary ? 1.6 :
        widget.card.rarity == CardRarity.epic ? 1.45 :
        widget.card.holo ? 1.4 : 1.25;
    final slamBounce = widget.card.rarity == CardRarity.legendary ? 0.85 :
        widget.card.rarity == CardRarity.epic ? 0.9 :
        widget.card.holo ? 0.9 : 0.95;
    _slamScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: slamPeak), weight: 25),
      TweenSequenceItem(tween: Tween(begin: slamPeak, end: slamBounce), weight: 20),
      TweenSequenceItem(tween: Tween(begin: slamBounce, end: 1.03), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _slamCtrl, curve: Curves.easeOut));

    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _sparkleAnim = CurvedAnimation(
      parent: _sparkleCtrl,
      curve: Curves.easeInOut,
    );

    if (widget.revealed && widget.isShiny && !_sparkled) {
      _sparkled = true;
      _sparkleCtrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _TriadFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.revealed && widget.revealed) {
      _ctrl.forward();
    }
    // Trigger sparkle when flip completes on a shiny card
    if (widget.revealed && widget.isShiny && !_sparkled && _ctrl.isCompleted) {
      _sparkled = true;
      _sparkleCtrl.forward();
    }
    // Slam rare/legendary/holo cards when flip completes
    if (widget.revealed && _isSpecial && !_slammed && _ctrl.isCompleted) {
      _slammed = true;
      _slamCtrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sparkleCtrl.dispose();
    _slamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flip, _sparkleCtrl, _slamCtrl]),
      builder: (context, _) {
        final angle = _flip.value * pi;
        final showFront = _flip.value > 0.5;
        final sparkleProgress = _sparkleAnim.value;
        final slamScale = _slamScale.value;

        // Trigger sparkle + slam on flip completion
        if (showFront && _ctrl.isCompleted) {
          if (widget.isShiny && !_sparkled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) { _sparkled = true; _sparkleCtrl.forward(); }
            });
          }
          if (_isSpecial && !_slammed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) { _slammed = true; _slamCtrl.forward(); }
            });
          }
        }

        return Transform.scale(
          scale: slamScale,
          child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: showFront
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(pi),
                        child: TriadCardView(card: widget.card, size: widget.size),
                      ),
                      // Sparkle overlay for shiny cards
                      if (widget.isShiny && sparkleProgress > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _SparklePainter(progress: sparkleProgress),
                            ),
                          ),
                        ),
                    ],
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: const DecorationImage(
                        image: AssetImage('assets/ui/card_back.png'),
                        fit: BoxFit.cover,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        );
      },
    );
  }
}

/// Paints white diamond sparkles radiating from center.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final cx = size.width / 2, cy = size.height / 2;
    final rng = Random(42);
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < 20; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final dist = (40 + rng.nextDouble() * size.width * 0.8) * progress;
      final x = cx + cos(angle) * dist;
      final y = cy + sin(angle) * dist;
      final life = ((progress * 2.0 + i * 0.15) % 1.0);
      final alpha = (life < 0.4 ? life / 0.4 : (1.0 - life) / 0.6).clamp(0.0, 1.0);
      final sz = 3.0 + alpha * 5.0;

      // Diamond shape
      final path = Path()
        ..moveTo(x, y - sz)
        ..lineTo(x + sz * 0.35, y - sz * 0.3)
        ..lineTo(x + sz, y)
        ..lineTo(x + sz * 0.35, y + sz * 0.3)
        ..lineTo(x, y + sz)
        ..lineTo(x - sz * 0.35, y + sz * 0.3)
        ..lineTo(x - sz, y)
        ..lineTo(x - sz * 0.35, y - sz * 0.3)
        ..close();

      // Outer glow
      fillPaint.color = Colors.white.withValues(alpha: alpha * 0.15);
      canvas.drawPath(path, fillPaint);
      // Diamond fill
      fillPaint.color = Colors.white.withValues(alpha: alpha * 0.9);
      canvas.drawPath(path, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
