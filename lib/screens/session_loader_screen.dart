import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/trainer_appearance.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/asset_manager.dart';
import '../services/auth_service.dart';
import '../services/card_repository.dart';
import '../widgets/server_down_screen.dart';
import '../widgets/trainer_sprite_stack.dart';
import '../widgets/triad_card_view.dart';

/// Fetches the player's profile/decks from the server, then proceeds to
/// Home. Reached right after a successful login/register, and at app boot
/// if a token is already stored. Shows the player's trainer sprite with
/// their top 3 cards orbiting around them during loading.
class SessionLoaderScreen extends StatefulWidget {
  const SessionLoaderScreen({super.key});

  @override
  State<SessionLoaderScreen> createState() => _SessionLoaderScreenState();
}

class _SessionLoaderScreenState extends State<SessionLoaderScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  bool _isNetworkError = false;
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  // Updated once profile loads
  TrainerAppearance? _trainer;
  List<TriadCard> _topCards = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (mounted) setState(() => _elapsed = elapsed);
    })..start();
    _topCards = [];
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = context.read<PlayerProfileController>();
      await controller.loadFromServer();

      if (!mounted) return;

      // Build trainer appearance from profile
      final p = controller.profile;
      _trainer = TrainerAppearance(
        trainerName: p.trainerName ?? p.playerName,
        gender: p.gender ?? 'boy',
        skinTone: p.skinTone ?? '',
        hairPath: p.hairPath ?? '',
        topPath: p.topPath ?? '',
        bottomPath: p.bottomPath ?? '',
        hatPath: p.hatPath,
      );

      // Top 3 cards by XP
      final growth = controller.cardGrowth;
      final sorted = growth.entries.toList()
        ..sort((a, b) => b.value.xp.compareTo(a.value.xp));
      _topCards = sorted.take(3)
          .map((e) => CardRepository.instance.cardById(e.key))
          .whereType<TriadCard>()
          .toList();

      // Update the UI with real trainer + cards
      if (mounted) setState(() {});

      // Initialize quests for new players
      controller.initNewPlayerQuests();

      // Sync game assets in background
      final assetMgr = AssetManager.instance;
      final baseUrl = await context.read<ApiClient>().baseUrlProvider();
      await assetMgr.init(baseUrl: baseUrl);
      assetMgr.syncIfNeeded(baseUrl: baseUrl); // fire and forget

      // Brief pause to enjoy the animation
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;
      final destination = p.hasCharacter ? AppRoutes.home : AppRoutes.characterCreator;
      Navigator.pushReplacementNamed(context, destination);
    } catch (e, st) {
      print('DEBUG SessionLoader: error $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isNetworkError = e is ApiNetworkException;
        _error = _messageFor(e);
      });
    }
  }

  String _messageFor(Object e) {
    if (e is ApiException) return e.message;
    if (e is ApiNetworkException) {
      return "Couldn't reach the server. Make sure it's running and try again.";
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _logOut() async {
    await context.read<AuthService>().logout();
    if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.title);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading) {
      // Network error → Voltorb shaking screen
      if (_isNetworkError) {
        return ServerDownScreen(
          onRetry: _load,
          onLogOut: _logOut,
        );
      }
      // Other errors → simple message
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                SizedBox(
                  width: 220,
                  child: FilledButton(onPressed: _load, child: const Text('Retry')),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _logOut, child: const Text('Log Out')),
              ],
            ),
          ),
        ),
      );
    }

    // Loading: trainer sprite + orbiting cards
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trainer + orbiting cards
            SizedBox(
              height: 300,
              child: _OrbitingTrainer(
                elapsed: _elapsed,
                appearance: _trainer,
                cards: _topCards,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Loading your adventure…',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Trainer sprite + orbiting cards ────────────────────────────────────
class _OrbitingTrainer extends StatelessWidget {
  const _OrbitingTrainer({
    required this.elapsed,
    required this.appearance,
    required this.cards,
  });

  final Duration elapsed;
  final TrainerAppearance? appearance;
  final List<TriadCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        final orbitR = min(cx, cy) * 0.65;

        // Continuous angle from elapsed time — never resets
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
                // Base platform (only if cards present)
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
                // Trainer sprite in center
                Positioned(
                  left: cx - 72,
                  top: cards.isNotEmpty ? cy - 96 : cy - 72,
                  child: appearance != null
                      ? TrainerSpriteStack(appearance: appearance!, size: 144)
                      : const SizedBox(
                          width: 144,
                          height: 144,
                          child: Icon(Icons.person, size: 72, color: Colors.white24),
                        ),
                ),
                ...inFront,
              ],
            );
      },
    );
  }
}
