import 'dart:math' show min;
import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import '../../models/triad_card.dart';
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

  TriadCard _card;
  TriadCard get card => _card;

  bool _dragging = false;

  Image? _cardBg;
  Image? _eliteBg;
  Image? _numbers;
  Image? _artwork;
  Image? _typeIcon;
  Image? _rarityFrame;
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

  @override
  void update(double dt) {
    super.update(dt);
    _sparkleTime += dt;
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
    paintTriadCardFace(
      canvas,
      Size(size.x, size.y),
      card: _card,
      cardBg: _cardBg,
      eliteBg: _eliteBg,
      numbers: _numbers,
      artwork: _artwork,
      typeIcon: _typeIcon,
      rarityFrame: _rarityFrame,
      shinyBg: _shinyBg,
      sparkleImage: _sparkleImage,
      tick: _tick,
      borderColor: ownerBorderColor(_card.owner),
      borderWidth: size.x * (selected ? 0.05 : 0.03),
      owner: _card.owner,
      isShiny: _card.shiny,
      drawNumberShadow: false,
    );
  }

  @override
  void onTapUp(TapUpEvent event) {
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
