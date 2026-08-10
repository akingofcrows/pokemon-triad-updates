import 'dart:math' show min, sin, pi;
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
  Image? ownerFrame,
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
  // Type effectiveness indicators: +2 = super effective (green), -2 = weak (red), -999 = immune
  int typeBonusNorth = 0,
  int typeBonusSouth = 0,
  int typeBonusEast = 0,
  int typeBonusWest = 0,
  // Condition battle-effect penalty (pokemon_triad_condition_system.md §3):
  // how much to subtract from each side's displayed value; nonzero also
  // draws that number tinted red (kNumberTintDebuffed).
  int conditionPenaltyNorth = 0,
  int conditionPenaltySouth = 0,
  int conditionPenaltyEast = 0,
  int conditionPenaltyWest = 0,
  bool hideArtwork = false,
  Offset? holoTilt,
  bool reverseHolo = false,
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

  // Regular holo: rainbow shimmer sweeping across card background
  final isReverse = reverseHolo || card.reverseHolo;
  if (card.holo && !isReverse) {
    final tiltX = holoTilt?.dx ?? 0;
    final tiltY = holoTilt?.dy ?? 0;
    final sweepPos = (tick * 18 + tiltX * size.width * 2) % (size.width + size.height * 2);
    final bandW = size.width * 0.22;
    final shimmerColors = _rainbowColors((tick + (tiltX * 20).round()) % 120);
    canvas.drawRect(rect, Paint()..shader = Gradient.linear(
      Offset(sweepPos - bandW, 0 - tiltY * size.height * 0.3),
      Offset(sweepPos + bandW, size.height + tiltY * size.height * 0.3),
      shimmerColors, _rainbowStops,
    )..blendMode = BlendMode.plus);
  }

  // Shiny: diamond bg + diagonal shimmer sweep (like Mint effect)
  if (isShiny) {
    _drawDiamondBg(canvas, rect, tick);
    // Sweep: off-card top-left → bottom-right → bounce back
    final bandW = size.width * 0.30;
    final total = size.width + size.height + bandW;
    final raw = (tick * 6) % (total * 2);
    final sweepPos = raw > total ? total * 2 - raw : raw;
    // Start off-card top-left
    final startX = -bandW;
    canvas.drawRect(rect, Paint()..shader = Gradient.linear(
      Offset(startX + sweepPos, 0),
      Offset(startX + sweepPos + bandW * 2, size.height),
      [const Color(0x00FFFFFF), const Color(0x20FFFFFF), const Color(0x38FFFFFF), const Color(0x20FFFFFF), const Color(0x00FFFFFF)],
      [0.0, 0.25, 0.5, 0.75, 1.0],
    )..blendMode = BlendMode.plus);
  }

  // Artwork — skipped when hideArtwork=true (pokéball absorb animation)
  if (artwork != null && !hideArtwork) {
    final artSize = min(artwork.width.toDouble(), artwork.height.toDouble());
    final srcRect = Rect.fromCenter(
      center: Offset(artwork.width / 2, artwork.height / 2),
      width: artSize,
      height: artSize,
    );
    if (isReverse) {
      canvas.drawImageRect(artwork, srcRect, Offset(3, 3) & rect.size, _shadowPaint);
    }
    if (card.holo && isReverse) {
      final tiltX = holoTilt?.dx ?? 0;
      final tiltY = holoTilt?.dy ?? 0;
      final sweepPos = (tick * 18 + tiltX * size.width * 2) % (size.width + size.height * 2);
      final bandW = size.width * 0.22;
      final shimmerColors = _rainbowColors((tick + (tiltX * 20).round()) % 120);
      canvas.saveLayer(rect, Paint());
      canvas.drawImageRect(artwork, srcRect, rect, Paint());
      canvas.drawRect(rect, Paint()..shader = Gradient.linear(
        Offset(sweepPos - bandW, 0 - tiltY * size.height * 0.3),
        Offset(sweepPos + bandW, size.height + tiltY * size.height * 0.3),
        shimmerColors, _rainbowStops,
      )..blendMode = BlendMode.srcATop);
      canvas.restore();
    } else {
      canvas.drawImageRect(artwork, srcRect, rect, Paint());
    }
  }

  canvas.restore();

  // Shiny sparkles — clipped to card area so they don't bleed under other cards
  if (isShiny && !hideArtwork) {
    canvas.save();
    canvas.clipRect(rect.inflate(size.width * 0.08));
    _drawDiamondSparkles(canvas, rect, tick);
    canvas.restore();
  }

  // Numbers
  if (numbers != null) {
    final dx = 7 * scale, dy = 7 * scale, off = 12 * scale, gs = kNumberCellSize * scale;
    void drawNum(int value, double x, double y, {int tintRow = kNumberTintDefault}) {
      final dst = Rect.fromLTWH(x, y, gs, gs);
      _drawImageWithShadow(canvas, numbers, numberSourceRect(value, tintRow: tintRow), dst, drawShadow: drawNumberShadow);
    }
    drawNum(card.values.north + bonusNorth + typeBonusNorth - conditionPenaltyNorth, dx + off, dy,
        tintRow: conditionPenaltyNorth > 0 ? kNumberTintDebuffed : kNumberTintDefault);
    drawNum(card.values.west + bonusWest + typeBonusWest - conditionPenaltyWest, dx, dy + off,
        tintRow: conditionPenaltyWest > 0 ? kNumberTintDebuffed : kNumberTintDefault);
    drawNum(card.values.east + bonusEast + typeBonusEast - conditionPenaltyEast, dx + off * 2, dy + off,
        tintRow: conditionPenaltyEast > 0 ? kNumberTintDebuffed : kNumberTintDefault);
    drawNum(card.values.south + bonusSouth + typeBonusSouth - conditionPenaltySouth, dx + off, dy + off * 2,
        tintRow: conditionPenaltySouth > 0 ? kNumberTintDebuffed : kNumberTintDefault);
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
    if (card.holo && isReverse) {
      final tiltX = holoTilt?.dx ?? 0;
      final tiltY = holoTilt?.dy ?? 0;
      final sweepPos = (tick * 18 + tiltX * size.width * 2) % (size.width + size.height * 2);
      final bandW = size.width * 0.22;
      final shimmerColors = _rainbowColors((tick + (tiltX * 20).round()) % 120);
      canvas.saveLayer(rect, Paint());
      canvas.drawImageRect(
        rarityFrame,
        Rect.fromLTWH(0, 0, rarityFrame.width.toDouble(), rarityFrame.height.toDouble()),
        rect,
        Paint(),
      );
      canvas.drawRect(rect, Paint()..shader = Gradient.linear(
        Offset(sweepPos - bandW, 0 - tiltY * size.height * 0.3),
        Offset(sweepPos + bandW, size.height + tiltY * size.height * 0.3),
        shimmerColors, _rainbowStops,
      )..blendMode = BlendMode.srcATop);
      canvas.restore();
    } else {
      canvas.drawImageRect(
        rarityFrame,
        Rect.fromLTWH(0, 0, rarityFrame.width.toDouble(), rarityFrame.height.toDouble()),
        rect,
        Paint(),
      );
    }
  }

  // Owner frame (player/opponent border)
  if (ownerFrame != null) {
    canvas.drawImageRect(
      ownerFrame,
      Rect.fromLTWH(0, 0, ownerFrame.width.toDouble(), ownerFrame.height.toDouble()),
      rect,
      Paint(),
    );
  }

  // Pop sparkles above the frame — clipped with margin
  if (isShiny && !hideArtwork) {
    canvas.save();
    canvas.clipRect(rect.inflate(size.width * 0.12));
    _drawPopSparkles(canvas, rect, tick);
    canvas.restore();
  }
}

/// Six semi-transparent rainbow colors cycling with [tick].
List<Color> _rainbowColors(int tick) {
  final hue = (tick * 3) % 360;
  return List.generate(6, (i) => _hslToColor((hue + i * 60) % 360, 0.8, 0.55, 0.40));
}

List<double> get _rainbowStops => const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

/// Convert HSL to a [Color] with alpha.
Color _hslToColor(double h, double s, double l, double a) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  double r, g, b;
  if (h < 60) { r = c; g = x; b = 0; }
  else if (h < 120) { r = x; g = c; b = 0; }
  else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; }
  else if (h < 300) { r = x; g = 0; b = c; }
  else { r = c; g = 0; b = x; }
  return Color.fromARGB((a * 255).round(), ((r + m) * 255).round(), ((g + m) * 255).round(), ((b + m) * 255).round());
}

/// Subtle diamond pattern on card background for shiny cards — static
/// scattered diamonds with gentle shimmer.
void _drawDiamondBg(Canvas canvas, Rect rect, int tick) {
  final paint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 40; i++) {
    final px = rect.left + rect.width * _pseudoRand(i * 11 + 3);
    final py = rect.top + rect.height * _pseudoRand(i * 17 + 7);
    final size = 1.5 + _pseudoRand(i * 23 + 1) * 4.0;
    // Shimmer: 0.06–0.20 opacity
    final shimmer = 0.06 + (sin((tick * 0.03 + i * 0.9) % (pi * 2)) * 0.5 + 0.5) * 0.14;
    paint.color = const Color(0xFFFFFFFF).withAlpha((shimmer * 255).round());
    final path = Path()
      ..moveTo(px, py - size)
      ..lineTo(px + size * 0.45, py)
      ..lineTo(px, py + size)
      ..lineTo(px - size * 0.45, py)
      ..close();
    canvas.drawPath(path, paint);
  }
}

/// Draws white diamond sparkles randomly across the card — brief bright
/// flashes at random positions, sizes, and intervals.
void _drawDiamondSparkles(Canvas canvas, Rect rect, int tick) {
  final paint = Paint()..style = PaintingStyle.fill;

  for (var i = 0; i < 24; i++) {
    // Faster flash cycles: 6–24 ticks
    final period = 6 + ((i * 31 + 7) % 19);
    final t = ((tick + i * 17) % period) / period;

    // Brief bright flash, mostly invisible
    final alpha = t < 0.1
        ? (t / 0.1)                      // quick fade in
        : (1.0 - t) / 0.9;               // fade out
    if (alpha <= 0.02) continue;

    // Random position — changes each cycle via tick-dependent seed
    final si = tick ~/ period + i;
    final px = rect.left + rect.width * _pseudoRand(si * 7 + 1);
    final py = rect.top + rect.height * _pseudoRand(si * 13 + 3);

    // Size: 1–6px
    final size = 1.0 + _pseudoRand(si * 17 + 5) * 5.0;

    paint.color = const Color(0xFFFFFFFF).withAlpha((alpha * 255).round());

    final path = Path()
      ..moveTo(px, py - size)
      ..lineTo(px + size * 0.5, py)
      ..lineTo(px, py + size)
      ..lineTo(px - size * 0.5, py)
      ..close();
    canvas.drawPath(path, paint);

    // Bright core
    if (alpha > 0.5 && size > 2) {
      paint.color = const Color(0xFFFFFFFF).withAlpha(((alpha - 0.2) * 160).round());
      final inner = Path()
        ..moveTo(px, py - size * 0.22)
        ..lineTo(px + size * 0.16, py)
        ..lineTo(px, py + size * 0.22)
        ..lineTo(px - size * 0.16, py)
        ..close();
      canvas.drawPath(inner, paint);
    }
  }
}

/// Occasional 3D pop sparkles — float above the frame with drop shadows.
void _drawPopSparkles(Canvas canvas, Rect rect, int tick) {
  final paint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 5; i++) {
    final period = 80 + ((i * 43 + 11) % 70);
    final t = ((tick + i * 29) % period) / period;
    if (t > 0.15) continue;

    final alpha = (t / 0.08).clamp(0.0, 1.0);
    final si = tick ~/ period + i;

    final px = rect.left + rect.width * (_pseudoRand(si * 7 + 2) * 0.8 + 0.1);
    final py = rect.top + rect.height * _pseudoRand(si * 11 + 4);
    final ox = (px < rect.center.dx ? -6.0 : 6.0) + _pseudoRand(si * 13) * 8;
    final oy = (py < rect.center.dy ? -6.0 : 6.0) + _pseudoRand(si * 17) * 8;
    final popX = px + ox;
    final popY = py + oy;

    final size = 4.0 + _pseudoRand(si * 19 + 3) * 6.0;

    // Drop shadow
    paint.color = const Color(0x60000000);
    final shadowPath = Path()
      ..moveTo(popX + 2, popY - size + 2)
      ..lineTo(popX + size * 0.5 + 2, popY + 2)
      ..lineTo(popX + 2, popY + size + 2)
      ..lineTo(popX - size * 0.5 + 2, popY + 2)
      ..close();
    canvas.drawPath(shadowPath, paint);

    // Bright diamond
    paint.color = const Color(0xFFFFFFFF).withAlpha((alpha * 255).round());
    final path = Path()
      ..moveTo(popX, popY - size)
      ..lineTo(popX + size * 0.5, popY)
      ..lineTo(popX, popY + size)
      ..lineTo(popX - size * 0.5, popY)
      ..close();
    canvas.drawPath(path, paint);

    if (alpha > 0.4) {
      paint.color = const Color(0xFFFFFFFF).withAlpha((alpha * 220).round());
      final inner = Path()
        ..moveTo(popX, popY - size * 0.2)
        ..lineTo(popX + size * 0.15, popY)
        ..lineTo(popX, popY + size * 0.2)
        ..lineTo(popX - size * 0.15, popY)
        ..close();
      canvas.drawPath(inner, paint);
    }
  }
}

/// Simple pseudo-random float in [0, 1) from an integer seed.
double _pseudoRand(int seed) {
  final n = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
  return n / 0x7FFFFFFF;
}
