import 'package:flutter/material.dart';

import '../models/trainer_appearance.dart';

/// Composites a trainer sprite from its layered parts — matches TTMMO's
/// `compositeTrainerSprite` layer order: base → bottoms → tops → hair → hat.
/// All part PNGs share the same 160×160 canvas, so no offset math is needed.
class TrainerSpriteStack extends StatelessWidget {
  const TrainerSpriteStack({super.key, required this.appearance, this.size = 160});

  final TrainerAppearance appearance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hatPath = appearance.hatPath;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _layer(appearance.skinTone),
          _layer(appearance.bottomPath),
          _layer(appearance.topPath),
          _layer(appearance.hairPath),
          if (hatPath != null) _layer(hatPath),
        ],
      ),
    );
  }

  Widget _layer(String assetPath) {
    return Image.asset(
      'assets/$assetPath',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
    );
  }
}
