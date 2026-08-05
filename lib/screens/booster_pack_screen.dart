import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_set.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

/// Opens a booster pack — tap to rip, 5 cards fan out as backs,
/// then flip one by one to reveal.
class BoosterPackScreen extends StatefulWidget {
  const BoosterPackScreen({
    super.key,
    this.boosterName = 'field_trip',
    this.inventoryName,
    this.onDone,
  });
  final String boosterName;
  /// The raw inventory key to consume when the booster is opened.
  /// If null, no inventory item is consumed (used for reward boosters).
  final String? inventoryName;
  /// Called after the player taps "Add to Collection" and cards are saved.
  /// Used for chaining multiple booster openings.
  final VoidCallback? onDone;

  @override
  State<BoosterPackScreen> createState() => _BoosterPackScreenState();
}

class _BoosterPackScreenState extends State<BoosterPackScreen>
    with SingleTickerProviderStateMixin {
  final List<_BoosterCard> _cards = [];
  int _revealed = 0;
  bool _saved = false;
  int _phase = 0; // 0=idle, 1=ripping, 2=cards-out, 3=flipping

  late AnimationController _ctrl;
  late Animation<double> _ripOffset;
  late Animation<double> _ripOpacity;
  late Animation<double> _cardsSpread;
  late Animation<double> _packShrink;

  @override
  void initState() {
    super.initState();
    _generateCards();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _ripOffset = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.1, 0.3, curve: Curves.easeInBack)),
    );
    _ripOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.35, curve: Curves.easeOut)),
    );
    _cardsSpread = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.6, curve: Curves.easeOutCubic)),
    );
    _packShrink = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.45, 0.6, curve: Curves.easeIn)),
    );

    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _phase = 3);
        _flipNext();
      }
    });
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

    for (var i = 0; i < 5; i++) {
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

      // Holo / reverse holo: 10% chance for any card
      final isHolo = rng.nextInt(100) < 10;
      final isReverseHolo = isHolo && rng.nextInt(100) < 30;
      card = card.copyWith(holo: isHolo, reverseHolo: isReverseHolo);

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
    _ctrl.forward();
  }

  void _flipNext() {
    if (_revealed >= 5) return;
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      setState(() => _revealed++);
      _flipNext();
    });
  }

  Future<void> _saveAndClose() async {
    if (_saved) return;
    _saved = true;
    // Consume the booster from inventory only when actually opening
    if (widget.inventoryName != null) {
      context.read<PlayerProfileController>().openBoosterFromInventory(widget.inventoryName!);
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
      default:
        return 'assets/images/Booster Pack/field.png';
    }
  }

  String _displayName() {
    switch (widget.boosterName) {
      case 'safari':
        return 'Safari Tour Booster';
      case 'urban':
        return 'Urban Life Booster';
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
      default:
        return null;
    }
  }

  static const _packW = 180.0;
  static const _cardSize = 128.0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
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
                    color: _phase >= 3 ? Colors.amber : Colors.amber.withValues(alpha: 0.5),
                    fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3,
                  ),
                ),
              ),
            ),

            // ── Card grid (after reveal) ──
            if (_phase >= 3)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Wrap(
                    spacing: 6, runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: List.generate(_cards.length, (i) {
                      final c = _cards[i];
                      final revealed = i < _revealed;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _TriadFlipCard(
                            card: c.card,
                            size: _cardSize,
                            revealed: revealed,
                            isShiny: c.isShiny,
                          ),
                          if (revealed && c.isNew)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Image.asset(
                                'assets/ui/new.png',
                                width: 36,
                                height: 36,
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                ),
              ),

            // ── Pack + emerging cards (phases 0–2) ──
            if (_phase < 3)
              Center(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final rip = _ripOffset.value;
                    final ripFade = _ripOpacity.value;
                    final spread = _cardsSpread.value;
                    final shrink = _packShrink.value;

                    return GestureDetector(
                      onTap: _phase == 0 ? _startRip : null,
                      child: SizedBox(
                        width: _packW + 80, height: 360,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            // ── Cards fanning out behind pack ──
                            ...List.generate(5, (i) {
                              final s = (spread - i * 0.06).clamp(0.0, 1.0);
                              final xOff = (i - 2) * 55 * s;
                              final rotation = (i - 2) * 0.12 * s;
                              return Positioned(
                                bottom: 40 + (1 - s) * 50,
                                left: _packW / 2 - _cardSize * 0.35 + xOff + 40,
                                child: Transform.rotate(
                                  angle: rotation,
                                  child: Opacity(
                                    opacity: s.clamp(0.0, 1.0),
                                    child: Container(
                                      width: _cardSize * 0.7, height: _cardSize * 0.7,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        image: const DecorationImage(
                                          image: AssetImage('assets/ui/card_back.png'),
                                          fit: BoxFit.cover,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 5,
                                            offset: Offset(0, 4 - s * 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),

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

                            // ── Torn top piece ──
                            if (rip > 0.01)
                              Positioned(
                                top: 30 - rip * 80,
                                child: Opacity(
                                  opacity: ripFade,
                                  child: Transform.rotate(
                                    angle: rip * 0.2,
                                    child: ClipRect(
                                      clipper: _TopClipper(0.52),
                                      child: Image.asset(_packImagePath, width: _packW, fit: BoxFit.contain),
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

            // ── Remaining counter ──
            if (_phase >= 3 && _revealed < 5)
              Positioned(
                top: 52, left: 0, right: 0,
                child: Center(
                  child: Text(
                    '${5 - _revealed} cards remaining...',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                  ),
                ),
              ),

            // ── Save button ──
            if (_revealed >= 5)
              Positioned(
                bottom: 24, left: 24, right: 24,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveAndClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Add to Collection', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopClipper extends CustomClipper<Rect> {
  _TopClipper(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * fraction);
  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
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
  bool _sparkled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _flip = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.revealed) _ctrl.value = 1.0;

    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _sparkleAnim = CurvedAnimation(
      parent: _sparkleCtrl,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _sparkleCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _sparkleCtrl.reverse();
      }
    });

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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sparkleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flip, _sparkleCtrl]),
      builder: (context, _) {
        final angle = _flip.value * pi;
        final showFront = _flip.value > 0.5;
        final sparkleProgress = _sparkleAnim.value;

        // Trigger sparkle on flip completion for shiny
        if (showFront && widget.isShiny && !_sparkled && _ctrl.isCompleted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _sparkled = true;
              _sparkleCtrl.forward();
            }
          });
        }

        return SizedBox(
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
        );
      },
    );
  }
}

/// Paints golden sparkle particles that fade in and out.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rng = Random(42); // fixed seed for consistent sparkle positions
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final sparkleLife = ((progress * 3 + i * 0.17) % 1.0);
      final alpha = sparkleLife < 0.5
          ? sparkleLife * 2 // fade in
          : (1.0 - sparkleLife) * 2; // fade out

      // Alternate gold and white sparkles
      final isGold = i % 3 != 0;
      paint.color = isGold
          ? const Color(0xFFFFD700).withValues(alpha: alpha * 0.9)
          : Colors.white.withValues(alpha: alpha * 0.8);

      final radius = (1.5 + rng.nextDouble() * 3) * (1.0 + progress * 0.5);
      // Draw a 4-point star shape
      final cx = x;
      final cy = y;

      // Simple diamond/star
      final path = Path()
        ..moveTo(cx, cy - radius * 1.5)
        ..lineTo(cx + radius * 0.4, cy - radius * 0.4)
        ..lineTo(cx + radius * 1.5, cy)
        ..lineTo(cx + radius * 0.4, cy + radius * 0.4)
        ..lineTo(cx, cy + radius * 1.5)
        ..lineTo(cx - radius * 0.4, cy + radius * 0.4)
        ..lineTo(cx - radius * 1.5, cy)
        ..lineTo(cx - radius * 0.4, cy - radius * 0.4)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
