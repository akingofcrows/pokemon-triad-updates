import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/quest.dart';
import '../services/api_client.dart';
import '../widgets/quest_display.dart';
import 'route_battle_screen.dart';

/// Downstairs — Mom gives the player their first quest.
class HouseDownstairsScreen extends StatefulWidget {
  const HouseDownstairsScreen({super.key});

  @override
  State<HouseDownstairsScreen> createState() => _HouseDownstairsScreenState();
}

class _HouseDownstairsScreenState extends State<HouseDownstairsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().updateLocation("Player's House");
  }

  int _momTalkStep = 0;
  final _momLines = const [
    'Oh, good morning, honey!',
    "Professor Oak was looking for you.\nHe said he has something important to give you.",
    "You should go visit him at his lab.\nIt's just east of our house.",
    "Don't forget to take your Pokémon Triad cards with you!",
  ];

  @override
  Widget build(BuildContext context) {
    final talked = _momTalkStep > 0;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E0A),
      appBar: AppBar(
        title: const Text("Mom's Kitchen"),
        backgroundColor: const Color(0xFF1A0E0A),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.home),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Navigation icons
          Positioned(
            top: 4,
            right: 12,
            child: _NavIcon(
              image: 'assets/ui/trainercard.png',
              tooltip: 'Trainer Card',
              onTap: () => Navigator.pushNamed(context, AppRoutes.trainerCard),
            ),
          ),
          Positioned(
            right: 12,
            top: 66,
            child: Column(
              children: [
                _NavIcon(
                  image: 'assets/ui/collection.png',
                  tooltip: 'Collection',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.collection),
                ),
                const SizedBox(height: 8),
                _NavIcon(
                  image: 'assets/ui/carddex.png',
                  tooltip: 'Card Dex',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.cardDex),
                ),
                const SizedBox(height: 8),
                _NavIcon(
                  image: 'assets/ui/deck.png',
                  tooltip: 'Decks',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.deckBuilder),
                ),
              ],
            ),
          ),
          // Main content
          Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, size: 80, color: Colors.brown),
              const SizedBox(height: 8),
              const Text('Mom', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (talked)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF083048),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF8F0E0), width: 1.5),
                  ),
                  child: Text(
                    _momLines[_momTalkStep - 1],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF8F0E0), fontSize: 15, height: 1.5),
                  ),
                ),
              if (_momTalkStep < _momLines.length)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: 200,
                    child: _GlassButton(
                      icon: Icons.chat,
                      label: 'Talk to Mom',
                      onTap: () {
                        setState(() => _momTalkStep++);
                        if (_momTalkStep >= _momLines.length) {
                          final ctrl = context.read<PlayerProfileController>();
                          ctrl.completeObjective('Talk to Mom');
                          // Start next quest
                          ctrl.startQuest(QuestData.momsErrand);
                        }
                      },
                    ),
                  ),
                ),
              if (_momTalkStep >= _momLines.length) ...[
                const SizedBox(height: 16),
                Consumer<PlayerProfileController>(
                  builder: (_, ctrl, __) {
                    final quest = ctrl.activeQuest;
                    if (quest != null)
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: QuestDisplay(quest: quest),
                      );
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 24),
                SizedBox(
                  width: 200,
                  child: _GlassButton(
                    icon: Icons.arrow_upward,
                    label: 'Go Upstairs',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.bedroom),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 200,
                  child: _GlassButton(
                    icon: Icons.door_front_door,
                    label: 'Leave House',
                    onTap: () {
                      context.read<PlayerProfileController>().completeObjective('Leave the house');
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RouteBattleScreen(locationId: 'pallet_town')),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}

// ─── Glass navigation icon ──────────────────────────────────────────────
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.image, required this.tooltip, required this.onTap});
  final String image;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
            ),
            child: Image.asset(image, fit: BoxFit.contain),
          ),
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
