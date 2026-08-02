import 'package:flutter/material.dart';

/// Displays a Pokémon's icon sprite from assets/images/icons/.
/// Sprites are 128×64 with 2 frames (64×64 each) side by side.
/// Frame 0 is the default, frame 1 animates on loop via an internal ticker.
class PokemonIcon extends StatefulWidget {
  const PokemonIcon({
    super.key,
    required this.pokemonName,
    this.size = 64,
    this.animate = true,
  });

  /// The Pokémon name (e.g. "Pikachu", "Bulbasaur") — matched to
  /// UPPERCASE icon files in assets/images/icons/.
  final String pokemonName;

  /// Display size (width & height in logical pixels).
  final double size;

  /// Whether to animate between the two 64×64 frames.
  final bool animate;

  @override
  State<PokemonIcon> createState() => _PokemonIconState();
}

class _PokemonIconState extends State<PokemonIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  String? _assetPath;
  int _frameCount = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _resolvePath();
    if (widget.animate && _frameCount > 1) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PokemonIcon old) {
    super.didUpdateWidget(old);
    if (old.pokemonName != widget.pokemonName) {
      _resolvePath();
      if (widget.animate && _frameCount > 1) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.stop();
      }
    }
  }

  void _resolvePath() {
    final name = widget.pokemonName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final path = 'assets/images/icons/$name.png';
    // Check if the base frame exists — try _1, _2 variants if not.
    // For now, use the base path; the sprite sheet handles both frames.
    _assetPath = path;
    _frameCount = 2; // assume 2-frame sprite sheet
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Derives an icon asset path from a card or Pokémon name.
  static String? iconPathFor(String pokemonName) {
    final name = pokemonName.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return 'assets/images/icons/$name.png';
  }

  @override
  Widget build(BuildContext context) {
    if (_assetPath == null) return const SizedBox.shrink();

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          // Determine which frame to show.
          // Frame 0: left half, Frame 1: right half
          final frameIndex = _frameCount > 1 ? (_ctrl.value * (_frameCount - 1)).round() : 0;

          return ClipRect(
            child: Align(
              alignment: Alignment(-1 + frameIndex * 2, 0), // left or right half
              widthFactor: 0.5, // only show 64px of the 128px width
              child: Image.asset(
                _assetPath!,
                width: widget.size * 2, // scale to match sprite sheet proportions
                height: widget.size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}
