import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/quest.dart';
import '../models/trainer_appearance.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/card_repository.dart';
import '../widgets/quest_display.dart';
import '../widgets/trainer_sprite_stack.dart';
import '../widgets/triad_card_view.dart';

/// Player's bedroom — first scene after waking up.
class BedroomScreen extends StatefulWidget {
  const BedroomScreen({super.key});

  @override
  State<BedroomScreen> createState() => _BedroomScreenState();
}

class _BedroomScreenState extends State<BedroomScreen> {
  List<TriadCard> _topCards = [];

  @override
  void initState() {
    super.initState();
    _topCards = _computeTopCards();
    context.read<ApiClient>().updateLocation('Your Bedroom');
  }

  List<TriadCard> _computeTopCards() {
    final controller = context.read<PlayerProfileController>();
    final growth = controller.cardGrowth;
    if (growth.isEmpty) return [];
    final sorted = growth.entries.toList()
      ..sort((a, b) => b.value.xp.compareTo(a.value.xp));
    return sorted.take(3)
        .map((e) => CardRepository.instance.cardById(e.key))
        .whereType<TriadCard>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfileController>().profile;
    final appearance = TrainerAppearance(
      trainerName: profile.trainerName ?? profile.playerName,
      gender: profile.gender ?? 'boy',
      skinTone: profile.skinTone ?? '',
      hairPath: profile.hairPath ?? '',
      topPath: profile.topPath ?? '',
      bottomPath: profile.bottomPath ?? '',
      hatPath: profile.hatPath,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Bedroom', style: TextStyle(fontSize: 16)),
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
          // Blurred bedroom background
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Image.asset(
                'assets/locations/playerhouse1.png',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.40),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          // Location badge — top center
          Positioned(
            top: 0,
            left: 40,
            right: 40,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bed, color: Colors.amber, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Your Bedroom',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          // Navigation icons (same as home screen)
          Positioned(
            top: 54,
            right: 12,
            child: _NavIcon(
              image: 'assets/ui/trainercard.png',
              tooltip: 'Trainer Card',
              onTap: () => Navigator.pushNamed(context, AppRoutes.trainerCard),
            ),
          ),
          Positioned(
            right: 12,
            top: 116,
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
          // Center: trainer + quest + buttons
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  // Trainer sprite
                  SizedBox(
                    height: 200,
                    child: _OrbitingTrainer(
                      elapsed: Duration.zero,
                      appearance: appearance,
                      cards: _topCards,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Active quest if any
                  Consumer<PlayerProfileController>(
                    builder: (_, ctrl, __) {
                      final quest = ctrl.activeQuest;
                      if (quest != null)
                        return QuestDisplay(quest: quest);
                      return const SizedBox.shrink();
                    },
                  ),
                  const SizedBox(height: 16),
                  // Buttons
                  _GlassNavButton(
                    onTap: () {
                      context.read<PlayerProfileController>().completeObjective('Go downstairs');
                      Navigator.pushNamed(context, AppRoutes.houseDownstairs);
                    },
                    child: const Text('Go Downstairs', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  _GlassNavButton(
                    onTap: () => context.read<PlayerProfileController>().completeObjective('Check your PC'),
                    child: const Text('Check PC', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                  const Spacer(),
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

// ─── Orbiting trainer + cards ──────────────────────────────────────────
class _OrbitingTrainer extends StatelessWidget {
  const _OrbitingTrainer({
    required this.elapsed,
    required this.appearance,
    required this.cards,
  });

  final Duration elapsed;
  final TrainerAppearance appearance;
  final List<TriadCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        final orbitR = min(cx, cy) * 0.65;

        final t = elapsed.inMilliseconds / 12000.0;
        final behind = <Widget>[];
        final inFront = <Widget>[];

        for (var i = 0; i < cards.length; i++) {
          final phase = (i / max(cards.length, 1)) * 2 * pi;
          final speed = 1.0 + i * 0.4;
          final angle = phase + t * 2 * pi * speed;
          final rx = orbitR * (0.85 + 0.15 * sin(t * 3 * pi + i));
          final ry = orbitR * 0.7;
          final x = cx + rx * cos(angle) - 36;
          final y = cy + ry * sin(angle) - 36;

          final cardWidget = Positioned(
            left: x,
            top: y,
            child: Transform.scale(
              scale: 1.05,
              child: SizedBox(
                width: 72,
                height: 72,
                child: TriadCardView(card: cards[i], size: 72),
              ),
            ),
          );

          if (sin(angle) < -0.05) {
            behind.add(cardWidget);
          } else {
            inFront.add(cardWidget);
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            ...behind,
            if (cards.isNotEmpty)
              Positioned(
                left: cx - 80,
                top: cy - 10,
                child: Image.asset(
                  'assets/ui/elite3_base1.png',
                  width: 160,
                  filterQuality: FilterQuality.none,
                ),
              ),
            Positioned(
              left: cx - 60,
              top: cards.isNotEmpty ? cy - 84 : cy - 60,
              child: TrainerSpriteStack(appearance: appearance, size: 120),
            ),
            ...inFront,
          ],
        );
      },
    );
  }
}

// ─── Glass navigation button (matching home screen) ───────────────────
class _GlassNavButton extends StatelessWidget {
  const _GlassNavButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
