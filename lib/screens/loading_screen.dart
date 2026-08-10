import 'dart:math';

import 'package:flutter/material.dart';
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key, this.message = 'Loading…', this.progress});

  final String message;
  final double? progress; // 0.0 – 1.0, null = indeterminate

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    // Don't call setState on every tick — use AnimatedBuilder instead
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => SizedBox(
                width: 240,
                height: 180,
                child: CustomPaint(
                  painter: _DeckShufflePainter(_ctrl.value),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (widget.progress != null) ...[
              SizedBox(
                width: 240,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: widget.progress,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(widget.progress! * 100).round()}%',
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontFamily: 'PowerGreen',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cards fan out from a deck, shuffle around, then stack back into a pile.
class _DeckShufflePainter extends CustomPainter {
  _DeckShufflePainter(this.t);
  final double t;

  static const _cardW = 48.0;
  static const _cardH = 68.0;
  static const _colors = [
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFFFFB300),
    Color(0xFF9C27B0),
    Color(0xFFF44336),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    const n = 5;

    // Deck stack at the bottom — 3 stacked cards.
    for (var j = 0; j < 3; j++) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 48 + j * 2), width: _cardW, height: _cardH),
        const Radius.circular(5),
      );
      canvas.drawRRect(r, Paint()..color = const Color(0xFF1A1A2E).withValues(alpha: 0.55 - j * 0.15));
      canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white10);
    }

    // Animated cards — emerge from deck, shuffle, return.
    for (var i = 0; i < n; i++) {
      final phase = (t + i / n) % 1.0;
      final emerge = _smoothstep(phase, 0.0, 0.22);
      final retreat = _smoothstep(phase, 0.78, 1.0);
      final visible = emerge * (1.0 - retreat);

      final angle = (i - 2) * 0.28 * visible + sin(t * 2 * pi + i * 1.7) * 0.12 * visible;
      final dx = (i - 2) * _cardW * 0.54 * visible + cos(t * 3 * pi + i * 2.1) * 8 * visible;
      final dy = -48 * visible + sin(t * 2.5 * pi + i * 0.9) * 6 * visible;
      final scale = 0.75 + 0.25 * visible;

      canvas.save();
      canvas.translate(cx + dx, cy + dy);
      canvas.rotate(angle);
      canvas.scale(scale);

      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: _cardW, height: _cardH),
        const Radius.circular(5),
      );
      canvas.drawRRect(r, Paint()..color = _colors[i].withValues(alpha: 0.88 * visible.clamp(0.2, 1.0)));
      canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = _colors[i].withValues(alpha: visible.clamp(0.3, 1.0)));

      canvas.restore();
    }
  }

  double _smoothstep(double t, double e0, double e1) {
    final x = ((t - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  bool shouldRepaint(covariant _DeckShufflePainter old) => old.t != t;
}
