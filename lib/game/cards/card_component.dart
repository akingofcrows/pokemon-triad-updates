import 'dart:math' show min, sin;
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../models/card_owner.dart';
import '../../models/condition.dart';
import '../../models/triad_card.dart';
import '../../widgets/card_damage_overlay.dart';
import '../../widgets/condition_badge.dart';
import 'card_visuals.dart';

/// Renders one [TriadCard], whether sitting in a hand or placed on the
/// board. Supports both tap-to-select and drag-to-place (GDD §10) when
/// [interactive] is true. Shares its paint routine (`paintTriadCardFace`)
/// with the Flutter-side Collection/Deck Builder card view.
///
/// [size] holds the card's actual current pixel dimensions (set by whoever
/// lays the board out, and updated live via [resize] on rotation/resize);
/// [scale] is used only for the transient selected/flip effects on top of
/// that, so those effects don't need to know the current layout's units.
class CardComponent extends PositionComponent with TapCallbacks, DragCallbacks {
  CardComponent({
    required TriadCard card,
    required this.images,
    required Vector2 position,
    required double pixelSize,
    this.interactive = false,
    this.onTapped,
    this.onDragStarted,
    this.onDropped,
  }) : _card = card,
       targetPosition = position.clone(),
       targetScale = 1,
       super(
         position: position,
         size: Vector2.all(pixelSize),
         anchor: Anchor.center,
         scale: Vector2.all(1),
       ) {
    _loadSprites();
  }

  final Images images;
  bool interactive;
  bool selected = false;

  /// Where this card should animate toward (its hand slot, or a board cell
  /// center). Ignored while actively being dragged by the pointer.
  Vector2 targetPosition;
  double targetScale;

  void Function(CardComponent card)? onTapped;
  void Function(CardComponent card)? onDragStarted;
  void Function(CardComponent card, Vector2 dropWorldPosition)? onDropped;
  /// Called when this card is tapped in targeting mode.
  void Function(CardComponent card)? onTargeted;

  TriadCard _card;
  TriadCard get card => _card;

  bool _dragging = false;

  Image? _cardBg;
  Image? _eliteBg;
  Image? _numbers;
  Image? _artwork;
  Image? get artworkImage => _artwork;  // exposed for pokéball animation
  Image? _typeIcon;
  Image? _rarityFrame;
  Image? _ownerFrame;
  Image? _shinyBg;
  Image? _sparkleImage;
  double _sparkleTime = 0;
  int get _tick => (_sparkleTime / 0.06).floor();

  /// Capture flip: a brief horizontal squash-to-zero-and-back, swapping the
  /// displayed owner/artwork at the midpoint (when the card is edge-on and
  /// nothing is visible), like a real card flip.
  static const double _flipDuration = 0.5;
  bool _flipping = false;
  bool _flipSwapped = false;
  double _flipTimer = 0;
  double _flipScaleX = 1;
  TriadCard? _pendingCard;

  /// When true, the card was captured via pokéball — renders dark/greyed and
  /// cannot be flipped again in battle.
  bool pokeballCaptured = false;

  /// When > 0, the artwork sprite is hidden (used during pokéball animation).
  /// 0 = fully visible, 1 = fully hidden.
  double _spriteHide = 0;
  double get spriteHide => _spriteHide;
  set spriteHide(double v) => _spriteHide = v.clamp(0.0, 1.0);

  /// Glow intensity for the card during pokéball capture animation.
  double _glowAmount = 0;
  double get glowAmount => _glowAmount;
  set glowAmount(double v) => _glowAmount = v.clamp(0.0, 1.0);

  void _loadSprites() {
    _cardBg = images.fromCache(flameImageKey(kCardBgAsset));
    final trainerBg = trainerBgAsset(_card.id);
    if (trainerBg != null) {
      _eliteBg = images.fromCache(flameImageKey(trainerBg));
    }
    _numbers = images.fromCache(flameImageKey(kNumbersAsset));
    final artPath = _card.shiny
        ? _card.image.replaceFirst('assets/pokemon/', 'assets/pokemon_shiny/')
        : _card.image;
    _artwork = images.fromCache(flameImageKey(artPath));
    _typeIcon = images.fromCache(flameImageKey(typeIconAsset(_card.affinity)));
    _rarityFrame = images.fromCache(flameImageKey(cardFrameAsset(_card)));
    _ownerFrame = _card.owner == CardOwner.player
        ? images.fromCache(flameImageKey('ui/playerframe.png'))
        : _card.owner == CardOwner.opponent
            ? images.fromCache(flameImageKey('ui/opponentframe.png'))
            : null;
    if (_card.shiny) {
      _shinyBg = images.fromCache(flameImageKey(kShinyBgAsset));
      _sparkleImage = images.fromCache(flameImageKey(kSparkleAsset));
    }
  }

  void _applyCard(TriadCard newCard) {
    final oldCard = _card;
    final artworkChanged = newCard.image != oldCard.image;
    final frameChanged = newCard.rarity != oldCard.rarity ||
        newCard.holo != oldCard.holo;
    final eliteChanged = trainerBgAsset(newCard.id) != trainerBgAsset(oldCard.id);
    _card = newCard;
    final shinyChanged = newCard.shiny != oldCard.shiny;
    if (artworkChanged || shinyChanged) {
      final artPath = newCard.shiny
          ? newCard.image.replaceFirst('assets/pokemon/', 'assets/pokemon_shiny/')
          : newCard.image;
      _artwork = images.fromCache(flameImageKey(artPath));
    }
    if (frameChanged || shinyChanged) {
      _rarityFrame = images.fromCache(flameImageKey(cardFrameAsset(newCard)));
      _shinyBg = newCard.shiny
          ? images.fromCache(flameImageKey(kShinyBgAsset))
          : null;
      _sparkleImage = newCard.shiny
          ? images.fromCache(flameImageKey(kSparkleAsset))
          : null;
    }
    if (newCard.owner != oldCard.owner) {
      _ownerFrame = newCard.owner == CardOwner.player
          ? images.fromCache(flameImageKey('ui/playerframe.png'))
          : newCard.owner == CardOwner.opponent
              ? images.fromCache(flameImageKey('ui/opponentframe.png'))
              : null;
    }
    if (eliteChanged) {
      final tb = trainerBgAsset(newCard.id);
      _eliteBg = tb != null ? images.fromCache(flameImageKey(tb)) : null;
    }
  }

  /// Plays a reveal flip: squash-to-zero and back, revealing the card face
  /// (used when the opponent plays a card from their hand).
  void reveal() {
    _flipScaleX = 0;
    _flipTimer = 0;
    _flipping = true;
    _flipSwapped = false;
    _pendingCard = null;
  }

  /// Updates the displayed card. If [newCard] changes owner (a capture),
  /// plays a flip animation and swaps the visuals at its midpoint instead of
  /// changing them instantly.
  void setCard(TriadCard newCard) {
    if (newCard.owner == _card.owner) {
      _applyCard(newCard);
      return;
    }
    _pendingCard = newCard;
    _flipping = true;
    _flipSwapped = false;
    _flipTimer = 0;
  }

  void moveTo(Vector2 worldPosition) {
    targetPosition = worldPosition;
  }

  /// Updates this card's true pixel dimensions — called when the board's
  /// layout changes (e.g. a device rotation between landscape/portrait).
  void resize(double pixelSize) {
    size.setValues(pixelSize, pixelSize);
  }

  void setSelected(bool value) {
    selected = value;
    targetScale = value ? kSelectedScaleBoost : 1.0;
  }

  /// When true, the card pulses with a highlight border to indicate it can
  /// be targeted by an item (pokéball).
  bool _targetable = false;
  double _targetablePulse = 0;

  void setTargetable(bool value) {
    _targetable = value;
    _targetablePulse = 0;
  }

  bool get isTargetable => _targetable;

  @override
  void update(double dt) {
    super.update(dt);
    _sparkleTime += dt;
    _targetablePulse += dt;
    final t = min(1.0, dt * 14);
    if (!_dragging) {
      position.setFrom(position + (targetPosition - position) * t);
    }
    final newScale = scale.y + (targetScale - scale.y) * t;

    if (_flipping) {
      _flipTimer += dt;
      final flipT = (_flipTimer / _flipDuration).clamp(0.0, 1.0);
      if (!_flipSwapped && flipT >= 0.5 && _pendingCard != null) {
        _applyCard(_pendingCard!);
        _pendingCard = null;
        _flipSwapped = true;
      }
      _flipScaleX = (2 * flipT - 1).abs();
      if (flipT >= 1.0) {
        _flipping = false;
        _flipScaleX = 1;
      }
    } else {
      _flipScaleX = 1;
    }

    scale.setValues(newScale * _flipScaleX, newScale);
  }

  @override
  void render(Canvas canvas) {
    final cardSize = Size(size.x, size.y);
    final tier = tierForCondition(_card.condition);
    final desaturation = desaturationForTier(tier);
    final seed = stableCardSeed(_card.id, null);
    final scratchCount = scratchCountForTier(tier, seed);
    final (tearCount, burnCount) = damageHoleCountsForTier(tier, seed);
    final wear = (kMaxCondition - _card.condition) / kMaxCondition;
    final holes = (tearCount > 0 || burnCount > 0)
        ? computeDamageHoles(size: cardSize, seed: seed, tearCount: tearCount, burnCount: burnCount, wear: wear)
        : const <TornHole>[];

    final isUnusable = tier == ConditionTier.unusable;
    // Same dimming TriadCardView applies (Collection/Deck Builder): a
    // worn-out card doesn't just desaturate, it looks a little washed out.
    final layerOpacity = isUnusable ? 0.5 : (tier == ConditionTier.heavilyPlayed ? 0.8 : 1.0);

    canvas.save();
    if (holes.isNotEmpty) {
      canvas.clipPath(buildCardFaceClipPath(cardSize, holes));
    }
    if (desaturation > 0 || layerOpacity < 1.0) {
      canvas.saveLayer(
        Offset.zero & cardSize,
        Paint()
          ..colorFilter = ColorFilter.matrix(desaturationMatrix(desaturation))
          ..color = const Color(0xFFFFFFFF).withValues(alpha: layerOpacity),
      );
    }
    paintTriadCardFace(
      canvas,
      cardSize,
      card: _card,
      cardBg: _cardBg,
      eliteBg: _eliteBg,
      numbers: _numbers,
      artwork: _artwork,
      typeIcon: _typeIcon,
      rarityFrame: _rarityFrame,
      ownerFrame: _ownerFrame,
      shinyBg: _shinyBg,
      sparkleImage: _sparkleImage,
      tick: _tick,
      borderColor: ownerBorderColor(_card.owner),
      borderWidth: size.x * (selected ? 0.05 : 0.03),
      drawColoredBorder: false,
      owner: _card.owner,
      isShiny: _card.shiny,
      drawNumberShadow: false,
      bonusNorth: 0,
      bonusSouth: 0,
      bonusEast: 0,
      bonusWest: 0,
      typeBonusNorth: 0,
      typeBonusSouth: 0,
      typeBonusEast: 0,
      typeBonusWest: 0,
      conditionPenaltyNorth: _card.conditionPenaltyNorth,
      conditionPenaltySouth: _card.conditionPenaltySouth,
      conditionPenaltyEast: _card.conditionPenaltyEast,
      conditionPenaltyWest: _card.conditionPenaltyWest,
      hideArtwork: _spriteHide > 0.5,
    );
    if (desaturation > 0 || layerOpacity < 1.0) {
      canvas.restore(); // pop the desaturation/dimming saveLayer
    }
    canvas.restore(); // pop the hole clip

    // Damage overlay (GDD §24) — scratches confined to the art/background
    // window, torn/burned rims framing the holes just cut out of the face
    // above. Drawn on top, same as the Collection/Deck Builder card view.
    if (holes.isNotEmpty) {
      paintFrameDamage(canvas, cardSize, seed: seed, holes: holes, opacity: (0.35 + wear * 0.5).clamp(0.0, 0.85));
    }
    if (scratchCount > 0) {
      final inset = cardSize.width * CardDamageOverlay.frameInset;
      canvas.save();
      canvas.translate(inset, inset);
      paintScratches(
        canvas,
        Size(cardSize.width - inset * 2, cardSize.height - inset * 2),
        seed: seed,
        count: scratchCount,
        opacity: (0.24 + wear * 0.28).clamp(0.0, 0.52),
      );
      canvas.restore();
    }

    // Condition badge / Unusable label / warning icon — same tier gating
    // and corner positions as TriadCardView, so a card reads identically
    // whether it's in the Collection grid or sitting on the board.
    if (tier != ConditionTier.mint) {
      if (isUnusable) {
        final fontSize = (cardSize.width * 0.1).clamp(7.0, 11.0);
        paintUnusableLabel(
          canvas,
          Offset(cardSize.width * 0.04, cardSize.height - cardSize.height * 0.04 - fontSize * 1.5),
          cardSize: cardSize.width,
        );
      } else {
        final fontSize = (cardSize.width * 0.11).clamp(8.0, 12.0);
        paintConditionBadge(
          canvas,
          Offset(cardSize.width * 0.04, cardSize.height - cardSize.height * 0.04 - fontSize * 1.5),
          condition: _card.condition,
          fontSize: fontSize,
        );
      }
    }
    if (tier == ConditionTier.worn || tier == ConditionTier.heavilyPlayed) {
      final iconSize = (cardSize.width * 0.18).clamp(12.0, 20.0);
      paintConditionWarningIcon(
        canvas,
        Offset(cardSize.width - cardSize.width * 0.04 - iconSize / 2, cardSize.height * 0.04 + iconSize / 2),
        tier: tier,
        size: iconSize,
      );
    }

    // Glow overlay (pokéball capture animation)
    if (_glowAmount > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.45 * _glowAmount),
      );
    }

    // Sprite fade-out overlay for remaining card elements
    if (_spriteHide > 0) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = const Color(0xFF1A1A1A).withValues(alpha: _spriteHide * 0.3),
      );
    }

    // Pokéball-captured dark overlay
    if (pokeballCaptured) {
      canvas.drawRect(
        Offset.zero & Size(size.x, size.y),
        Paint()..color = const Color(0x88000000),
      );
    }

    // Targetable highlight pulse — draws at card bounds (0,0 to size)
    if (_targetable) {
      final pulse = (0.5 + 0.5 * sin(_targetablePulse * 4)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = const Color(0xFFFFCA28).withValues(alpha: 0.6 + 0.4 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.x * 0.08;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & Size(size.x, size.y), Radius.circular(size.x * 0.06)),
        paint,
      );
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_targetable && onTargeted != null) {
      onTargeted!.call(this);
      return;
    }
    if (!interactive) return;
    onTapped?.call(this);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!interactive) return;
    _dragging = true;
    priority = 1000;
    onDragStarted?.call(this);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (!interactive || !_dragging) return;
    position.add(event.localDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!interactive || !_dragging) return;
    _dragging = false;
    priority = 0;
    onDropped?.call(this, position.clone());
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragging = false;
    priority = 0;
  }
}
