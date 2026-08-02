import 'dart:math';

import 'package:flutter/material.dart';

import '../models/card_growth.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import 'triad_card_view.dart';

/// Full-screen evolution animation modal, styled after the mainline games:
/// sprite whites out → strobes between the whited-out old/new forms with
/// sparkles orbiting it → flashes and settles on the fully-colored evolution.
class EvolutionAnimation extends StatefulWidget {
  const EvolutionAnimation({
    super.key,
    required this.fromCard,
    required this.toCard,
    required this.onComplete,
    this.fromBonuses,
    this.toBonusesFuture,
  });

  final TriadCard fromCard;
  final TriadCard toCard;
  final VoidCallback onComplete;
  final CardValues? fromBonuses;

  /// Resolves to the evolved card's real N/S/E/W bonus — evolving randomly
  /// trims each stat's bonus rather than carrying it over intact, so this
  /// can't just reuse [fromBonuses]. Falls back to [fromBonuses] until (or
  /// if) it resolves; both stat display and the card face aren't shown
  /// until well after the strobe/flash/slam runway, so there's no visible
  /// flicker as long as the evolve call finishes before then.
  final Future<CardValues?>? toBonusesFuture;

  @override
  State<EvolutionAnimation> createState() => _EvolutionAnimationState();
}

class _EvolutionAnimationState extends State<EvolutionAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _phaseCtrl;
  late final Animation<double> _fadeIn;

  // Runs after _phaseCtrl finishes: the card frame/bg/numbers assemble
  // behind the sprite, then the sprite slams down onto it.
  late final AnimationController _slamCtrl;
  late final Future<void> _cardAssetsReady;
  bool _impactTriggered = false;
  bool _cardRevealed = false;

  // The evolved card's real bonus, once the evolve call resolves — see
  // [EvolutionAnimation.toBonusesFuture].
  late CardValues? _toBonuses;

  // Phase boundaries (fraction of _phaseCtrl's 0..1 range).
  static const _introEnd = 0.12;
  static const _strobeEnd = 0.80;
  static const _revealStart = 0.90;
  static const _toggleCount = 10;

  final List<_Sparkle> _sparkles = [];
  final _rng = Random();
  bool _showEvolved = false;
  int _toggleIdx = -1;

  @override
  void initState() {
    super.initState();

    _toBonuses = widget.fromBonuses;
    widget.toBonusesFuture?.then((v) {
      if (mounted && v != null) setState(() => _toBonuses = v);
    });

    _phaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );

    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _phaseCtrl,
        curve: const Interval(0.0, _introEnd, curve: Curves.easeIn),
      ),
    );

    _phaseCtrl.addListener(() {
      final t = _phaseCtrl.value;
      if (t >= _introEnd && t < _strobeEnd) {
        final localT = ((t - _introEnd) / (_strobeEnd - _introEnd)).clamp(
          0.0,
          1.0,
        );
        final newIdx = (localT * _toggleCount).floor().clamp(
          0,
          _toggleCount - 1,
        );
        if (newIdx != _toggleIdx) {
          _toggleIdx = newIdx;
          _showEvolved = _toggleIdx.isOdd;
          _spawnSparkles();
          setState(() {});
        }
      } else {
        // Force a rebuild each frame for the flash/reveal phases too.
        setState(() {});
      }
    });

    _phaseCtrl.addStatusListener((status) async {
      if (status != AnimationStatus.completed) return;
      _spawnSparkles(burst: true);
      setState(() {});
      // Card art (bg/frame/numbers/type icon) is a different asset set than
      // the battle sprites used above — make sure it's decoded before the
      // slam so the card doesn't pop in blank underneath the sprite.
      await _cardAssetsReady;
      if (mounted) _slamCtrl.forward();
    });

    _slamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _slamCtrl.addListener(() {
      if (!_impactTriggered && _slamCtrl.value >= 0.55) {
        _impactTriggered = true;
        _spawnSparkles(burst: true);
      }
      setState(() {});
    });
    _slamCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed)
        setState(() => _cardRevealed = true);
    });

    // The card face uses widget.toCard's normal artwork, not the strobe's
    // front-sprite assets, so it needs its own preload — kick it off now,
    // it has the whole strobe/flash runway (a few seconds) to finish.
    _cardAssetsReady = TriadCardView.preloadAssets(
      widget.toCard,
      shiny: widget.toCard.shiny,
    );

    _spawnSparkles();
    _phaseCtrl.forward();
  }

  void _spawnSparkles({bool burst = false}) {
    _sparkles.clear();
    final count = burst ? 20 : 10;
    for (var i = 0; i < count; i++) {
      _sparkles.add(_Sparkle.random(_rng, i, count));
    }
  }

  @override
  void dispose() {
    _phaseCtrl.dispose();
    _slamCtrl.dispose();
    super.dispose();
  }

  String get _spriteFolder {
    return widget.fromCard.shiny
        ? 'assets/sprites/front_shiny'
        : 'assets/sprites/front';
  }

  String get _fromSpritePath {
    final name = widget.fromCard.name.toUpperCase().replaceAll(' ', '_');
    return '$_spriteFolder/$name.png';
  }

  String get _toSpritePath {
    final name = widget.toCard.name.toUpperCase().replaceAll(' ', '_');
    return '$_spriteFolder/$name.png';
  }

  @override
  Widget build(BuildContext context) {
    final t = _phaseCtrl.value;
    final inStrobe = t >= _introEnd && t < _strobeEnd;
    final inFlash = t >= _strobeEnd && t < _revealStart;
    final revealed = t >= _revealStart;
    final flashLocalT = inFlash
        ? ((t - _strobeEnd) / (_revealStart - _strobeEnd)).clamp(0.0, 1.0)
        : (revealed ? 1.0 : 0.0);

    // Glow ramps up through the strobe, peaks mid-flash, fades once revealed.
    final glow = inStrobe
        ? (((t - _introEnd) / (_strobeEnd - _introEnd)).clamp(0.0, 1.0)) * 0.6
        : inFlash
        ? (sin(pi * flashLocalT)).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _cardRevealed ? widget.onComplete : null,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Text(
                        'Oh! ${widget.fromCard.name} is evolving!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Sprite + orbiting sparkles, all relative to one fixed box
                  // so the particles stay anchored around the Pokémon.
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft energy glow behind the sprite
                        if (glow > 0)
                          Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(
                                    alpha: glow * 0.55,
                                  ),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),

                        if (_phaseCtrl.isCompleted)
                          _buildCardAssembly()
                        else
                          _buildSpriteBox(
                            glow: glow,
                            child: _buildSpriteStack(
                              t,
                              inStrobe,
                              inFlash,
                              revealed,
                              flashLocalT,
                            ),
                          ),

                        // Sparkles orbiting the sprite
                        ..._sparkles.map((s) => s.buildWidget()),
                      ],
                    ),
                  ),

                  if (_cardRevealed)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        children: [
                          Text(
                            widget.toCard.name,
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(2, 2),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildEvolvedStatComparison(),
                          const SizedBox(height: 20),
                          Text(
                            '${widget.fromCard.name} has evolved into ${widget.toCard.name}!',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(1, 1),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _TapToContinueHint(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The sprite content: whited-out silhouette that strobes between the
  /// pre- and post-evolution forms, then crossfades into the real,
  /// full-color evolved sprite.
  Widget _buildSpriteStack(
    double t,
    bool inStrobe,
    bool inFlash,
    bool revealed,
    double flashLocalT,
  ) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (!revealed)
          Opacity(
            opacity: inFlash ? (1 - flashLocalT) : 1,
            child: t < _introEnd
                ? _spriteImage(_fromSpritePath, silhouette: false)
                : _spriteImage(
                    _showEvolved ? _toSpritePath : _fromSpritePath,
                    silhouette: true,
                  ),
          ),
        Opacity(
          opacity: revealed ? 1 : (inFlash ? flashLocalT : 0),
          child: _spriteImage(_toSpritePath, silhouette: false),
        ),
      ],
    );
  }

  /// Proxies the evolved card's real (post-loss) bonus into a [CardGrowth]
  /// so the assembled card's numbers match what
  /// [_buildEvolvedStatComparison] shows.
  CardGrowth? get _displayGrowth {
    final bonus = _toBonuses;
    if (bonus == null) return null;
    return CardGrowth(
      cardId: widget.toCard.id,
      xp: 0,
      level: 0,
      bonusNorth: bonus.north,
      bonusSouth: bonus.south,
      bonusEast: bonus.east,
      bonusWest: bonus.west,
      shiny: widget.toCard.shiny,
    );
  }

  /// The post-strobe finale: the card frame/bg/numbers assemble behind the
  /// sprite, then the sprite slams down onto it. Once fully landed, swaps
  /// to the real card (with its actual artwork) as the permanent display.
  Widget _buildCardAssembly() {
    if (_cardRevealed) {
      return TriadCardView(
        card: widget.toCard,
        size: 150,
        growth: _displayGrowth,
      );
    }

    final slamT = _slamCtrl.value;
    double dropOffset;
    double squashX = 1.0, squashY = 1.0;
    if (slamT < 0.55) {
      final fallT = Curves.easeIn.transform((slamT / 0.55).clamp(0.0, 1.0));
      dropOffset = -70 * (1 - fallT);
    } else if (slamT < 0.72) {
      dropOffset = 0;
      final bounceT = ((slamT - 0.55) / 0.17).clamp(0.0, 1.0);
      final s = sin(pi * bounceT);
      squashX = 1 + s * 0.18;
      squashY = 1 - s * 0.22;
    } else {
      dropOffset = 0;
    }

    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Card frame/bg/numbers assemble first, sprite lands after.
          Opacity(
            opacity: slamT.clamp(0.0, 1.0),
            child: TriadCardView(
              card: widget.toCard.copyWith(image: ''),
              size: 150,
              growth: _displayGrowth,
            ),
          ),
          Transform.translate(
            offset: Offset(0, dropOffset),
            child: Transform.scale(
              scaleX: squashX,
              scaleY: squashY,
              child: _spriteImage(_toSpritePath, silhouette: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpriteBox({required Widget child, double glow = 0}) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15 + glow * 0.4),
        ),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: child),
    );
  }

  Widget _spriteImage(String path, {required bool silhouette}) {
    final image = Image.asset(
      path,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.catching_pokemon, color: Colors.white24, size: 64),
    );
    if (!silhouette) return image;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: image,
    );
  }

  Widget _buildEvolvedStatComparison() {
    final fromBonus = widget.fromBonuses;
    final toBonus = _toBonuses;
    final fromV = fromBonus != null
        ? widget.fromCard.values.plusBonus(fromBonus)
        : widget.fromCard.values;
    // The "new" total needs the evolved card's own (post-loss) bonus, not
    // the pre-evolve one — otherwise this shows a number that doesn't match
    // the card face right above it (or reality, once evolveCard() lands).
    final toV = toBonus != null
        ? widget.toCard.values.plusBonus(toBonus)
        : widget.toCard.values;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statPill(
          'N',
          fromV.north,
          toV.north,
          bonus: toBonus?.north ?? 0,
          bonusLoss: (fromBonus?.north ?? 0) - (toBonus?.north ?? 0),
        ),
        const SizedBox(width: 8),
        _statPill(
          'S',
          fromV.south,
          toV.south,
          bonus: toBonus?.south ?? 0,
          bonusLoss: (fromBonus?.south ?? 0) - (toBonus?.south ?? 0),
        ),
        const SizedBox(width: 8),
        _statPill(
          'E',
          fromV.east,
          toV.east,
          bonus: toBonus?.east ?? 0,
          bonusLoss: (fromBonus?.east ?? 0) - (toBonus?.east ?? 0),
        ),
        const SizedBox(width: 8),
        _statPill(
          'W',
          fromV.west,
          toV.west,
          bonus: toBonus?.west ?? 0,
          bonusLoss: (fromBonus?.west ?? 0) - (toBonus?.west ?? 0),
        ),
      ],
    );
  }

  Widget _statPill(
    String label,
    int oldVal,
    int newVal, {
    int bonus = 0,
    int bonusLoss = 0,
  }) {
    final improved = newVal > oldVal;
    final lostBonus = bonusLoss > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: improved
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: improved
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$newVal',
            style: TextStyle(
              color: improved ? Colors.greenAccent : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (lostBonus)
            Text(
              '-$bonusLoss Bonus',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (bonus > 0)
            Text(
              '+$bonus Bonus',
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

// ── "Tap to continue" hint — blinks to invite the dismiss tap ──

class _TapToContinueHint extends StatefulWidget {
  @override
  State<_TapToContinueHint> createState() => _TapToContinueHintState();
}

class _TapToContinueHintState extends State<_TapToContinueHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(
        begin: 0.3,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: const Text(
        'Tap to continue',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ── Sparkle particle — orbits the sprite box it's drawn inside ──

class _Sparkle {
  _Sparkle({
    required this.angle,
    required this.radiusFactor,
    required this.size,
    required this.opacity,
    required this.duration,
  });

  /// [index]/[count] spaces sparkles evenly around the ring, with jitter,
  /// so they read as "surrounding" the sprite rather than scattered.
  factory _Sparkle.random(Random rng, int index, int count) {
    final baseAngle = (index / count) * 2 * pi;
    return _Sparkle(
      angle: baseAngle + (rng.nextDouble() - 0.5) * (pi / count),
      radiusFactor: 0.62 + rng.nextDouble() * 0.3,
      size: 3.0 + rng.nextDouble() * 5,
      opacity: 0.5 + rng.nextDouble() * 0.5,
      duration: Duration(milliseconds: 350 + rng.nextInt(400)),
    );
  }

  final double angle, radiusFactor, size, opacity;
  final Duration duration;

  Widget buildWidget() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      builder: (_, val, __) {
        if (val == 0) return const SizedBox.shrink();
        final alpha = opacity * (1 - val);
        final dx = cos(angle) * radiusFactor;
        final dy = sin(angle) * radiusFactor;
        return Align(
          alignment: Alignment(dx, dy),
          child: IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: alpha),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: alpha * 0.6),
                    blurRadius: size * 2,
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
