import 'package:flutter/material.dart';

import '../models/quest.dart';

/// Displays the current quest with objectives and progress.
class QuestDisplay extends StatelessWidget {
  const QuestDisplay({super.key, required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final done = quest.doneCount;
    final total = quest.objectives.length;
    final allDone = quest.allObjectivesDone;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allDone
              ? Colors.green.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allDone ? Icons.check_circle : Icons.assignment,
                color: allDone ? Colors.green : Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                quest.name,
                style: TextStyle(
                  color: allDone ? Colors.green : Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (allDone) ...[
                const SizedBox(width: 8),
                Text(
                  'COMPLETE',
                  style: TextStyle(color: Colors.green.shade300, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...quest.objectives.map((obj) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  obj.completed ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: obj.completed ? Colors.green : Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(
                  obj.description,
                  style: TextStyle(
                    color: obj.completed ? Colors.white38 : Colors.white70,
                    fontSize: 13,
                    decoration: obj.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          )),
          if (allDone && quest.rewardMoney > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Reward: ${quest.rewardDescription}',
              style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          if (!allDone)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$done / $total',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
