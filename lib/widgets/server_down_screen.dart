import 'dart:math';

import 'package:flutter/material.dart';

/// Server-down error screen — Voltorb rotates side-to-side
/// like it's wobbling in place, with a "Voltorbs in the
/// server room" message and Retry / Log Out buttons.
class ServerDownScreen extends StatefulWidget {
  const ServerDownScreen({
    super.key,
    required this.onRetry,
    this.onLogOut,
  });

  final VoidCallback onRetry;
  final VoidCallback? onLogOut;

  @override
  State<ServerDownScreen> createState() => _ServerDownScreenState();
}

class _ServerDownScreenState extends State<ServerDownScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _startLoop();
  }

  void _startLoop() {
    Future.doWhile(() async {
      await _ctrl.forward();
      _ctrl.reset();
      await Future.delayed(const Duration(milliseconds: 500));
      return mounted;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Voltorb rocking in place ──
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  final double angle;
                  if (t < 0.25) {
                    angle = -sin(t / 0.25 * pi / 2) * 0.35;
                  } else if (t < 0.5) {
                    angle = -sin((1 - (t - 0.25) / 0.25) * pi / 2) * 0.35;
                  } else if (t < 0.75) {
                    angle = sin((t - 0.5) / 0.25 * pi / 2) * 0.35;
                  } else {
                    angle = sin((1 - (t - 0.75) / 0.25) * pi / 2) * 0.35;
                  }
                  return Transform(
                    transform: Matrix4.identity()
                      ..translate(65.0, 130.0, 0.0)
                      ..rotateZ(angle)
                      ..translate(-65.0, -130.0, 0.0),
                    child: Image.asset(
                      'assets/pokemon/VOLTORB.png',
                      width: 130,
                      height: 130,
                      filterQuality: FilterQuality.none,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // ── Message ──
              const Text(
                'Server Down!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Voltorbs found in the server room,\nwe are clearing them out',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 32),
              // ── Retry ──
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (widget.onLogOut != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onLogOut,
                  child: const Text('Log Out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
