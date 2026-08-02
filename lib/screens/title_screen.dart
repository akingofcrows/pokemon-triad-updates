import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/routes.dart';
import '../game/cards/card_visuals.dart';
import '../game/cards/image_asset_cache.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/update_service.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/update_dialog.dart';

/// Title screen with animated shuffling cards, battery indicator, and version.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  final _rng = Random();
  List<TriadCard> _allCards = [];
  final List<TriadCard> _fanCards = [];
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _allCards = CardRepository.instance.allCards.toList();
    if (_allCards.isEmpty) _allCards = [TriadCard.fallback()];
    for (var i = 0; i < 5; i++) {
      var card = _allCards[_rng.nextInt(_allCards.length)];
      final isTrainer = card.cardType == TriadCardType.trainer;
      final isFinalEvo = card.cardType == TriadCardType.pokemon &&
          (card.evolvesTo == null || card.evolvesTo!.isEmpty) &&
          card.baseLevel != null && card.baseLevel! > 1;
      final holoChance = isTrainer ? 0.30 : isFinalEvo ? 0.25 : 0.08;
      if (_rng.nextDouble() < holoChance) {
        card = card.copyWith(holo: true, reverseHolo: _rng.nextDouble() < 0.3);
      }
      _fanCards.add(card);
    }
    _initImages();
  }

  Future<void> _initImages() async {
    // Run update check in parallel — don't block on image loading
    _checkForUpdates();
    try {
      await _preloadCardImages();
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _checkForUpdates() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      await checkAndShowUpdateDialog(context);
    } catch (_) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        if (mounted) await checkAndShowUpdateDialog(context);
      } catch (_) {}
    }
  }

  Future<void> _preloadCardImages() async {
    final cache = ImageAssetCache.instance;
    final paths = <String>{
      kCardBgAsset,
      kNumbersAsset,
      kShinyBgAsset,
      kHoloFrameAsset,
      kShinyFrameAsset,
      rarityFrameAsset(CardRarity.common),
      rarityFrameAsset(CardRarity.uncommon),
      rarityFrameAsset(CardRarity.rare),
      rarityFrameAsset(CardRarity.epic),
      rarityFrameAsset(CardRarity.legendary),
      'assets/ui/sparkle.png',
      'assets/ui/holographic.png',
    };
    for (final a in kAffinityBgIndex.keys) {
      paths.add(typeIconAsset(a));
    }
    for (final c in _allCards) {
      if (c.image.isNotEmpty) paths.add(c.image);
    }
    // Don't preload shiny sprites — they're loaded on demand, missing ones fall back gracefully
    cache.preload(paths);
  }

  @override
  void dispose() { super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/ui/titlebg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.30), Colors.black.withValues(alpha: 0.50), Colors.black.withValues(alpha: 0.65)],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: !_ready
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFC9A44C)))
              : Stack(
              children: [
                const Positioned(top: 8, left: 12, child: BatteryIndicator()),
                const Positioned(top: 40, left: 0, right: 0, child: _TitleWidget()),
                Positioned(top: 0, left: 0, right: 0, bottom: 240,
                  child: _FanHand(cards: _fanCards, pool: _allCards, onCardChanged: (i, c) => setState(() => _fanCards[i] = c)),
                ),
                const Positioned(left: 0, right: 0, bottom: 52,
                  child: _BottomActions(),
                ),
                const Positioned(bottom: 8, right: 12, child: _VersionWidget()),
              ],
            ),
        ),
      ),
    ));
  }

  static void _showSettings(BuildContext ctx) => showDialog(context: ctx, builder: (_) => const _SettingsDialog());
  static void _showStub(BuildContext ctx, String t) => showDialog(context: ctx, builder: (_) => AlertDialog(title: Text(t), content: const Text('Coming soon.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
}

// ─── Settings Dialog ─────────────────────────────────────────────────────
class _SettingsDialog extends StatefulWidget { const _SettingsDialog(); @override State<_SettingsDialog> createState() => _SettingsDialogState(); }
class _SettingsDialogState extends State<_SettingsDialog> {
  String _ver = '';
  bool _checking = false;
  String _checkResult = '';

  @override void initState() { super.initState(); _loadVer(); }
  @override void dispose() { super.dispose(); }

  Future<void> _loadVer() async {
    try { final p = await PackageInfo.fromPlatform(); if (mounted) setState(() => _ver = p.version); } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    setState(() { _checking = true; _checkResult = ''; });
    try {
      final service = UpdateService.instance;
      final info = await service.checkForUpdate();
      if (!mounted) return;
      if (info != null) {
        setState(() { _checking = false; _checkResult = 'update'; });
        Navigator.pop(context);
        await showDialog(context: context, barrierDismissible: false, builder: (_) => UpdateDialog(info: info));
      } else {
        setState(() { _checking = false; _checkResult = 'uptodate'; });
      }
    } catch (_) {
      if (mounted) setState(() { _checking = false; _checkResult = 'error'; });
    }
  }

  @override Widget build(BuildContext ctx) {
    final resultIcon = _checkResult == 'uptodate' ? Icons.check_circle : _checkResult == 'error' ? Icons.error_outline : null;
    final resultColor = _checkResult == 'uptodate' ? const Color(0xFF4CAF50) : _checkResult == 'error' ? const Color(0xFFF44336) : const Color(0xFFC9A44C);
    final resultText = _checkResult == 'uptodate' ? 'You\'re up to date!' : _checkResult == 'error' ? 'Check failed' : _checkResult == 'update' ? 'Update available!' : '';
    return Material(
      color: Colors.transparent,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF083048),
                border: Border.all(color: const Color(0xFFF8F0E0), width: 2.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('SETTINGS', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 18, fontFamily: 'PowerGreen', letterSpacing: 3)),
                _row('Version', 'v$_ver'),
                if (_checkResult.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (resultIcon != null) ...[
                      Icon(resultIcon, color: resultColor, size: 20),
                      const SizedBox(width: 6),
                    ],
                    Text(resultText, style: TextStyle(color: resultColor, fontSize: 13, fontFamily: 'PowerGreen')),
                  ]),
                ],
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: GestureDetector(
                  onTap: _checking ? null : _checkForUpdate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC9A44C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_checking ? 'CHECKING…' : 'CHECK FOR UPDATES',
                      style: const TextStyle(color: Colors.black, fontSize: 14, fontFamily: 'PowerGreen', fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ),
                )),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFF8F0E0), width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('CLOSE', style: TextStyle(color: Color(0xFFF8F0E0), fontSize: 13, fontFamily: 'PowerGreen', letterSpacing: 2)),
                  ),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Color(0xFFF8F0E0), fontSize: 13, fontFamily: 'PowerGreen')),
      Text(value, style: TextStyle(color: const Color(0xFFF8F0E0).withValues(alpha: 0.6), fontSize: 13, fontFamily: 'PowerGreen')),
    ]),
  );
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.child, this.bgOpacity = 0.15, this.borderOpacity = 0.20});
  final VoidCallback onTap;
  final Widget child;
  final double bgOpacity;
  final double borderOpacity;
  @override Widget build(BuildContext ctx) => Material(color: Colors.transparent, child: InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Container(padding: const EdgeInsets.symmetric(vertical: 14), alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white.withValues(alpha: bgOpacity),
        border: Border.all(color: Colors.white.withValues(alpha: borderOpacity), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    ),
  ));
}

// ---- Stateless widgets (never affected by setState) ----

// ---- Shared helpers (formerly in _BatteryWidgetState) ----

Widget _dropShadow(Widget child) => Stack(
  clipBehavior: Clip.none,
  children: [
    Positioned(left: 2, top: 2, child: _recolor(child, const Color(0xFF404040))),
    child,
  ],
);

Widget _recolor(Widget child, Color c) {
  if (child is Icon) return Icon(child.icon, size: child.size, color: c);
  if (child is Text) return Text(child.data!, style: (child.style ?? const TextStyle()).copyWith(color: c));
  return child;
}

class _TitleWidget extends StatelessWidget { const _TitleWidget(); @override Widget build(BuildContext ctx) => IgnorePointer(child: Column(children: [
  Text('POKEMON', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 5, color: const Color(0xFFC9A44C).withValues(alpha: 0.85), fontFamily: 'PowerGreen')),
  const SizedBox(height: 2),
  Text('TRIAD MASTER', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white.withValues(alpha: 0.90), fontFamily: 'PowerGreen')),
  const SizedBox(height: 6),
  Container(width: 50, height: 2, decoration: BoxDecoration(borderRadius: BorderRadius.circular(1), gradient: const LinearGradient(colors: [Color(0xFFC9A44C), Color(0xFFF0D060), Color(0xFFC9A44C)]))),
])); }

class _VersionWidget extends StatefulWidget { const _VersionWidget(); @override State<_VersionWidget> createState() => _VersionWidgetState(); }
class _VersionWidgetState extends State<_VersionWidget> {
  String _ver = '';
  @override void initState() { super.initState(); _loadVer(); }
  Future<void> _loadVer() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _ver = 'v${p.version}');
    } catch (_) { if (mounted) setState(() => _ver = 'v1.0.0'); }
  }
  @override Widget build(BuildContext ctx) => _dropShadow(Text(_ver, style: const TextStyle(color: Color(0x33FFFFFF), fontSize: 11)));
}

class _BottomActions extends StatelessWidget {
  const _BottomActions();
  @override Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 230, child: _GlassButton(
      onTap: () => Navigator.pushNamed(context, AppRoutes.login),
      child: _dropShadow(const Text('Log In', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'PowerGreen'))),
      bgOpacity: 0.20,
    )),
    const SizedBox(height: 12),
    SizedBox(width: 230, child: _GlassButton(
      onTap: () => Navigator.pushNamed(context, AppRoutes.register),
      child: _dropShadow(const Text('Register', style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'PowerGreen'))),
      bgOpacity: 0.08,
      borderOpacity: 0.12,
    )),
    const SizedBox(height: 12),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TextButton(onPressed: () => _TitleScreenState._showSettings(context), child: _dropShadow(const Text('Settings', style: TextStyle(color: Colors.white38, fontSize: 12)))),
      const SizedBox(width: 24),
      TextButton(onPressed: () => _TitleScreenState._showStub(context, 'Credits'), child: _dropShadow(const Text('Credits', style: TextStyle(color: Colors.white38, fontSize: 12)))),
    ]),
    const SizedBox(height: 4),
  ]);
}

// ─── Fanned hand of 5 cards, tap to flip ──────────────────────────────────
class _FanHand extends StatelessWidget {
  const _FanHand({required this.cards, required this.pool, required this.onCardChanged});
  final List<TriadCard> cards;
  final List<TriadCard> pool;
  final void Function(int index, TriadCard newCard) onCardChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 340,
        height: 120,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < cards.length; i++)
              Positioned(
                left: i * 55.0,
                top: (i % 2 == 0 ? 0 : 20).toDouble(),
                child: Transform.rotate(
                  angle: (i - 2) * 0.15,
                  child: _FanCard(
                    card: cards[i],
                    onFlip: () => _flipCard(i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _flipCard(int index) {
    final rng = Random();
    var next = pool[rng.nextInt(pool.length)];
    if (rng.nextDouble() < 0.08 && next.cardType == TriadCardType.pokemon) {
      final sp = next.image.replaceFirst('assets/pokemon/', 'assets/pokemon_shiny/');
      next = next.copyWith(shiny: true, image: sp);
      ImageAssetCache.instance.load(sp);
    }
    final isTrainer = next.cardType == TriadCardType.trainer;
    final isFinalEvo = next.cardType == TriadCardType.pokemon &&
        (next.evolvesTo == null || next.evolvesTo!.isEmpty) &&
        next.baseLevel != null && next.baseLevel! > 1;
    final holoChance = isTrainer ? 0.30 : isFinalEvo ? 0.25 : 0.08;
    if (rng.nextDouble() < holoChance) {
      next = next.copyWith(holo: true, reverseHolo: rng.nextDouble() < 0.3);
    }
    onCardChanged(index, next);
  }
}

// ─── Single tappable card with flip animation ──────────────────────────────
class _FanCard extends StatefulWidget {
  const _FanCard({required this.card, required this.onFlip});
  final TriadCard card;
  final VoidCallback onFlip;

  @override
  State<_FanCard> createState() => _FanCardState();
}

class _FanCardState extends State<_FanCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  int _tick = 0;
  Timer? _tickTimer;
  Timer? _autoFlipTimer;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _anim = Tween<double>(begin: 1, end: -1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _tickTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() => _tick++);
    });
    _scheduleAutoFlip();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _autoFlipTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _scheduleAutoFlip() {
    _autoFlipTimer?.cancel();
    final delay = 5 + _rng.nextInt(6); // 5-10 seconds
    _autoFlipTimer = Timer(Duration(seconds: delay), () {
      if (mounted && !_ctrl.isAnimating) _doFlip();
    });
  }

  void _handleTap() {
    if (_ctrl.isAnimating) return;
    _autoFlipTimer?.cancel();
    _doFlip();
  }

  void _doFlip() {
    _ctrl.forward().then((_) {
      widget.onFlip();
      _ctrl.reverse().then((_) => _scheduleAutoFlip());
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final scaleX = _anim.value.abs();
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(scaleX, 1.0),
            child: SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(
                size: const Size(84, 84),
                painter: _CardFacePainter(card: widget.card, tick: _tick),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CardFacePainter extends CustomPainter {
  _CardFacePainter({required this.card, required this.tick}); final TriadCard card; final int tick;
  static final _sdPaint = Paint()..colorFilter = const ColorFilter.mode(Color(0xFF404040), BlendMode.srcIn);

  @override void paint(Canvas canvas, Size size) {
    final cache = ImageAssetCache.instance;
    final holoImg = cache.peek('assets/ui/holographic.png');
    final artwork = card.image.isNotEmpty ? cache.peek(card.image) : null;
    final isReverse = card.reverseHolo;

    // Draw card background first
    paintTriadCardFace(canvas, size, card: card,
      cardBg: cache.peek(kCardBgAsset),
    );

    // Regular holo: on top of bg, below artwork
    if (card.holo && !isReverse) _drawHolo(canvas, size, holoImg);

    // Artwork
    if (artwork != null) {
      final src = Rect.fromLTWH(0, 0, artwork.width.toDouble(), artwork.height.toDouble());
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.08)));
      if (isReverse) canvas.drawImageRect(artwork, src, const Offset(2, 2) & size, _sdPaint);

      if (card.holo && isReverse) {
        // Isolate the sprite in its own layer so the shimmer's blend mode is
        // masked to the artwork's own alpha (its silhouette) instead of
        // compositing against whatever's already on the canvas — otherwise
        // it paints across the full card rect (background included), since
        // the background fill beneath is already opaque everywhere.
        canvas.saveLayer(Offset.zero & size, Paint());
        canvas.drawImageRect(artwork, src, Offset.zero & size, Paint());
        _drawHolo(canvas, size, holoImg, blendMode: BlendMode.srcATop, alpha: 0x33);
        canvas.restore();
      } else {
        canvas.drawImageRect(artwork, src, Offset.zero & size, Paint());
      }
      canvas.restore();
    }

    // Numbers and type icon above artwork — draw manually
    final nums = cache.peek(kNumbersAsset);
    final typeIcn = cache.peek(typeIconAsset(card.affinity));
    final scale = size.width / kCardBgCellSize;
    if (nums != null) {
      final dx = 7 * scale, dy = 7 * scale, off = 12 * scale, gs = kNumberCellSize * scale;
      void drawNum(int value, double x, double y) {
        final dst = Rect.fromLTWH(x, y, gs, gs);
        final src = numberSourceRect(value);
        // dropshadow
        canvas.drawImageRect(nums, src, dst.translate(2, 2), _sdPaint);
        canvas.drawImageRect(nums, src, dst, Paint());
      }
      drawNum(card.values.north, dx + off, dy);
      drawNum(card.values.west, dx, dy + off);
      drawNum(card.values.east, dx + off * 2, dy + off);
      drawNum(card.values.south, dx + off, dy + off * 2);
    }
    if (typeIcn != null) {
      final boxW = 22 * scale, boxH = 36 * scale;
      final boxX = size.width - boxW - 7 * scale, boxY = 7 * scale;
      final aspect = typeIcn.width / typeIcn.height;
      double dw = boxW, dh = boxH;
      if (boxW / boxH > aspect) { dw = boxH * aspect; } else { dh = boxW / aspect; }
      final ix = boxX + (boxW - dw) / 2, iy = boxY + (boxH - dh) / 2;
      final typeSrc = Rect.fromLTWH(0, 0, typeIcn.width.toDouble(), typeIcn.height.toDouble());
      final typeDst = Rect.fromLTWH(ix, iy, dw, dh);
      // dropshadow
      canvas.drawImageRect(typeIcn, typeSrc, typeDst.translate(2, 2), _sdPaint);
      canvas.drawImageRect(typeIcn, typeSrc, typeDst, Paint());
    }

    // Frame only — no colored border stroke
    final frame = cache.peek(cardFrameAsset(card));
    if (frame != null) {
      canvas.drawImageRect(frame,
        Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
        Offset.zero & size, Paint());
    }

    // Sparkle for shiny
    if (card.shiny) {
      final sparkle = cache.peek('assets/ui/sparkle.png');
      if (sparkle != null) {
        final fw = sparkle.width / 20;
        canvas.drawImageRect(sparkle,
          Rect.fromLTWH((tick % 20) * fw, 0, fw, sparkle.height.toDouble()),
          Offset.zero & size, Paint());
      }
    }
  }

  void _drawHolo(Canvas canvas, Size size, ui.Image? img, {BlendMode blendMode = BlendMode.srcOver, int alpha = 0x44}) {
    if (img == null) return;
    final offset = (tick * 14) % img.width; // faster scroll
    canvas.drawImageRect(img,
      Rect.fromLTWH(offset.toDouble(), 0, size.width, img.height.toDouble()),
      Offset.zero & size, Paint()..color = Color(alpha << 24 | 0xFFFFFF)..blendMode = blendMode);
  }

  @override bool shouldRepaint(covariant _CardFacePainter o) => o.card.id != card.id || o.tick != tick;
}
