import 'dart:math' show min;
import 'dart:ui';

import '../../models/card_owner.dart';
import '../../models/triad_card.dart';

/// Visual constants shared by the Flutter-side card painter (Collection /
/// Deck Builder) and the Flame-side card component (battle board), so both
/// render cards with the exact same look using TTMMO's original art.

/// Column order baked into TTMMO's `card_bg.png` spritesheet (2304x128 =
/// 18 cells of 128x128, one per Pokémon type). This order is fixed by the
/// art itself and must not be changed.
const Map<String, int> kAffinityBgIndex = {
  'normal': 0,
  'neutral': 0,
  'fighting': 1,
  'rock': 2,
  'fire': 3,
  'water': 4,
  'grass': 5,
  'electric': 6,
  'psychic': 7,
  'dark': 8,
  'dragon': 9,
  'steel': 10,
  'flying': 11,
  'poison': 12,
  'ground': 13,
  'bug': 14,
  'ice': 15,
  'ghost': 16,
  'fairy': 17,
};

const double kCardBgCellSize = 128;
const double kNumberCellSize = 16;

/// A hand card renders at this fraction of the current board cell size —
/// see `BoardLayout`, which recomputes actual pixel sizes for whatever the
/// device's current canvas size/orientation is (landscape or portrait).
const double kHandRestScale = 0.82;

/// Extra scale multiplier applied on top of a card's normal size when
/// selected (GDD §10: "enlarge slightly").
const double kSelectedScaleBoost = 1.18;

/// numbers.png row tint: 0 = default/white, 1 = buffed/green, 2 = debuffed/red.
const int kNumberTintDefault = 0;
const int kNumberTintBuffed = 1;
const int kNumberTintDebuffed = 2;

const Map<CardRarity, Color> kRarityColors = {
  CardRarity.common: Color(0xFF888888),
  CardRarity.uncommon: Color(0xFF4CAF50),
  CardRarity.rare: Color(0xFF2196F3),
  CardRarity.epic: Color(0xFF9C27B0),
  CardRarity.legendary: Color(0xFFFFB300),
};

const Color kPlayerOwnerColor = Color(0xFF2196F3);
const Color kOpponentOwnerColor = Color(0xFFF44336);
const Color kNeutralOwnerColor = Color(0xFF9E9E9E);

const String kCardBgAsset = 'assets/ui/card_bg.png';
const String kEliteBgAsset = 'assets/ui/elite.png';
const String kGymLeaderBgAsset = 'assets/ui/gym_leader.png';
const String kTrainerBgAsset = 'assets/ui/trainerbg.png';
const String kOakBgAsset = 'assets/ui/oakbg.png';
const String kNumbersAsset = 'assets/ui/numbers.png';

/// Elite 4 and Champion trainer card IDs.
const _elite4CardIds = {
  'trainer_lance',
  'trainer_lorelei',
  'trainer_bruno',
  'trainer_agatha',
  'trainer_champion',
};

/// Gym Leader trainer card IDs.
const _gymLeaderCardIds = {
  'trainer_brock',
  'trainer_misty',
  'trainer_surge',
  'trainer_erika',
  'trainer_koga',
  'trainer_sabrina',
  'trainer_blaine',
  'trainer_giovanni',
};

/// Returns the custom background asset for a trainer card, or null if the
/// card should use the standard type-based background.
String? trainerBgAsset(String cardId) {
  if (_elite4CardIds.contains(cardId)) return kEliteBgAsset;
  if (_gymLeaderCardIds.contains(cardId)) return kGymLeaderBgAsset;
  if (cardId == 'trainer_oak') return kOakBgAsset;
  if (cardId.startsWith('trainer_')) return kTrainerBgAsset;
  return null;
}

/// Returns true if [cardId] belongs to an Elite 4 / Champion trainer card.
bool isEliteCard(String cardId) => _elite4CardIds.contains(cardId);

Color ownerBorderColor(CardOwner owner) {
  switch (owner) {
    case CardOwner.player:
      return kPlayerOwnerColor;
    case CardOwner.opponent:
      return kOpponentOwnerColor;
    case CardOwner.neutral:
      return kNeutralOwnerColor;
  }
}

/// Source rect within card_bg.png for a given Pokémon type.
Rect cardBgSourceRect(String affinity) {
  final index = kAffinityBgIndex[affinity] ?? 0;
  return Rect.fromLTWH(index * kCardBgCellSize, 0, kCardBgCellSize, kCardBgCellSize);
}

/// Source rect within numbers.png for a given directional value (0-10) and tint row.
Rect numberSourceRect(int value, {int tintRow = kNumberTintDefault}) {
  final col = value.clamp(0, 10);
  return Rect.fromLTWH(
    col * kNumberCellSize,
    tintRow * kNumberCellSize,
    kNumberCellSize,
    kNumberCellSize,
  );
}

String typeIconAsset(String affinity) => 'assets/ui/types/$affinity.png';

/// Flame's [Images] cache is configured with prefix `'assets/'` (see
/// `TriadGame`), so it keys/loads images without that leading segment while
/// every other asset path in this app (rootBundle, Flutter `Image.asset`)
/// keeps the full `assets/...` path. This strips it for Flame call sites.
String flameImageKey(String assetPath) {
  return assetPath.startsWith('assets/') ? assetPath.substring('assets/'.length) : assetPath;
}

String rarityFrameAsset(CardRarity rarity) {
  switch (rarity) {
    case CardRarity.common:
      return 'assets/ui/frame.png';
    case CardRarity.uncommon:
      return 'assets/ui/frameU.png';
    case CardRarity.rare:
      return 'assets/ui/frameR.png';
    case CardRarity.epic:
      return 'assets/ui/frameE.png';
    case CardRarity.legendary:
      return 'assets/ui/frameL.png';
  }
}

const String kHoloFrameAsset = 'assets/ui/holoframe.png';
const String kShinyFrameAsset = 'assets/ui/shinyframe.png';
const String kShinyBgAsset = 'assets/ui/shinyframe.png';
const String kSparkleAsset = 'assets/ui/sparkle.png';

/// Returns the frame asset for a card taking holo / shiny into account.
/// [isShiny] overrides the template's [TriadCard.shiny] — use this when the
/// shiny flag comes from instance growth data rather than the card template.
String cardFrameAsset(TriadCard card, {bool isShiny = false}) {
  if (isShiny || card.shiny) return kShinyFrameAsset;
  if (card.holo) return kHoloFrameAsset;
  return rarityFrameAsset(card.rarity);
}

/// Dropshadow paint used for number / type-icon legibility.
final _shadowPaint = Paint()
  ..colorFilter = const ColorFilter.mode(Color(0xFF404040), BlendMode.srcIn);

/// Draws a sub-region of [image] at [dst], optionally with a dropshadow.
void _drawImageWithShadow(Canvas canvas, Image image, Rect src, Rect dst, {bool drawShadow = true, double shadowDx = 2, double shadowDy = 2}) {
  if (drawShadow) {
    final dstShadow = dst.translate(shadowDx, shadowDy);
    canvas.drawImageRect(image, src, dstShadow, _shadowPaint);
  }
  canvas.drawImageRect(image, src, dst, Paint());
}

/// Draws one Triple Triad card face onto [canvas] within [size] — the single
/// shared implementation used by both the Flutter-side painter
/// (`widgets/triad_card_view.dart`, for Collection/Deck Builder) and the
/// Flame-side component (`game/cards/card_component.dart`, for the battle
/// board), so a card looks identical in both places. `dart:ui`'s `Canvas` is
/// the same type both Flutter's `CustomPainter.paint` and Flame's
/// `Component.render` hand you, so this needs no framework glue.
void paintTriadCardFace(
  Canvas canvas,
  Size size, {
  required TriadCard card,
  Image? cardBg,
  Image? eliteBg,
  Image? numbers,
  Image? artwork,
  Image? typeIcon,
  Image? rarityFrame,
  Image? shinyBg,
  Image? holoImage,
  Image? sparkleImage,
  int tick = 0,
  bool drawNumberShadow = true,
  bool drawColoredBorder = true,
  Color borderColor = kNeutralOwnerColor,
  double borderWidth = 2.5,
  CardOwner? owner,
  bool isShiny = false,
  int bonusNorth = 0,
  int bonusSouth = 0,
  int bonusEast = 0,
  int bonusWest = 0,
}) {
  final rect = Offset.zero & size;
  final scale = size.width / kCardBgCellSize;
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.08));

  canvas.save();
  canvas.clipRRect(rrect);

  // Trainer cards may use a custom background (elite, gym leader, etc.)
  final customBg = trainerBgAsset(card.id);
  final trainerBgImage = customBg != null ? eliteBg : null;
  // Note: eliteBg is reused as a generic "trainer background" slot here

  if (trainerBgImage != null) {
    canvas.drawImageRect(trainerBgImage, Offset.zero & Size(trainerBgImage.width.toDouble(), trainerBgImage.height.toDouble()), rect, Paint());
  } else if (cardBg != null) {
    canvas.drawImageRect(cardBg, cardBgSourceRect(card.affinity), rect, Paint());
  } else {
    canvas.drawRect(rect, Paint()..color = const Color(0xFF333333));
  }

  // Shiny background: full-bleed sparkle texture behind the artwork.
  if (shinyBg != null) {
    canvas.drawImageRect(shinyBg, Offset.zero & Size(shinyBg.width.toDouble(), shinyBg.height.toDouble()), rect, Paint());
  }

  // TTMMO owner-colour wash.
  if (owner != null && owner != CardOwner.neutral) {
    canvas.drawRect(
      rect,
      Paint()..color = owner == CardOwner.player
          ? const Color(0x4D2196F3)
          : const Color(0x59DC3228),
    );
  }

  // Regular holo: below artwork
  if (holoImage != null && card.holo && !card.reverseHolo) {
    final offset = (tick * 14) % holoImage.width;
    canvas.drawImageRect(holoImage,
      Rect.fromLTWH(offset.toDouble(), 0, size.width, holoImage.height.toDouble()),
      rect, Paint()..color = const Color(0x44FFFFFF)..blendMode = BlendMode.srcOver);
  }

  // Artwork
  if (artwork != null) {
    final artSize = min(artwork.width.toDouble(), artwork.height.toDouble());
    final srcRect = Rect.fromCenter(
      center: Offset(artwork.width / 2, artwork.height / 2),
      width: artSize,
      height: artSize,
    );
    if (card.reverseHolo) {
      // Dropshadow for reverse holo artwork
      final sdDst = const Offset(2, 2) & size;
      canvas.drawImageRect(artwork, srcRect, sdDst, _shadowPaint);
    }
    if (holoImage != null && card.holo && card.reverseHolo) {
      // Reverse holo: shimmer masked to artwork silhouette
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawImageRect(artwork, srcRect, rect, Paint());
      final offset = (tick * 14) % holoImage.width;
      canvas.drawImageRect(holoImage,
        Rect.fromLTWH(offset.toDouble(), 0, size.width, holoImage.height.toDouble()),
        rect, Paint()..color = const Color(0x33FFFFFF)..blendMode = BlendMode.srcATop);
      canvas.restore();
    } else {
      canvas.drawImageRect(artwork, srcRect, rect, Paint());
    }
  }

  // Shiny sparkle overlay
  if (sparkleImage != null && isShiny) {
    final fw = sparkleImage.width / 20;
    canvas.drawImageRect(sparkleImage,
      Rect.fromLTWH((tick % 20) * fw, 0, fw, sparkleImage.height.toDouble()),
      rect, Paint());
  }

  canvas.restore();

  // Numbers
  if (numbers != null) {
    final dx = 7 * scale, dy = 7 * scale, off = 12 * scale, gs = kNumberCellSize * scale;
    void drawNum(int value, double x, double y) {
      final dst = Rect.fromLTWH(x, y, gs, gs);
      _drawImageWithShadow(canvas, numbers, numberSourceRect(value), dst, drawShadow: drawNumberShadow);
    }
    drawNum(card.values.north + bonusNorth, dx + off, dy);
    drawNum(card.values.west + bonusWest, dx, dy + off);
    drawNum(card.values.east + bonusEast, dx + off * 2, dy + off);
    drawNum(card.values.south + bonusSouth, dx + off, dy + off * 2);
  }

  // Type icon
  if (typeIcon != null) {
    final boxW = 22 * scale, boxH = 36 * scale;
    final boxX = size.width - boxW - 7 * scale, boxY = 7 * scale;
    final aspect = typeIcon.width / typeIcon.height;
    double dw = boxW, dh = boxH;
    if (boxW / boxH > aspect) {
      dw = boxH * aspect;
    } else {
      dh = boxW / aspect;
    }
    final dx = boxX + (boxW - dw) / 2, dy = boxY + (boxH - dh) / 2;
    final typeSrc = Rect.fromLTWH(0, 0, typeIcon.width.toDouble(), typeIcon.height.toDouble());
    final typeDst = Rect.fromLTWH(dx, dy, dw, dh);
    _drawImageWithShadow(canvas, typeIcon, typeSrc, typeDst, drawShadow: true);
  }

  // Colored border stroke (optional — not used in collection / title)
  if (drawColoredBorder) {
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..color = borderColor,
    );
  }

  // Frame
  if (rarityFrame != null) {
    canvas.drawImageRect(
      rarityFrame,
      Rect.fromLTWH(0, 0, rarityFrame.width.toDouble(), rarityFrame.height.toDouble()),
      rect,
      Paint(),
    );
  }
}
