import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A quest objective the player must complete.
class QuestObjective {
  final String description;
  bool completed;

  QuestObjective({required this.description, this.completed = false});

  Map<String, dynamic> toJson() => {'description': description, 'completed': completed};
  factory QuestObjective.fromJson(Map<String, dynamic> json) =>
      QuestObjective(description: json['description'] as String, completed: json['completed'] == true);
}

/// A quest with objectives and a reward.
class Quest {
  final String id;
  final String name;
  final List<QuestObjective> objectives;
  final String rewardDescription;
  final int rewardMoney;
  bool completed;

  Quest({
    required this.id,
    required this.name,
    required this.objectives,
    this.rewardDescription = '',
    this.rewardMoney = 0,
    this.completed = false,
  });

  bool get allObjectivesDone => objectives.every((o) => o.completed);
  int get doneCount => objectives.where((o) => o.completed).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'completed': completed,
    'objectives': objectives.map((o) => o.toJson()).toList(),
    'rewardDescription': rewardDescription,
    'rewardMoney': rewardMoney,
  };

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'] as String,
    name: json['name'] as String,
    completed: json['completed'] == true,
    rewardDescription: json['rewardDescription'] as String? ?? '',
    rewardMoney: json['rewardMoney'] as int? ?? 0,
    objectives: (json['objectives'] as List)
        .map((o) => QuestObjective.fromJson(o as Map<String, dynamic>))
        .toList(),
  );
}

/// Holds quest-completion dialogue loaded from quests.json.
class QuestCompletionDialogue {
  final String speaker;
  final String portrait;
  final List<String> pages;
  final String actionLabel;

  const QuestCompletionDialogue({
    required this.speaker,
    required this.portrait,
    required this.pages,
    required this.actionLabel,
  });

  factory QuestCompletionDialogue.fromJson(Map<String, dynamic> json) => QuestCompletionDialogue(
    speaker: json['speaker'] as String? ?? '',
    portrait: json['portrait'] as String? ?? '',
    pages: (json['pages'] as List).cast<String>(),
    actionLabel: json['actionLabel'] as String? ?? 'OK',
  );
}

/// Static quest definitions — the game's quest database.
class QuestData {
  static Quest get newStart => Quest(
    id: 'new_start',
    name: 'New Start',
    rewardDescription: '100 Poké Dollars',
    rewardMoney: 100,
    objectives: [
      QuestObjective(description: 'Check your PC'),
      QuestObjective(description: 'Go downstairs'),
      QuestObjective(description: 'Talk to Mom'),
    ],
  );

  static Quest get momsErrand => Quest(
    id: 'moms_errand',
    name: "Mom's Errand",
    rewardDescription: 'Pokédex + 200 Poké Dollars',
    rewardMoney: 200,
    objectives: [
      QuestObjective(description: 'Leave the house'),
      QuestObjective(description: 'Visit Professor Oak at his lab'),
      QuestObjective(description: 'Receive your starter deck'),
    ],
  );

  static Quest get oaksParcel => Quest(
    id: 'oaks_parcel',
    name: "Oak's Parcel",
    rewardDescription: '10 Poké Balls + 200 Poké Dollars',
    rewardMoney: 200,
    objectives: [
      QuestObjective(description: 'Travel to Viridian City'),
      QuestObjective(description: 'Pick up the parcel at Viridian PokéMart'),
      QuestObjective(description: 'Return the parcel to Professor Oak'),
    ],
  );

  /// Cached quest definitions loaded from quests.json.
  static Map<String, dynamic>? _questsJson;

  /// Load quest definitions from assets/data/quests.json.
  static Future<void> load() async {
    if (_questsJson != null) return;
    final raw = await rootBundle.loadString('assets/data/quests.json');
    _questsJson = jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Returns completion dialogue for a quest, or null if none defined.
  static QuestCompletionDialogue? completionDialogue(String questId) {
    final q = _findQuest(questId);
    if (q == null) return null;
    final cd = q['completionDialogue'];
    if (cd == null) return null;
    return QuestCompletionDialogue.fromJson(cd as Map<String, dynamic>);
  }

  /// Returns quest detail info: { name, objectives, rewardDescription, rewardMoney, rewardItems, icon? }.
  static Map<String, dynamic>? questDetail(String questId) {
    final q = _findQuest(questId);
    if (q == null) return null;
    return {
      'name': q['name'] ?? '',
      'objectives': (q['objectives'] as List?)?.cast<String>() ?? <String>[],
      'rewardDescription': q['rewardDescription'] ?? '',
      'rewardMoney': q['rewardMoney'] ?? 0,
      'rewardItems': q['rewardItems'] ?? <Map<String, dynamic>>[],
      if (q['icon'] != null) 'icon': q['icon'],
    };
  }

  static Map<String, dynamic>? _findQuest(String questId) {
    if (_questsJson == null) return null;
    final list = _questsJson!['quests'] as List?;
    if (list == null) return null;
    for (final q in list) {
      final qMap = q as Map<String, dynamic>;
      if (qMap['id'] == questId) return qMap;
    }
    return null;
  }
}
