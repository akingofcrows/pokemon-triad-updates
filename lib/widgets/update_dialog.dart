import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/cards/card_visuals.dart';
import '../game/cards/image_asset_cache.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../services/update_service.dart';

// ─── Oak-style constants ───────────────────────────────────────────────────
const _boxBg = Color(0xFF083048);
const _boxBorder = Color(0xFFF8F0E0);
const _textColor = Color(0xFFF8F0E0);
const _accent = Color(0xFFC9A44C);

const _oakSprite = 'assets/trainers/intro/introOak.png';

/// Shows the update dialog with Professor Oak + orbiting cards — single screen.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});
  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitCtrl;

  // Download state
  bool _downloading = false;
  double _progress = 0;
  String _status = '';
  Timer? _poll;
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typeTimer;
  bool _typingDone = false;

  // Orbiting cards — Bulbasaur, Charmander, Squirtle
  final List<TriadCard> _orbitCards = [];

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    // Kanto starters only
    const starterIds = {'card_bulbasaur_1', 'card_charmander_1', 'card_squirtle_1'};
    for (final c in CardRepository.instance.allCards) {
      if (starterIds.contains(c.id)) _orbitCards.add(c);
    }
    if (_orbitCards.isEmpty) {
      _orbitCards.add(TriadCard.fallback());
    }

    // Preload the Oak sprite + card artwork + shared assets for orbiting cards
    ImageAssetCache.instance.load(_oakSprite);
    final preloadPaths = <String>{
      kCardBgAsset,
      kNumbersAsset,
    };
    for (final c in _orbitCards) {
      if (c.image.isNotEmpty) preloadPaths.add(c.image);
      preloadPaths.add(typeIconAsset(c.affinity));
      preloadPaths.add(rarityFrameAsset(c.rarity));
    }
    ImageAssetCache.instance.preload(preloadPaths);

    _startTyping();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _typeTimer?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  String get _fullText {
    final v = widget.info.version;
    final log = widget.info.changelog.isNotEmpty
        ? '\n\n${widget.info.changelog}'
        : '';
    return 'Hello there! Welcome to the world of\n'
        'POKéMON TRIPLE TRIAD!\n\n'
        'Version $v is now available!$log';
  }

  void _startTyping() {
    final msg = _fullText;
    const interval = Duration(milliseconds: 28);
    _typeTimer = Timer.periodic(interval, (t) {
      if (_charIndex < msg.length) {
        _charIndex++;
        setState(() => _displayedText = msg.substring(0, _charIndex));
      } else {
        t.cancel();
        setState(() => _typingDone = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: !_downloading,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A1A30), Color(0xFF051020), Color(0xFF020810)],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // ── Background ──────────────────────────────────
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Image.asset(
                      'assets/locations/oakslab.png',
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.35),
                      colorBlendMode: BlendMode.darken,
                    ),
                  ),
                ),
                // ── Oak + orbiting cards (upper portion) ────────────
                Positioned(
                  top: screenH * 0.04,
                  left: 0,
                  right: 0,
                  height: screenH * 0.42,
                  child: _OakWithOrbitingCards(
                    orbitCtrl: _orbitCtrl,
                    cards: _orbitCards,
                  ),
                ),

                // ── Text box (bottom portion) ──────────────────────
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: _downloading ? 120 : 100,
                  child: _OakTextBox(
                    text: _displayedText,
                    downloading: _downloading,
                    progress: _progress,
                    status: _status,
                  ),
                ),

                // ── Action buttons ─────────────────────────────────
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 28,
                  child: _ActionRow(
                    downloading: _downloading,
                    typingDone: _typingDone,
                    onLater: () => Navigator.pop(context),
                    onUpdate: _startUpdate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startUpdate() async {
    final service = UpdateService.instance;

    // Check install permission first
    final canInstall = await service.canInstallApk();
    if (!canInstall && mounted) {
      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => _InstallPermissionDialog(),
      );
      if (goToSettings == true) {
        await service.openInstallSettings();
      }
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Connecting…';
      _displayedText = 'Downloading update…\n';
      _typingDone = true;
    });

    _poll = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) {
        setState(() {
          _progress = service.downloadProgress;
          _status = service.status;
          _displayedText =
              'Downloading update…\n${(_progress * 100).toStringAsFixed(0)}%';
        });
      }
    });

    final ok = await service.downloadAndInstall(widget.info.apkUrl);
    _poll?.cancel();

    if (mounted) {
      setState(() {
        _downloading = false;
        _displayedText = ok
            ? 'Installing update…'
            : 'Update failed.\n${service.status}';
      });
    }
  }
}

// ─── "Allow install unknown apps" permission dialog ────────────────────────
class _InstallPermissionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xCC0D0D1A),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.security, color: Color(0xFFC9A44C), size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Allow installs from\nthis app to update.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'PowerGreen', height: 1.5),
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: GestureDetector(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                      child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'PowerGreen', fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ),
                )),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                    ),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'PowerGreen', letterSpacing: 2)),
                  ),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Oak sprite + orbiting Triad cards ─────────────────────────────────────
class _OakWithOrbitingCards extends StatelessWidget {
  const _OakWithOrbitingCards({
    required this.orbitCtrl,
    required this.cards,
  });

  final AnimationController orbitCtrl;
  final List<TriadCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2 + 10;
        final orbitR = min(cx, cy) * 0.72;

        return AnimatedBuilder(
          animation: orbitCtrl,
          builder: (_, __) {
            final t = orbitCtrl.value;
            // Split cards: behind Oak (upper half of orbit), in front (lower half)
            final behind = <Widget>[];
            final inFront = <Widget>[];

            for (var i = 0; i < cards.length; i++) {
              final phase = (i / cards.length) * 2 * pi;
              final speed = 1.0 + i * 0.3;
              final angle = phase + t * 2 * pi * speed;
              final rx = orbitR * (0.85 + 0.15 * sin(t * 3 * pi + i));
              final ry = orbitR * 0.7;
              final x = cx + rx * cos(angle) - 42;
              final y = cy + ry * sin(angle) - 42;

              final cardWidget = Positioned(
                left: x,
                top: y,
                child: Transform.scale(
                  scale: 1.1,
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: _OrbitingTriadCard(card: cards[i]),
                  ),
                ),
              );

              // Upper half of orbit = behind Oak
              if (sin(angle) < -0.05) {
                behind.add(cardWidget);
              } else {
                inFront.add(cardWidget);
              }
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Cards behind Oak
                ...behind,
                // Base platform under Oak
                Positioned(
                  left: cx - 80,
                  top: cy + 30,
                  child: Image.asset(
                    'assets/trainers/intro/introbase.png',
                    width: 160,
                    filterQuality: FilterQuality.none,
                  ),
                ),
                // Oak sprite on top of behind cards
                Positioned(
                  left: cx - 64,
                  top: cy - 80,
                  child: Image.asset(
                    _oakSprite,
                    width: 128,
                    height: 128,
                    filterQuality: FilterQuality.none,
                  ),
                ),
                // Cards in front of Oak
                ...inFront,
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Full Triad card for orbiting (numbers, sprite, type, frame) ──────────
class _OrbitingTriadCard extends StatelessWidget {
  const _OrbitingTriadCard({required this.card});
  final TriadCard card;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(84, 84),
      painter: _OrbitingCardPainter(card: card),
    );
  }
}

class _OrbitingCardPainter extends CustomPainter {
  _OrbitingCardPainter({required this.card});
  final TriadCard card;

  @override
  void paint(Canvas canvas, Size size) {
    final cache = ImageAssetCache.instance;

    // Preload all needed assets
    final cardBg = cache.peek(kCardBgAsset);
    final nums = cache.peek(kNumbersAsset);
    final artwork = card.image.isNotEmpty ? cache.peek(card.image) : null;
    final typeIcon = cache.peek(typeIconAsset(card.affinity));
    final frame = cache.peek(rarityFrameAsset(card.rarity));

    // Background
    if (cardBg != null) {
      canvas.drawImageRect(cardBg, cardBgSourceRect(card.affinity),
          Offset.zero & size, Paint());
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF333333));
    }

    // Artwork
    if (artwork != null) {
      final src = Rect.fromLTWH(0, 0, artwork.width.toDouble(), artwork.height.toDouble());
      canvas.drawImageRect(artwork, src, Offset.zero & size, Paint());
    }

    // Numbers — no dropshadow
    if (nums != null) {
      final scale = size.width / kCardBgCellSize;
      final dx = 6 * scale, dy = 6 * scale, off = 13 * scale, gs = kNumberCellSize * scale;

      void drawNum(int value, double x, double y) {
        final dst = Rect.fromLTWH(x, y, gs, gs);
        final src = numberSourceRect(value);
        canvas.drawImageRect(nums, src, dst, Paint());
      }
      drawNum(card.values.north, dx + off, dy);
      drawNum(card.values.west, dx, dy + off);
      drawNum(card.values.east, dx + off * 2, dy + off);
      drawNum(card.values.south, dx + off, dy + off * 2);
    }

    // Type icon — no dropshadow
    if (typeIcon != null) {
      final scale = size.width / kCardBgCellSize;
      final boxW = 22 * scale, boxH = 36 * scale;
      final boxX = size.width - boxW - 6 * scale, boxY = 6 * scale;
      final src = Rect.fromLTWH(0, 0, typeIcon.width.toDouble(), typeIcon.height.toDouble());
      final aspect = typeIcon.width / typeIcon.height;
      double dw = boxW, dh = boxH;
      if (boxW / boxH > aspect) { dw = boxH * aspect; } else { dh = boxW / aspect; }
      final ix = boxX + (boxW - dw) / 2, iy = boxY + (boxH - dh) / 2;
      final typeDst = Rect.fromLTWH(ix, iy, dw, dh);
      canvas.drawImageRect(typeIcon, src, typeDst, Paint());
    }

    // Frame
    if (frame != null) {
      canvas.drawImageRect(frame,
        Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
        Offset.zero & size, Paint());
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitingCardPainter o) => o.card.id != card.id;
}

// ─── Oak-style Text Box ────────────────────────────────────────────────────
class _OakTextBox extends StatelessWidget {
  const _OakTextBox({
    required this.text,
    this.downloading = false,
    this.progress = 0,
    this.status = '',
  });

  final String text;
  final bool downloading;
  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: _boxBg,
        border: Border.all(color: _boxBorder, width: 2.5),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: _textColor,
              fontSize: 14,
              fontFamily: 'PowerGreen',
              height: 1.45,
              letterSpacing: 1.0,
            ),
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 10,
                color: _accent,
                backgroundColor: _boxBg.withValues(alpha: 0.5),
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                status,
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.55),
                  fontSize: 10,
                  fontFamily: 'PowerGreen',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Action Buttons ────────────────────────────────────────────────────────
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.downloading,
    required this.typingDone,
    required this.onLater,
    required this.onUpdate,
  });

  final bool downloading;
  final bool typingDone;
  final VoidCallback onLater;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final canUpdate = typingDone && !downloading;
    return Row(
      children: [
        Expanded(
          child: _OakButton(
            label: 'LATER',
            onTap: downloading ? null : onLater,
            primary: false,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _OakButton(
            label: canUpdate ? 'UPDATE' : '…',
            onTap: canUpdate ? onUpdate : null,
            primary: true,
          ),
        ),
      ],
    );
  }
}

class _OakButton extends StatelessWidget {
  const _OakButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: primary
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.10),
          border: Border.all(
            color: primary
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.15),
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
        child: Text(
          label,
          style: TextStyle(
            color: primary ? Colors.white : _textColor,
            fontSize: 15,
            fontFamily: 'PowerGreen',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

// ─── Public entry point ─────────────────────────────────────────────────────

/// Checks for update and shows dialog if available.
Future<void> checkAndShowUpdateDialog(BuildContext context) async {
  final info = await UpdateService.instance.checkForUpdate();
  if (info != null && context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }
}
