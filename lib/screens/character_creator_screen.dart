import 'package:flutter/material.dart';
import 'dart:math';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../models/triad_card.dart';
import '../models/trainer_appearance.dart';
import '../services/api_client.dart';
import '../services/card_repository.dart';
import '../services/trainer_parts_repository.dart';
import '../widgets/trainer_sprite_stack.dart';
import '../widgets/triad_card_view.dart';

enum _Stage {
  oak,
  gender,
  skin,
  hairStyle,
  hairColor,
  topStyle,
  topColor,
  bottomStyle,
  bottomColor,
  hatStyle,
  name,
  confirm,
  oakFarewell,
}

const _oakLines = [
  'Hello, there!\nGlad to meet you!',
  'Welcome to the world of Pokémon\nTriple Triad!',
  'My name is Oak.',
  'People affectionately refer to me\nas the Pokémon Professor.',
  'But first, tell me a little about\nyourself.',
];

/// Ports TTMMO's Discord `/intro` character-creation flow: Oak's greeting,
/// then gender → skin tone → hairstyle/color → top style/color → bottom
/// style/color → hat → trainer name, saved via PUT /api/me/character.
/// Reached after registration (or login, if character creation was never
/// finished) — see SessionLoaderScreen.
class CharacterCreatorScreen extends StatefulWidget {
  const CharacterCreatorScreen({super.key});

  @override
  State<CharacterCreatorScreen> createState() => _CharacterCreatorScreenState();
}

class _CharacterCreatorScreenState extends State<CharacterCreatorScreen> {
  _Stage _stage = _Stage.oak;
  int _oakLineIndex = 0;

  String? _gender;
  int _skinIndex = 0;
  int _hairStyleIndex = 0;
  int _hairColorIndex = 0;
  int _topStyleIndex = 0;
  int _topColorIndex = 0;
  int _bottomStyleIndex = 0;
  int _bottomColorIndex = 0;
  int _hatStyleIndex = 0;

  final _nameController = TextEditingController();
  String? _nameError;
  String? _trainerName;
  bool _checkingName = false;

  bool _saving = false;
  String? _saveError;
  int _farewellLineIndex = 0;
  bool _fadingOut = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  TrainerAppearance _defaultAppearanceFor(String gender) {
    final parts = TrainerPartsRepository.instance.forGender(gender);
    return TrainerAppearance(
      gender: gender,
      skinTone: parts.skinTones[0].file!,
      hairPath: parts.hair[0].colors[0].file!,
      topPath: parts.tops[0].colors[0].file!,
      bottomPath: parts.bottoms[0].colors[0].file!,
      hatPath: parts.hats[0].colors[0].file,
    );
  }

  TrainerAppearance get _previewAppearance {
    final parts = TrainerPartsRepository.instance.forGender(_gender!);
    return TrainerAppearance(
      gender: _gender!,
      skinTone: parts.skinTones[_skinIndex].file!,
      hairPath: parts.hair[_hairStyleIndex].colors[_hairColorIndex].file!,
      topPath: parts.tops[_topStyleIndex].colors[_topColorIndex].file!,
      bottomPath: parts.bottoms[_bottomStyleIndex].colors[_bottomColorIndex].file!,
      hatPath: parts.hats[_hatStyleIndex].colors[0].file,
    );
  }

  void _selectGender(String gender) {
    setState(() {
      _gender = gender;
      _skinIndex = 0;
      _hairStyleIndex = 0;
      _hairColorIndex = 0;
      _topStyleIndex = 0;
      _topColorIndex = 0;
      _bottomStyleIndex = 0;
      _bottomColorIndex = 0;
      _hatStyleIndex = 0;
      _stage = _Stage.skin;
    });
  }

  String? _validateName(String name) {
    if (name.length < 3 || name.length > 16) {
      return 'Name must be 3-16 characters.';
    }
    if (!RegExp(r"^[a-zA-Z0-9 '-]+$").hasMatch(name)) {
      return 'Only letters, numbers, spaces, hyphens, and apostrophes allowed.';
    }
    return null;
  }

  void _submitName() async {
    final name = _nameController.text.trim();
    final error = _validateName(name);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }

    setState(() => _checkingName = true);

    // Check server-side uniqueness
    try {
      final apiClient = context.read<ApiClient>();
      final available = await apiClient.checkTrainerName(name);
      if (!available) {
        setState(() {
          _nameError = 'That trainer name is already taken.';
          _checkingName = false;
        });
        return;
      }
    } catch (_) {
      // Server unreachable or error — allow locally, will be caught on save
    }

    setState(() {
      _trainerName = name;
      _nameError = null;
      _checkingName = false;
      _stage = _Stage.confirm;
    });
  }

  Future<void> _confirmAndSave() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final appearance = _previewAppearance.copyWith(trainerName: _trainerName);
      await context.read<PlayerProfileController>().saveCharacter(appearance);
      if (mounted) setState(() { _saving = false; _stage = _Stage.oakFarewell; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is ApiException
            ? e.message
            : 'Connection failed. Make sure you have internet and try again.\n\n($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.oak:
        return _buildOakDialogue();
      case _Stage.gender:
        return _buildGenderSelect();
      case _Stage.skin:
        return _buildSkinStep();
      case _Stage.hairStyle:
        return _buildHairStyleStep();
      case _Stage.hairColor:
        return _buildHairColorStep();
      case _Stage.topStyle:
        return _buildTopStyleStep();
      case _Stage.topColor:
        return _buildTopColorStep();
      case _Stage.bottomStyle:
        return _buildBottomStyleStep();
      case _Stage.bottomColor:
        return _buildBottomColorStep();
      case _Stage.hatStyle:
        return _buildHatStyleStep();
      case _Stage.name:
        return _buildNameStep();
      case _Stage.confirm:
        return _buildConfirmStep();
      case _Stage.oakFarewell:
        return _buildOakFarewell();
    }
  }

  static const _farewellLines = [
    "Your very own Pokémon legend\nis about to unfold!",
    "A world of dreams and adventures\nwith Pokémon awaits!",
    "I'll be seeing you later.\nGood luck on your journey!",
  ];

  Widget _buildOakFarewell() {
    final isLast = _farewellLineIndex >= _farewellLines.length - 1;
    final line = _farewellLineIndex < _farewellLines.length
        ? _farewellLines[_farewellLineIndex]
        : _farewellLines.last;

    return AnimatedOpacity(
      opacity: _fadingOut ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 600),
      onEnd: () {
        if (_fadingOut) {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      },
      child: _centeredScaffold(
        children: [
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Image.asset('assets/trainers/intro/introbase.png', width: 200, filterQuality: FilterQuality.none),
              Transform.translate(
                offset: const Offset(-5, -20),
                child: Image.asset('assets/trainers/intro/introOak.png', height: 180, filterQuality: FilterQuality.none),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _DialogueBox(text: line),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            child: FilledButton(
              onPressed: () {
                if (isLast) {
                  setState(() => _fadingOut = true);
                } else {
                  setState(() => _farewellLineIndex++);
                }
              },
              child: Text(isLast ? 'Let\'s go! ▶' : 'Next ▶'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOakDialogue() {
    final isLast = _oakLineIndex == _oakLines.length - 1;
    return _centeredScaffold(
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Image.asset(
              'assets/trainers/intro/introbase.png',
              width: 200,
              filterQuality: FilterQuality.none,
            ),
            Transform.translate(
              offset: const Offset(-5, -20),
              child: Image.asset(
                'assets/trainers/intro/introOak.png',
                height: 180,
                filterQuality: FilterQuality.none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _DialogueBox(text: _oakLines[_oakLineIndex]),
        const SizedBox(height: 24),
        SizedBox(
          width: 220,
          child: FilledButton(
            onPressed: () => setState(() {
              if (isLast) {
                _stage = _Stage.gender;
              } else {
                _oakLineIndex++;
              }
            }),
            child: Text(isLast ? 'Continue ▶' : 'Next ▶'),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderSelect() {
    return _centeredScaffold(
      children: [
        const _DialogueBox(text: 'Are you a boy?\nOr are you a girl?'),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _GenderOption(
              label: 'Boy',
              symbol: '♂',
              symbolColor: const Color(0xFF4A90E2),
              appearance: _defaultAppearanceFor('boy'),
              onTap: () => _selectGender('boy'),
            ),
            _GenderOption(
              label: 'Girl',
              symbol: '♀',
              symbolColor: const Color(0xFFE24A90),
              appearance: _defaultAppearanceFor('girl'),
              onTap: () => _selectGender('girl'),
            ),
          ],
        ),
      ],
    );
  }

  /// Every stage shares this shell: a black scaffold whose content is
  /// vertically centered (scrolling if it's ever taller than the screen)
  /// instead of anchored to the bottom — keeps interactive buttons well
  /// clear of the gesture-nav area at the screen edge.
  ///
  /// `Center` wrapping a bare `SingleChildScrollView` does NOT center short
  /// content — the scroll viewport greedily fills the offered height, so the
  /// inner column ends up pinned to one edge instead. Forcing the scroll
  /// content to be at least viewport-tall (via `LayoutBuilder` +
  /// `ConstrainedBox`) is what makes `Center` actually take effect, while
  /// still allowing normal top-anchored scrolling if content overflows.
  Widget _centeredScaffold({required List<Widget> children}) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(mainAxisSize: MainAxisSize.min, children: children),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkinStep() {
    final tones = TrainerPartsRepository.instance.forGender(_gender!).skinTones;
    return _carouselStep(
      prompt: 'Choose your skin tone.',
      currentLabel: tones[_skinIndex].label,
      onPrev: () => setState(() => _skinIndex = (_skinIndex - 1 + tones.length) % tones.length),
      onNext: () => setState(() => _skinIndex = (_skinIndex + 1) % tones.length),
      onBack: () => setState(() => _stage = _Stage.gender),
      onConfirm: () => setState(() => _stage = _Stage.hairStyle),
    );
  }

  Widget _buildHairStyleStep() {
    final styles = TrainerPartsRepository.instance.forGender(_gender!).hair;
    return _carouselStep(
      prompt: 'Choose a hairstyle.',
      currentLabel: styles[_hairStyleIndex].label,
      onPrev: () => setState(() {
        _hairStyleIndex = (_hairStyleIndex - 1 + styles.length) % styles.length;
        _hairColorIndex = 0;
      }),
      onNext: () => setState(() {
        _hairStyleIndex = (_hairStyleIndex + 1) % styles.length;
        _hairColorIndex = 0;
      }),
      onBack: () => setState(() => _stage = _Stage.skin),
      onConfirm: () => setState(() => _stage = _Stage.hairColor),
    );
  }

  Widget _buildHairColorStep() {
    final colors = TrainerPartsRepository.instance.forGender(_gender!).hair[_hairStyleIndex].colors;
    return _carouselStep(
      prompt: 'Choose a hair color.',
      currentLabel: colors[_hairColorIndex].label,
      onPrev: () => setState(() => _hairColorIndex = (_hairColorIndex - 1 + colors.length) % colors.length),
      onNext: () => setState(() => _hairColorIndex = (_hairColorIndex + 1) % colors.length),
      onBack: () => setState(() => _stage = _Stage.hairStyle),
      onConfirm: () => setState(() => _stage = _Stage.topStyle),
    );
  }

  Widget _buildTopStyleStep() {
    final styles = TrainerPartsRepository.instance.forGender(_gender!).tops;
    return _carouselStep(
      prompt: 'Choose a top.',
      currentLabel: styles[_topStyleIndex].label,
      onPrev: () => setState(() {
        _topStyleIndex = (_topStyleIndex - 1 + styles.length) % styles.length;
        _topColorIndex = 0;
      }),
      onNext: () => setState(() {
        _topStyleIndex = (_topStyleIndex + 1) % styles.length;
        _topColorIndex = 0;
      }),
      onBack: () => setState(() => _stage = _Stage.hairColor),
      onConfirm: () => setState(() => _stage = _Stage.topColor),
    );
  }

  Widget _buildTopColorStep() {
    final colors = TrainerPartsRepository.instance.forGender(_gender!).tops[_topStyleIndex].colors;
    return _carouselStep(
      prompt: "Choose your top's color.",
      currentLabel: colors[_topColorIndex].label,
      onPrev: () => setState(() => _topColorIndex = (_topColorIndex - 1 + colors.length) % colors.length),
      onNext: () => setState(() => _topColorIndex = (_topColorIndex + 1) % colors.length),
      onBack: () => setState(() => _stage = _Stage.topStyle),
      onConfirm: () => setState(() => _stage = _Stage.bottomStyle),
    );
  }

  Widget _buildBottomStyleStep() {
    final styles = TrainerPartsRepository.instance.forGender(_gender!).bottoms;
    return _carouselStep(
      prompt: 'Choose a bottom.',
      currentLabel: styles[_bottomStyleIndex].label,
      onPrev: () => setState(() {
        _bottomStyleIndex = (_bottomStyleIndex - 1 + styles.length) % styles.length;
        _bottomColorIndex = 0;
      }),
      onNext: () => setState(() {
        _bottomStyleIndex = (_bottomStyleIndex + 1) % styles.length;
        _bottomColorIndex = 0;
      }),
      onBack: () => setState(() => _stage = _Stage.topColor),
      onConfirm: () => setState(() => _stage = _Stage.bottomColor),
    );
  }

  Widget _buildBottomColorStep() {
    final colors = TrainerPartsRepository.instance.forGender(_gender!).bottoms[_bottomStyleIndex].colors;
    return _carouselStep(
      prompt: "Choose your bottom's color.",
      currentLabel: colors[_bottomColorIndex].label,
      onPrev: () => setState(() => _bottomColorIndex = (_bottomColorIndex - 1 + colors.length) % colors.length),
      onNext: () => setState(() => _bottomColorIndex = (_bottomColorIndex + 1) % colors.length),
      onBack: () => setState(() => _stage = _Stage.bottomStyle),
      onConfirm: () => setState(() => _stage = _Stage.hatStyle),
    );
  }

  Widget _buildHatStyleStep() {
    final styles = TrainerPartsRepository.instance.forGender(_gender!).hats;
    return _carouselStep(
      prompt: 'Choose a hat.',
      currentLabel: styles[_hatStyleIndex].label,
      onPrev: () => setState(() => _hatStyleIndex = (_hatStyleIndex - 1 + styles.length) % styles.length),
      onNext: () => setState(() => _hatStyleIndex = (_hatStyleIndex + 1) % styles.length),
      onBack: () => setState(() => _stage = _Stage.bottomColor),
      onConfirm: () => setState(() => _stage = _Stage.name),
    );
  }

  Widget _carouselStep({
    required String prompt,
    required String currentLabel,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onBack,
    required VoidCallback onConfirm,
  }) {
    return _centeredScaffold(
      children: [
        _DialogueBox(text: prompt),
        const SizedBox(height: 16),
        TrainerSpriteStack(appearance: _previewAppearance, size: 200),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left, color: Colors.white70)),
            SizedBox(
              width: 180,
              child: Text(
                currentLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right, color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(width: 140, child: OutlinedButton(onPressed: onBack, child: const Text('◀ Back'))),
            SizedBox(width: 140, child: FilledButton(onPressed: onConfirm, child: const Text('✅ Confirm'))),
          ],
        ),
      ],
    );
  }

  Widget _buildNameStep() {
    return _centeredScaffold(
      children: [
        TrainerSpriteStack(appearance: _previewAppearance, size: 160),
        const SizedBox(height: 24),
        const _DialogueBox(text: "Now, what's your name?"),
        const SizedBox(height: 24),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _nameController,
            maxLength: 16,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'Trainer Name', hintText: 'Ash'),
            onSubmitted: (_) => _submitName(),
          ),
        ),
        if (_nameError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_nameError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: 140,
              child: OutlinedButton(
                onPressed: () => setState(() => _stage = _Stage.hatStyle),
                child: const Text('◀ Back'),
              ),
            ),
            SizedBox(
              width: 140,
              child: FilledButton(
                onPressed: _checkingName ? null : _submitName,
                child: _checkingName
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('✏️ Confirm'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfirmStep() {
    return _centeredScaffold(
      children: [
        TrainerSpriteStack(appearance: _previewAppearance, size: 180),
        const SizedBox(height: 24),
        _DialogueBox(text: 'So your name is $_trainerName?'),
        const SizedBox(height: 24),
        if (_saveError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_saving)
          const CircularProgressIndicator()
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 140,
                child: OutlinedButton(
                  onPressed: () => setState(() => _stage = _Stage.name),
                  child: const Text('🔁 Change'),
                ),
              ),
              SizedBox(
                width: 140,
                child: FilledButton(onPressed: _confirmAndSave, child: const Text('✅ Yes')),
              ),
            ],
          ),
      ],
    );
  }}

class _DialogueBox extends StatelessWidget {
  const _DialogueBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A4A), width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFF8F8F8), fontSize: 16, height: 1.4),
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.label,
    required this.symbol,
    required this.symbolColor,
    required this.appearance,
    required this.onTap,
  });

  final String label;
  final String symbol;
  final Color symbolColor;
  final TrainerAppearance appearance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF2A2A4A), width: 1.5),
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF1A1A2E),
            ),
            child: TrainerSpriteStack(appearance: appearance, size: 140),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                symbol,
                style: TextStyle(color: symbolColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
