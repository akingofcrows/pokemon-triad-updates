import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/quest.dart';
import '../screens/route_battle_screen.dart';
import '../services/api_client.dart';
import '../widgets/quest_display.dart';

/// Pallet Town — hub area with Oak's Lab, Player's House, and Route 1.
class PalletTownScreen extends StatefulWidget {
  const PalletTownScreen({super.key});

  @override
  State<PalletTownScreen> createState() => _PalletTownScreenState();
}

class _PalletTownScreenState extends State<PalletTownScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().updateLocation('Pallet Town');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
          // Background
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Image.asset(
                'assets/locations/pallet.png',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.30),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
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
          // Location label
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('PALLET TOWN', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4)),
              ),
            ),
          ),
          // Buildings
          Positioned(
            left: 20,
            bottom: 160,
            child: _BuildingButton(
              icon: Icons.home,
              label: "My House",
              onTap: () => Navigator.pushNamed(context, AppRoutes.houseDownstairs),
            ),
          ),
          Positioned(
            right: 20,
            top: 120,
            child: _BuildingButton(
              icon: Icons.biotech,
              label: "Oak's Lab",
              onTap: () {
                context.read<PlayerProfileController>().completeObjective('Visit Professor Oak at his lab');
                Navigator.pushNamed(context, AppRoutes.oaksLab);
              },
            ),
          ),
          Positioned(
            top: 200,
            right: 10,
            child: _BuildingButton(
              icon: Icons.map,
              label: 'Route 1',
              onTap: () async {
                final ctrl = context.read<PlayerProfileController>();
                final alreadySeen = await ctrl.hasSeenParcelQuest();
                if (!alreadySeen && mounted) {
                  final name = ctrl.profile.trainerName ?? ctrl.profile.playerName;
                  await showDialog(
                    context: context,
                    builder: (_) => _OakParcelDialog(characterName: name),
                  );
                  if (mounted) await ctrl.startParcelQuest();
                }
                if (!mounted) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const RouteBattleScreen(locationId: 'route_1'),
                ));
              },
            ),
          ),
          // Quest + actions at bottom
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Consumer<PlayerProfileController>(
              builder: (_, ctrl, __) {
                final quest = ctrl.activeQuest;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (quest != null) QuestDisplay(quest: quest),
                    if (quest != null) const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionChip(
                          icon: Icons.explore,
                          label: 'Explore',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('You look around but find nothing interesting.')),
                            );
                          },
                        ),
                        _ActionChip(
                          icon: Icons.phishing,
                          label: 'Fish',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("You don't have a fishing rod yet.")),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingButton extends StatelessWidget {
  const _BuildingButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.amber, size: 32),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─── Oak's parcel dialogue ─────────────────────────────────────────────
class _OakParcelDialog extends StatelessWidget {
  const _OakParcelDialog({required this.characterName});
  final String characterName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/trainers/intro/introOak.png', height: 80),
          const SizedBox(height: 12),
          Text(
            'Professor Oak',
            style: TextStyle(color: Colors.amber.shade300, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Oh hey, $characterName, before you head out — I have a parcel that needs to be picked up in Viridian City. Is there any way you can stop by the PokéMart there and bring it back to me? I'll let them know you're coming...",
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}
