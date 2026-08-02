import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_values.dart';
import '../models/triad_card.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

/// Opens a booster pack — shows 5 cards with a reveal animation.
class BoosterPackScreen extends StatefulWidget {
  const BoosterPackScreen({super.key});

  @override
  State<BoosterPackScreen> createState() => _BoosterPackScreenState();
}

class _BoosterPackScreenState extends State<BoosterPackScreen> {
  final List<_BoosterCard> _cards = [];
  int _revealed = 0;
  bool _opening = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _generateCards();
    Future.delayed(const Duration(milliseconds: 400), _startReveal);
  }

  void _generateCards() {
    final rng = Random();
    final allCards = CardRepository.instance.allCards;
    final pool = allCards.where((c) =>
      c.cardType == TriadCardType.pokemon &&
      !c.id.startsWith('card_trainer')).toList();

    for (var i = 0; i < 5; i++) {
      // Weight toward common/uncommon, small chance of rare+
      final roll = rng.nextInt(100);
      List<TriadCard> tier;
      if (roll < 60) {
        tier = pool.where((c) => c.rarity == CardRarity.common).toList();
      } else if (roll < 90) {
        tier = pool.where((c) => c.rarity == CardRarity.uncommon).toList();
      } else if (roll < 98) {
        tier = pool.where((c) => c.rarity == CardRarity.rare).toList();
      } else {
        tier = pool.where((c) => c.rarity == CardRarity.epic || c.rarity == CardRarity.legendary).toList();
      }
      if (tier.isEmpty) tier = pool;

      final card = tier[rng.nextInt(tier.length)];
      final level = 1 + rng.nextInt(5);
      final isShiny = rng.nextInt(64) == 0;
      final bonus = CardValues(
        north: rng.nextInt(3), south: rng.nextInt(3),
        east: rng.nextInt(3), west: rng.nextInt(3),
      );

      _cards.add(_BoosterCard(
        card: card.copyWith(values: card.values.plusBonus(bonus), shiny: isShiny, baseLevel: level),
        level: level,
        isShiny: isShiny,
      ));
    }
  }

  void _startReveal() {
    setState(() => _opening = true);
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return false;
      setState(() => _revealed++);
      return _revealed < 5;
    });
  }

  Future<void> _saveAndClose() async {
    if (_saved) return;
    _saved = true;
    // Save all cards to the server
    try {
      await context.read<PlayerProfileController>().addBoosterCards(
        _cards.map((c) => {
          'cardId': c.card.id,
          'level': c.level,
          'isShiny': c.isShiny,
        }).toList(),
      );
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text('FIELD TRIP BOOSTER',
                style: TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 3)),
            const SizedBox(height: 8),
            Text('${5 - _revealed} cards remaining...',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: List.generate(_cards.length, (i) {
                    final c = _cards[i];
                    final revealed = i < _revealed;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: revealed
                          ? _BoosterCardWidget(card: c.card, level: c.level, isShiny: c.isShiny)
                          : _BoosterCardBack(),
                    );
                  }),
                ),
              ),
            ),
            if (_revealed >= 5)
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveAndClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Add to Collection', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _BoosterCard {
  final TriadCard card;
  final int level;
  final bool isShiny;
  const _BoosterCard({required this.card, required this.level, required this.isShiny});
}

class _BoosterCardWidget extends StatelessWidget {
  const _BoosterCardWidget({required this.card, required this.level, required this.isShiny});
  final TriadCard card;
  final int level;
  final bool isShiny;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isShiny ? Colors.amber.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isShiny ? Colors.amber.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TriadCardView(card: card, size: 90),
          const SizedBox(height: 4),
          Text(card.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Lv.$level', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            if (isShiny) ...[
              const SizedBox(width: 6),
              const Text('⭐', style: TextStyle(fontSize: 12)),
            ],
          ]),
        ],
      ),
    );
  }
}

class _BoosterCardBack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120, height: 160,
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: Colors.white24, size: 40),
      ),
    );
  }
}
