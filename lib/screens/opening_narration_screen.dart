import 'dart:async';

import 'package:flutter/material.dart';

import '../app/routes.dart';
import '../services/world_clock.dart';

/// Shows after character creation: Oak's farewell, then weather-based narration,
/// then transitions to the home screen.
class OpeningNarrationScreen extends StatefulWidget {
  const OpeningNarrationScreen({super.key});

  @override
  State<OpeningNarrationScreen> createState() => _OpeningNarrationScreenState();
}

class _OpeningNarrationScreenState extends State<OpeningNarrationScreen> {
  int _stage = 0; // 0=oak, 1+=narration panels
  final List<String> _narrationLines = [];
  String _displayedText = '';
  int _charIndex = 0;
  Timer? _typeTimer;
  bool _typingDone = false;

  @override
  void initState() {
    super.initState();
    final clock = WorldClock.instance;
    _narrationLines.addAll(clock.buildNarration(clock.weather, clock.dayPeriod));
    _startOakMessage();
  }

  void _startOakMessage() {
    const msg = "Your very own Pokémon Triad legend is about to unfold!\n\nA world of dreams and adventures with Pokémon Triad cards awaits!\n\nLet's go!";
    _typeText(msg, () {
      setState(() => _stage = 1);
      _startNarrationLine(0);
    });
  }

  void _startNarrationLine(int index) {
    if (index >= _narrationLines.length) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.bedroom);
        }
      });
      return;
    }
    setState(() {
      _charIndex = 0;
      _displayedText = '';
      _typingDone = false;
    });
    _typeText(_narrationLines[index], () async {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) _startNarrationLine(index + 1);
    });
  }

  void _typeText(String text, VoidCallback onDone) {
    _charIndex = 0;
    _displayedText = '';
    _typingDone = false;
    const interval = Duration(milliseconds: 35);
    _typeTimer?.cancel();
    _typeTimer = Timer.periodic(interval, (t) {
      if (_charIndex < text.length) {
        _charIndex++;
        if (mounted) setState(() => _displayedText = text.substring(0, _charIndex));
      } else {
        t.cancel();
        if (mounted) setState(() => _typingDone = true);
        onDone();
      }
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOak = _stage == 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOak) ...[
                  Image.asset('assets/trainers/intro/introOak.png', height: 160),
                  const SizedBox(height: 24),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF083048),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF8F0E0), width: 1.5),
                  ),
                  child: Text(
                    _displayedText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF8F0E0),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_typingDone)
                  SizedBox(
                    width: 200,
                    child: FilledButton(
                      onPressed: () {
                        if (_stage == 0) {
                          setState(() => _stage = 1);
                          _startNarrationLine(0);
                        } else {
                          _startNarrationLine(
                            _narrationLines.indexOf(_displayedText) + 1,
                          );
                        }
                      },
                      child: const Text('Continue ▶'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
