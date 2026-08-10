import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/trainer_appearance.dart';
import '../widgets/trainer_sprite_stack.dart';

enum JankenHand { rock, paper, scissors }

class JankenScreen extends StatefulWidget {
  const JankenScreen({
    super.key,
    required this.opponentName,
    required this.opponentPortrait,
    required this.rules,
    required this.onComplete,
    this.opponentCardImage,
  });

  final String opponentName;
  final String opponentPortrait;
  final List<String> rules;
  final String? opponentCardImage;
  final void Function({required JankenHand player, required JankenHand opponent, required bool playerGoesFirst}) onComplete;

  @override
  State<JankenScreen> createState() => _JankenScreenState();
}

class _JankenScreenState extends State<JankenScreen> {
  final _rng = Random();
  JankenHand? _playerHand;
  JankenHand? _opponentHand;
  bool _busy = false;
  bool _showResult = false;
  String? _resultText;

  void _choose(JankenHand hand) {
    if (_busy) return;
    setState(() {
      _busy = true;
      _playerHand = hand;
    });

    // NPC picks after brief delay
    Timer(const Duration(milliseconds: 500), () {
      final npcHand = JankenHand.values[_rng.nextInt(3)];
      final result = _compare(_playerHand!, npcHand);
      setState(() {
        _opponentHand = npcHand;
        _showResult = true;
        _resultText = _resultMessage(_playerHand!, npcHand, result);
      });

      // Fade to battle after result
      Timer(const Duration(milliseconds: 2000), () {
        if (!mounted) return;
        if (result == 0) {
          // Draw — reset and play again
          setState(() {
            _playerHand = null;
            _opponentHand = null;
            _busy = false;
            _showResult = false;
            _resultText = null;
          });
        } else {
          widget.onComplete(
            player: _playerHand!,
            opponent: _opponentHand!,
            playerGoesFirst: result > 0,
          );
        }
      });
    });
  }

  /// Returns: >0 = player wins, 0 = draw, <0 = opponent wins
  int _compare(JankenHand a, JankenHand b) {
    if (a == b) return 0;
    return switch (a) {
      JankenHand.rock => b == JankenHand.scissors ? 1 : -1,
      JankenHand.paper => b == JankenHand.rock ? 1 : -1,
      JankenHand.scissors => b == JankenHand.paper ? 1 : -1,
    };
  }

  String _resultMessage(JankenHand player, JankenHand opponent, int result) {
    final pName = 'You';
    final oName = widget.opponentName;
    if (result == 0) return "It's a draw!";
    return result > 0
        ? "You chose ${player.name}, $oName chose ${opponent.name}\nPlayer goes first!"
        : "$pName chose ${player.name}, $oName chose ${opponent.name}\n$oName goes first!";
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfileController>().profile;
    final playerAppearance = TrainerAppearance(
      gender: profile.gender ?? 'boy',
      skinTone: profile.skinTone ?? 'light',
      hairPath: profile.hairPath ?? 'trainers/male/hair/hair_1__black.png',
      topPath: profile.topPath ?? 'trainers/male/tops/t_shirt__blue.png',
      bottomPath: profile.bottomPath ?? 'trainers/male/bottoms/jeans__black.png',
      hatPath: profile.hatPath,
    );
    final playerName = profile.trainerName ?? profile.playerName;

    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _VsBanner(
                    playerAppearance: playerAppearance,
                    playerName: playerName,
                    opponentName: widget.opponentName,
                    opponentPortrait: widget.opponentPortrait,
                    opponentCardImage: widget.opponentCardImage,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Janken to decide who goes first',
                    style: TextStyle(color: Color(0xFFB4B9C8), fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  _RulesPanel(rules: widget.rules),
                  const SizedBox(height: 16),
                  // Arms between rules and buttons
                  _JankenArms(player: _playerHand, opponent: _opponentHand),
                  const SizedBox(height: 28),
                  _HandPicker(selected: _playerHand, onChoose: _choose),
                  const Spacer(flex: 1),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            if (_showResult) _buildResultOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC9A44C), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sports_kabaddi, color: Color(0xFFC9A44C), size: 36),
              const SizedBox(height: 12),
              Text(
                _resultText!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VsBanner extends StatelessWidget {
  const _VsBanner({
    required this.playerAppearance,
    required this.playerName,
    required this.opponentName,
    required this.opponentPortrait,
    this.opponentCardImage,
  });

  final TrainerAppearance playerAppearance;
  final String playerName;
  final String opponentName;
  final String opponentPortrait;
  final String? opponentCardImage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final ribbonH = w * 0.26;   // VS banner height
      final bustH = w * 0.30;     // trainer bust size

      return SizedBox(
        height: bustH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // VS bars centered vertically
            Positioned(
              left: 0, right: 0,
              top: bustH / 2 - ribbonH / 2,
              child: SizedBox(
                height: ribbonH,
                child: Row(
                  children: [
                    Expanded(child: Image.asset('assets/ui/vsBar_blue.png', fit: BoxFit.fill, filterQuality: FilterQuality.none)),
                    Expanded(child: Image.asset('assets/ui/vsBar_red.png', fit: BoxFit.fill, filterQuality: FilterQuality.none)),
                  ],
                ),
              ),
            ),
            // Player trainer sprite (left)
            Positioned(
              left: w * 0.18 - bustH / 2,
              top: 0,
              child: TrainerSpriteStack(appearance: playerAppearance, size: bustH),
            ),
            // Opponent sprite (right)
            Positioned(
              right: w * 0.18 - bustH / 2,
              top: 0,
              child: SizedBox(
                width: bustH, height: bustH,
                child: opponentCardImage != null
                    ? Image.asset(opponentCardImage!, width: bustH, height: bustH, filterQuality: FilterQuality.none)
                    : Image.asset(opponentPortrait, width: bustH, height: bustH, filterQuality: FilterQuality.none),
              ),
            ),
            // VS logo centered
            Positioned(
              left: w / 2 - w * 0.15,
              top: bustH / 2 - w * 0.15,
              child: Image.asset('assets/ui/hgss_vs1.png', width: w * 0.30, height: w * 0.30, filterQuality: FilterQuality.none),
            ),
          ],
        ),
      );
    });
  }
}

/// Clips [child] to [maxVisibleHeight] measured from its own top, without
/// scaling it — used so trainer busts stop exactly at the vsBar's bottom
/// edge instead of spilling onto the background below.
class _ClippedBust extends StatelessWidget {
  const _ClippedBust({required this.height, required this.maxVisibleHeight, required this.child});

  final double height;
  final double maxVisibleHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = maxVisibleHeight.clamp(0.0, height);
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: visible / height,
        child: SizedBox(height: height, child: child),
      ),
    );
  }
}

class _RulesPanel extends StatelessWidget {
  const _RulesPanel({required this.rules});

  final List<String> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18182C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF5A648C), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Rules', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('•  $rule', style: const TextStyle(color: Color(0xFFC8D2E6), fontSize: 17)),
            ),
        ],
      ),
    );
  }
}

class _HandPicker extends StatelessWidget {
  const _HandPicker({required this.selected, required this.onChoose});

  final JankenHand? selected;
  final ValueChanged<JankenHand> onChoose;

  @override
  Widget build(BuildContext context) {
    const btn = 90.0;
    const gap = 14.0;

    Widget button(JankenHand hand, int col, String label) {
      final isSelected = selected == hand;
      // Row 0 = idle (top), Row 1 = selected (bottom)
      final buttonRow = isSelected ? 1 : 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => onChoose(hand),
            child: SizedBox(
              width: btn, height: btn,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _SpriteCell(
                    asset: 'assets/ui/Janken_button.png',
                    sheetW: 280, sheetH: 188, cols: 3, rows: 2, col: col, row: buttonRow,
                    width: btn, height: btn,
                  ),
                  if (isSelected)
                    OverflowBox(
                      maxWidth: btn + 16, maxHeight: btn + 16,
                      child: Image.asset('assets/ui/Janken_cursor.png', width: btn + 16, height: btn + 16, filterQuality: FilterQuality.none),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Color(0xFFDCDCDC), fontSize: 16)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            button(JankenHand.rock, 0, 'Rock'),
            SizedBox(width: gap),
            button(JankenHand.scissors, 1, 'Scissors'),
            SizedBox(width: gap),
            button(JankenHand.paper, 2, 'Paper'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          selected == null ? 'Tap your move' : '...',
          style: const TextStyle(color: Color(0xFF9096AA), fontSize: 16),
        ),
      ],
    );
  }
}

/// Shows both arms between rules and buttons.
class _JankenArms extends StatelessWidget {
  const _JankenArms({required this.player, required this.opponent});

  final JankenHand? player;
  final JankenHand? opponent;

  // Arm row per hand: Rock=row2(bottom), Scissors=row1(mid), Paper=row0(top)
  static int _armRow(JankenHand? hand) => switch (hand) {
    JankenHand.rock => 2,
    JankenHand.scissors => 1,
    JankenHand.paper => 0,
    null => 2,
  };

  @override
  Widget build(BuildContext context) {
    const fistH = 90.0;
    const fistW = fistH * (388 / 214);

    return SizedBox(
      height: fistH * 0.5,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -fistW * 0.3,
            top: -fistH * 0.2,
            child: Transform.flip(
              flipX: true,
              child: _SpriteCell(
                asset: 'assets/ui/Janken_hand.png',
                sheetW: 388, sheetH: 642, cols: 1, rows: 3, col: 0, row: _armRow(player),
                width: fistW, height: fistH,
              ),
            ),
          ),
          Positioned(
            right: -fistW * 0.3,
            top: -fistH * 0.2,
            child: _SpriteCell(
              asset: 'assets/ui/Janken_hand.png',
              sheetW: 388, sheetH: 642, cols: 1, rows: 3, col: 0, row: _armRow(opponent),
              width: fistW, height: fistH,
            ),
          ),
        ],
      ),
    );
  }
}

/// Crops one cell out of a [cols]x[rows] spritesheet without pre-slicing it
/// into separate asset files — same offset/clip trick as
/// `battle_header_bar.dart`'s `_ScorePip`.
class _SpriteCell extends StatelessWidget {
  const _SpriteCell({
    required this.asset,
    required this.sheetW,
    required this.sheetH,
    required this.cols,
    required this.rows,
    required this.col,
    required this.row,
    required this.width,
    required this.height,
  });

  final String asset;
  final double sheetW;
  final double sheetH;
  final int cols;
  final int rows;
  final int col;
  final int row;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final nativeCellW = sheetW / cols;
    final nativeCellH = sheetH / rows;
    final scale = height / nativeCellH;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: -col * nativeCellW * scale,
              top: -row * nativeCellH * scale,
              child: Image.asset(
                asset,
                width: sheetW * scale,
                height: sheetH * scale,
                filterQuality: FilterQuality.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
