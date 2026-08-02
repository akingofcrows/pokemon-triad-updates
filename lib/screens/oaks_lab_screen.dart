import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/deck.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/card_repository.dart';
import '../widgets/triad_card_view.dart';

/// Oak's Lab — where players receive their first deck.
class OaksLabScreen extends StatefulWidget {
  const OaksLabScreen({super.key});

  @override
  State<OaksLabScreen> createState() => _OaksLabScreenState();
}

class _OaksLabScreenState extends State<OaksLabScreen> {
  int _stage = 0; // 0=oak intro, 1=deck selection, 2=oak farewell
  bool _saving = false;
  String? _saveError;
  late final Map<String, bool> _shinyFlags;

  final _oakIntro = const [
    "Ah, welcome! I'm Professor Oak,\nthe leading researcher of Pokémon Triad cards!",
    "Triad cards capture the very essence\nof Pokémon in a battle of wits and strategy!",
    "Ah-ha! I have an idea...\nWhy don't I give you your very first deck?",
    "Choose wisely — each starter brings\na different type and strategy!",
  ];

  String _oakFarewell = '';

  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().updateLocation("Oak's Lab");
    final rng = Random();
    final decks = CardRepository.instance.starterDecks;
    _shinyFlags = {};
    for (final deck in decks) {
      for (final cardId in deck.cardIds) {
        _shinyFlags.putIfAbsent(cardId, () => rng.nextDouble() < 0.06); // ~1/16
      }
    }
  }

  void _nextStage() => setState(() => _stage++);

  Future<void> _selectDeck(Deck deck) async {
    setState(() { _saving = true; _saveError = null; });
    try {
      final api = context.read<ApiClient>();
      final ctrl = context.read<PlayerProfileController>();
      final cards = deck.cardIds.map((id) => {'cardId': id, 'shiny': _shinyFlags[id] == true}).toList();
      await api.claimStarterDeck(cards);
      await ctrl.createDeck(deck.name, deck.cardIds);
      ctrl.completeObjective('Receive your starter deck');

      // Persist locally so Oak tutorial stays hidden after restart
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasStarterDeck', true);

      // Build Oak's farewell with starter info
      final starterCard = CardRepository.instance.cardById(deck.cardIds.first);
      final starterName = starterCard?.name ?? deck.name;
      final typeName = _capitalize(starterCard?.affinity ?? '');

      setState(() {
        _saving = false;
        _oakFarewell = "Ah! The $typeName type Pokémon, $starterName!\nA wonderful choice. I tossed in a few more Pokémon to help you along the way and even slid in an exceptionally special card... ahem! Anyway!";
        _stage = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is ApiException ? e.message : 'Connection failed.';
      });
    }
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _deckIcon(String id) {
    if (id.contains('grass')) return '🌿';
    if (id.contains('fire')) return '🔥';
    return '💧';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2010),
      appBar: AppBar(
        title: const Text("Oak's Lab"),
        backgroundColor: const Color(0xFF0D2010),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : _stage == 0
              ? _buildOakIntro()
              : _stage == 1
                  ? _buildDeckSelection()
                  : _buildOakFarewell(),
    );
  }

  Widget _buildOakIntro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/trainers/intro/introOak.png', height: 140),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF083048),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF8F0E0), width: 1.5),
              ),
              child: Text(
                _oakIntro[_stage], // always 0
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF8F0E0), fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: _GlassButton(
                icon: Icons.arrow_forward,
                label: 'Next',
                onTap: () => setState(() {
                  if (_stage < _oakIntro.length - 1) {
                    _stage++;
                  } else {
                    _stage = 1; // go to deck selection
                  }
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeckSelection() {
    final decks = CardRepository.instance.starterDecks;

    return Column(
      children: [
        const SizedBox(height: 8),
        const Text('Choose Your Starter Deck', style: TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: decks.length,
            itemBuilder: (_, i) {
              final deck = decks[i];
              final cards = CardRepository.instance.cardsForIds(deck.cardIds);
              final displayCards = cards.map((c) => _shinyFlags[c.id] == true ? c.copyWith(shiny: true) : c).toList();

              return Card(
                color: const Color(0xFF1A2A1E),
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => _selectDeck(deck),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text('${_deckIcon(deck.id)} ${deck.name}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final c in displayCards)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: TriadCardView(card: c, size: 64, showRarityFrame: true),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOakFarewell() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/trainers/intro/introOak.png', height: 120),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF083048),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF8F0E0), width: 1.5),
              ),
              child: Text(
                _oakFarewell,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFF8F0E0), fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: _GlassButton(
                icon: Icons.home,
                label: 'Return to Pallet Town',
                onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.home),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.icon, required this.label});
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
