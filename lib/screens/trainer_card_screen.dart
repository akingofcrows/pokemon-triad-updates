import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/player_profile.dart';
import '../models/trainer_appearance.dart';
import '../services/auth_service.dart';
import '../services/card_repository.dart';
import '../widgets/trainer_sprite_stack.dart';

/// A Pokémon-style "Trainer Card" — TTMMO's card/card_back (boy) and
/// card_f/card_back_f (girl) artwork, with the player's composited trainer
/// sprite and stats overlaid. Tap to flip between front and back.
class TrainerCardScreen extends StatefulWidget {
  const TrainerCardScreen({super.key});

  @override
  State<TrainerCardScreen> createState() => _TrainerCardScreenState();
}

class _TrainerCardScreenState extends State<TrainerCardScreen> with TickerProviderStateMixin {
  late final AnimationController _tiltController;
  late final Animation<double> _tiltAnimation;
  late final AnimationController _flipController;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _tiltAnimation = Tween<double>(begin: -0.035, end: 0.035).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeInOut),
    );
    _flipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _tiltController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  void _flip() {
    if (_flipController.isAnimating) return;
    if (_flipController.value == 0) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfileController>().profile;
    final isGirl = profile.gender == 'girl';
    final bgAsset = _bgFor(profile.location);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Trainer Card'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Image.asset(bgAsset, fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.40),
                  colorBlendMode: BlendMode.darken),
            ),
          ),
          Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: GestureDetector(
            onTap: _flip,
            child: AnimatedBuilder(
              animation: Listenable.merge([_tiltAnimation, _flipController]),
              builder: (context, child) {
                final flipAngle = _flipController.value * math.pi;
                final showingBack = _flipController.value >= 0.5;
                final face = showingBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: CardBackWidget(isGirl: isGirl, profile: profile),
                      )
                    : CardFrontWidget(isGirl: isGirl, profile: profile);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateZ(_tiltAnimation.value)
                    ..rotateY(flipAngle),
                  child: face,
                );
              },
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }

  static String _bgFor(String? location) {
    const def = 'assets/locations/oakslab.png';
    if (location == null) return def;
    const named = <String, String>{
      'Pallet Town': 'assets/locations/pallet.png',
      'Route 1': 'assets/locations/route1.png',
      'Viridian City': 'assets/locations/viridian.png',
      'Route 2': 'assets/locations/route2.png',
      'Viridian Forest': 'assets/locations/viridianforest.png',
      'Pewter City': 'assets/locations/pewter.png',
      'Cerulean City': 'assets/locations/cerulean.png',
      'Vermilion City': 'assets/locations/vermillion.png',
      'Lavender Town': 'assets/locations/lavender.png',
      'Celadon City': 'assets/locations/celadon.png',
      'Fuchsia City': 'assets/locations/fuschia.png',
      'Saffron City': 'assets/locations/saffron.png',
      'Cinnabar Island': 'assets/locations/cinnabar.png',
      'Mt. Moon': 'assets/locations/mtmoon.png',
    };
    if (named.containsKey(location)) return named[location]!;
    final routeMatch = RegExp(r'^Route (\d+)$').firstMatch(location);
    if (routeMatch != null) {
      return 'assets/locations/route${routeMatch.group(1)}.png';
    }
    return def;
  }

  Future<void> _logOut(BuildContext context) async {
    await context.read<AuthService>().logout();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.title, (route) => false);
    }
  }
}

class CardFrontWidget extends StatelessWidget {
  const CardFrontWidget({required this.isGirl, required this.profile});

  final bool isGirl;
  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final asset =
        isGirl ? 'assets/trainers/card/card_front_f.png' : 'assets/trainers/card/card_front.png';

    return AspectRatio(
      aspectRatio: 484 / 356,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          double fx(double px) => px / 484 * w;
          double fy(double px) => px / 356 * h;

          return Stack(
            children: [
              Positioned.fill(
                child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.none),
              ),
              if (profile.hasCharacter)
                Positioned(
                  left: fx(314),
                  top: fy(90),
                  width: fx(144),
                  height: fy(144),
                  child: TrainerSpriteStack(
                    appearance: TrainerAppearance(
                      gender: profile.gender!,
                      skinTone: profile.skinTone!,
                      hairPath: profile.hairPath!,
                      topPath: profile.topPath!,
                      bottomPath: profile.bottomPath!,
                      hatPath: profile.hatPath,
                    ),
                    size: fx(144),
                  ),
                ),
              _statLine('Name: ${profile.trainerName ?? profile.playerName}', fx(24), fy(65), fx(260)),
              _statLine(_formatFriendCode(profile.friendCode), fx(322), fy(65), fx(130)),
              _statLine('Money: \$${profile.money}', fx(24), fy(113), fx(260)),
              _statLine(
                'Cards: ${profile.ownedCardIds.length}/${CardRepository.instance.allCards.length}',
                fx(24),
                fy(161),
                fx(260),
              ),
              _statLine('Record: ${profile.wins}W-${profile.losses}L-${profile.draws}D', fx(24), fy(209), fx(260)),
              _statLine('Joined: ${_formatJoinedDate(profile.joinedAt)}', fx(24), fy(257), fx(260)),
              Positioned(
                left: 0,
                right: 0,
                bottom: fy(10),
                child: const Text(
                  'Tap to flip',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A stable pseudo trainer-ID derived from the name, since accounts don't
  /// carry a human-facing numeric ID — deterministic so it doesn't change
  /// across app restarts.
  String _formatFriendCode(String? code) {
    if (code == null || code.isEmpty) return '————';
    // Format as XXXX-XXXX-XXXX
    if (code.length >= 12) {
      return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}';
    }
    return code;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatJoinedDate(String? joinedAt) {
    if (joinedAt == null) return '—';
    final parsed = DateTime.tryParse(joinedAt);
    if (parsed == null) return '—';
    return '${_months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Widget _statLine(String text, double left, double centerY, double width) {
    return Positioned(
      left: left,
      top: centerY - 11,
      width: width,
      height: 22,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFF15305A), fontSize: 13, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class CardBackWidget extends StatelessWidget {
  const CardBackWidget({required this.isGirl, required this.profile});

  final bool isGirl;
  final PlayerProfile profile;

  @override
  Widget build(BuildContext context) {
    final asset = isGirl ? 'assets/trainers/card/card_back_f.png' : 'assets/trainers/card/card_back.png';
    final total = profile.wins + profile.losses + profile.draws;
    final winRate = total == 0 ? '—' : '${(profile.wins / total * 100).round()}%';
    final totalCards = CardRepository.instance.allCards.length;

    return AspectRatio(
      aspectRatio: 484 / 356,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          double fx(double px) => px / 484 * w;
          double fy(double px) => px / 356 * h;

          return Stack(
            children: [
              Positioned.fill(child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.none)),
              _row('Cards Owned', '${profile.ownedCardIds.length}/$totalCards', fx(24), fy(33), fx(446)),
              _row('Decks Saved', '${profile.decks.length}', fx(24), fy(65), fx(446)),
              _row('Total Duels:', '$total', fx(24), fy(113), fx(446)),
              _row('Duel Record', 'Won: ${profile.wins}   Lost: ${profile.losses}', fx(24), fy(145), fx(446)),
              _row('Win Rate', winRate, fx(24), fy(177), fx(446)),
              Positioned(
                left: 0,
                right: 0,
                bottom: fy(10),
                child: const Text(
                  'Tap to flip',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF15305A), fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, double left, double centerY, double width) {
    return Positioned(
      left: left,
      top: centerY - 13,
      width: width,
      height: 26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
