import 'package:flutter/material.dart';

import '../game/board/dashed_border_painter.dart';
import '../game/cards/card_visuals.dart' show ownerBorderColor;
import '../models/battle_log_entry.dart';

/// Scrolling chronological list of battle events, in a dashed-border panel
/// matching the board's cell style.
class BattleLogPanel extends StatefulWidget {
  const BattleLogPanel({super.key, required this.entries});

  final List<BattleLogEntry> entries;

  @override
  State<BattleLogPanel> createState() => _BattleLogPanelState();
}

class _BattleLogPanelState extends State<BattleLogPanel> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant BattleLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length > oldWidget.entries.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xCC00001C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FlourishTitle(text: 'Battle Log'),
              const SizedBox(height: 6),
              Expanded(
                child: widget.entries.isEmpty
                    ? const Center(
                        child: Text('No moves yet', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: widget.entries.length,
                        itemBuilder: (context, index) {
                          final entry = widget.entries[index];
                          final spans = <InlineSpan>[
                            TextSpan(
                              text: entry.moverName,
                              style: TextStyle(
                                color: ownerBorderColor(entry.moverOwner),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ];
                          // For capture entries, color the captured card name
                          if (entry.capturedOwner != null) {
                            final msg = entry.message;
                            final capPrefix = 'captured ';
                            if (msg.startsWith(capPrefix)) {
                              final capturedPart = msg.substring(capPrefix.length);
                              spans.add(TextSpan(text: ' $capPrefix'));
                              spans.add(TextSpan(
                                text: capturedPart,
                                style: TextStyle(
                                  color: ownerBorderColor(entry.capturedOwner!),
                                  fontWeight: FontWeight.w600,
                                ),
                              ));
                            } else {
                              spans.add(TextSpan(text: ' ${entry.message}'));
                            }
                          } else {
                            spans.add(TextSpan(text: ' ${entry.message}'));
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text.rich(
                              TextSpan(children: spans),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
    );
  }
}

class _FlourishTitle extends StatelessWidget {
  const _FlourishTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: Colors.white24)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Container(height: 1, color: Colors.white24)),
      ],
    );
  }
}

class _DashedPanelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10));
    drawDashedRRect(
      canvas,
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedPanelPainter oldDelegate) => false;
}
