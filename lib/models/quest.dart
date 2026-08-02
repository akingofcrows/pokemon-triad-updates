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
    rewardDescription: 'Pokédex upgrade + 300 Poké Dollars',
    rewardMoney: 300,
    objectives: [
      QuestObjective(description: 'Travel to Viridian City'),
      QuestObjective(description: 'Visit the PokéMart in Viridian City'),
      QuestObjective(description: 'Return the parcel to Professor Oak'),
    ],
  );
}
