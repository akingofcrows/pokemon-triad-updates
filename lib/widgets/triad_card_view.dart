import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/cards/card_visuals.dart';
import '../game/cards/image_asset_cache.dart';
import '../models/card_growth.dart';
import '../models/triad_card.dart';

/// Flutter-side rendering of a [TriadCard] — used by the Collection and Deck
/// Builder screens. Shares its drawing code (`paintTriadCardFace`) with the
/// Flame battle board (`lib/game/cards/card_component.dart`).
///
/// Holo and shiny effects animate via a periodic tick.
class TriadCardView extends StatefulWidget {
  const TriadCardView({
    super.key,
    required this.card,
    this.size = 100,
    this.showRarityFrame = true,
    this.selected = false,
    this.growth,
  });

  final TriadCard card;
  final double size;
  final bool showRarityFrame;
  final bool selected;
  final CardGrowth? growth;

  /// Whether this instance should render as shiny — uses the player's
  /// growth data if available, otherwise falls back to the card template.
  bool get _isShiny => growth?.shiny == true || card.shiny;

  @override
  State<TriadCardView> createState() => _TriadCardViewState();

  /// Warms [ImageAssetCache] for [card] so a subsequent [TriadCardView]
  /// paints immediately instead of showing a blank/stale frame while its
  /// art decodes — e.g. right before a card-flip reveal.
  static Future<void> preloadAssets(
    TriadCard card, {
    bool shiny = false,
    bool showRarityFrame = true,
  }) {
    final paths = <String>[
      kCardBgAsset,
      kNumbersAsset,
      typeIconAsset(card.affinity),
    ];
    if (card.image.isNotEmpty) {
      paths.add(
        shiny
            ? card.image.replaceFirst(
                'assets/pokemon/',
                'assets/pokemon_shiny/',
              )
            : card.image,
      );
    }
    if (showRarityFrame) {
      paths.add(shiny ? kShinyFrameAsset : cardFrameAsset(card));
    }
    if (card.holo) paths.add('assets/ui/holographic.png');
    if (shiny) {
      paths.add('assets/ui/sparkle.png');
      paths.add(kShinyBgAsset);
    }
    if (isEliteCard(card.id)) {
      paths.add(kEliteBgAsset);
    } else {
      final tb = trainerBgAsset(card.id);
      if (tb != null) paths.add(tb);
    }
    return ImageAssetCache.instance.preload(paths);
  }
}

class _TriadCardViewState extends State<TriadCardView> {
  int _tick = 0;
  Timer? _timer;
  Map<String, ui.Image?> _images = const {};

  bool get _isShiny => widget.growth?.shiny == true || widget.card.shiny;

  @override
  void initState() {
    super.initState();
    _loadImages();
    if (_isShiny || widget.card.holo) _startTicker();
  }

  @override
  void didUpdateWidget(covariant TriadCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasShiny = oldWidget._isShiny;
    if (widget.card != oldWidget.card ||
        widget.showRarityFrame != oldWidget.showRarityFrame ||
        _isShiny != wasShiny) {
      _loadImages();
    }
    final wasAnimated = oldWidget.card.holo || wasShiny;
    final isAnimated = widget.card.holo || _isShiny;
    if (isAnimated && !wasAnimated) {
      _tick = 0;
      _startTicker();
    } else if (!isAnimated && wasAnimated) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() => ++_tick);
    });
  }

  void _loadImages() {
    final card = widget.card;
    final showFrame = widget.showRarityFrame;

    // Load all needed assets in parallel, keyed by role.
    final futures = <String, Future<ui.Image?>>{};
    void add(String key, String path) =>
        futures[key] = ImageAssetCache.instance.load(path);
    if (isEliteCard(card.id)) {
      add('eliteBg', kEliteBgAsset);
      add('bg', kCardBgAsset);
    } else {
      final trainerBg = trainerBgAsset(card.id);
      if (trainerBg != null) {
        add('eliteBg', trainerBg);
        add('bg', kCardBgAsset);
      } else {
        add('bg', kCardBgAsset);
      }
    }
    add('nums', kNumbersAsset);
    if (card.image.isNotEmpty) {
      // Use shiny sprite when the player has a shiny instance
      final artPath = _isShiny
          ? card.image.replaceFirst('assets/pokemon/', 'assets/pokemon_shiny/')
          : card.image;
      add('art', artPath);
    }
    add('type', typeIconAsset(card.affinity));
    if (showFrame) {
      add('frame', _isShiny ? kShinyFrameAsset : cardFrameAsset(card));
    }
    if (card.holo) add('holo', 'assets/ui/holographic.png');
    if (_isShiny) add('sparkle', 'assets/ui/sparkle.png');
    if (_isShiny) add('shinyBg', kShinyBgAsset);

    _resolveAll(futures).then((result) {
      if (mounted) setState(() => _images = result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final im = _images;
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _TriadCardPainter(
        card: widget.card,
        cardBg: im['bg'],
        eliteBg: im['eliteBg'],
        numbers: im['nums'],
        artwork: im['art'],
        typeIcon: im['type'],
        rarityFrame: im['frame'],
        holoImage: im['holo'],
        sparkleImage: im['sparkle'],
        shinyBg: im['shinyBg'],
        tick: _tick,
        selected: widget.selected,
        growth: widget.growth,
      ),
    );
  }

  Future<Map<String, ui.Image?>> _resolveAll(
    Map<String, Future<ui.Image?>> futures,
  ) async {
    final result = <String, ui.Image?>{};
    for (final entry in futures.entries) {
      result[entry.key] = await entry.value;
    }
    return result;
  }
}

class _TriadCardPainter extends CustomPainter {
  _TriadCardPainter({
    required this.card,
    required this.cardBg,
    required this.eliteBg,
    required this.numbers,
    required this.artwork,
    required this.typeIcon,
    required this.rarityFrame,
    required this.holoImage,
    required this.sparkleImage,
    required this.shinyBg,
    required this.tick,
    required this.selected,
    this.growth,
  });

  final TriadCard card;
  final ui.Image? cardBg;
  final ui.Image? eliteBg;
  final ui.Image? numbers;
  final ui.Image? artwork;
  final ui.Image? typeIcon;
  final ui.Image? rarityFrame;
  final ui.Image? holoImage;
  final ui.Image? sparkleImage;
  final ui.Image? shinyBg;
  final int tick;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    paintTriadCardFace(
      canvas,
      size,
      card: card,
      cardBg: cardBg,
      eliteBg: eliteBg,
      numbers: numbers,
      artwork: artwork,
      typeIcon: typeIcon,
      rarityFrame: rarityFrame,
      shinyBg: shinyBg,
      holoImage: holoImage,
      sparkleImage: sparkleImage,
      tick: tick,
      drawNumberShadow: false,
      drawColoredBorder: false,
      isShiny: _isShiny,
      bonusNorth: growth?.bonusNorth ?? 0,
      bonusSouth: growth?.bonusSouth ?? 0,
      bonusEast: growth?.bonusEast ?? 0,
      bonusWest: growth?.bonusWest ?? 0,
    );
  }

  /// Forward the widget's shiny detection to the painter.
  bool get _isShiny => (growth?.shiny == true) || card.shiny;

  final CardGrowth? growth;

  @override
  bool shouldRepaint(covariant _TriadCardPainter oldDelegate) {
    return oldDelegate.card != card ||
        oldDelegate.artwork != artwork ||
        oldDelegate.tick != tick;
  }
}
