import 'package:flutter/material.dart';

import '../game/cards/card_visuals.dart' show ownerBorderColor;
import '../models/battle_log_entry.dart';
import 'home_style_panel.dart';

/// Scrolling chronological list of battle events, in the same rounded
/// dark-card style used throughout the home screen.
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
    return HomeStylePanel(
      height: 160,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
