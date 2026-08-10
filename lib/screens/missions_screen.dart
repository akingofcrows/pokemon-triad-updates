import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/player_profile_controller.dart';
import '../models/card_values.dart';
import '../models/quest.dart';
import '../services/card_repository.dart';
import '../services/item_repository.dart';
import '../widgets/triad_card_view.dart';

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PlayerProfileController>();
    final quest = ctrl.activeQuest;

    return Scaffold(
      backgroundColor: const Color(0xFF2D2E35),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Missions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: quest != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quest header card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.assignment, color: Color(0xFFC9A44C), size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  quest.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: quest.completed
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : const Color(0xFFC9A44C).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  quest.completed ? 'DONE' : '${quest.doneCount}/${quest.objectives.length}',
                                  style: TextStyle(
                                    color: quest.completed ? Colors.green : const Color(0xFFC9A44C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (quest.completed && quest.rewardMoney > 0) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC9A44C).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Text('₽', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '+${quest.rewardMoney} — ${quest.rewardDescription}',
                                      style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Show reward items (cards, pokéballs, etc.)
                          _buildRewardItems(quest.id),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Objectives list
                    const Text('Objectives', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    ...quest.objectives.asMap().entries.map((entry) {
                      final i = entry.key;
                      final obj = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: obj.completed
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: obj.completed
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                              child: Center(
                                child: obj.completed
                                    ? const Icon(Icons.check, color: Colors.green, size: 18)
                                    : Text('${i + 1}', style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                obj.description,
                                style: TextStyle(
                                  color: obj.completed ? Colors.white38 : Colors.white,
                                  fontSize: 15,
                                  decoration: obj.completed ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              )
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.assignment_outlined, color: Colors.white24, size: 64),
                    SizedBox(height: 16),
                    Text('No active missions', style: TextStyle(color: Colors.white38, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Explore the world to find new quests!', style: TextStyle(color: Colors.white24, fontSize: 13)),
                  ],
                ),
              ),
      ),
    );
  }
}

Widget _buildRewardItems(String questId) {
  final detail = QuestData.questDetail(questId);
  if (detail == null) return const SizedBox.shrink();
  final items = detail['rewardItems'] as List? ?? [];
  if (items.isEmpty) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Reward Items', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1)),
      const SizedBox(height: 8),
      ...items.map((item) {
        final itemMap = item as Map<String, dynamic>;
        final itemId = itemMap['id'] as String? ?? '';
        final qty = itemMap['quantity'] as int? ?? 1;
        final isCard = itemId.startsWith('card_');
        if (isCard) {
          final card = CardRepository.instance.cardById(itemId);
          if (card == null) return const SizedBox.shrink();
          final level = itemMap['level'] as int? ?? card.baseLevel ?? 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 36, height: 36, child: TriadCardView(card: card, size: 36, showCondition: false)),
              const SizedBox(width: 8),
              Text('${card.name} Lv.$level - x $qty', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          );
        }
        final imgPath = ItemRepository().itemById(itemId)?.imageAsset ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            if (imgPath.isNotEmpty)
              Padding(padding: const EdgeInsets.only(right: 8), child: Image.asset(imgPath, height: 24, width: 24)),
            Text('x $qty', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
      }),
    ]),
  );
}
