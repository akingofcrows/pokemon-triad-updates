/// Models for the Story Mode location-based travel system.
///
/// Locations contain a sequence of battle/story nodes that the player
/// completes in order to unlock the next major destination.

/// A location (route, city, dungeon) in the story.
class StoryLocation {
  final String id;
  final String name;
  final String region;
  final String? unlockRequirement;
  final String? entryRequirement;
  final WildLevelRange wildLevelRange;
  final List<StoryNode> nodes;
  final List<String> completionUnlocks;
  final CompletionRule completionRule;
  final int shinyRate;

  const StoryLocation({
    required this.id,
    required this.name,
    required this.region,
    this.unlockRequirement,
    this.entryRequirement,
    required this.wildLevelRange,
    required this.nodes,
    this.completionUnlocks = const [],
    this.completionRule = const CompletionRule(),
    this.shinyRate = 16,
  });

  /// Whether this location is fully completed according to its completion rule.
  /// Completion count is tracked externally via [completionCount].
  bool isFullyComplete(int completionCount) {
    // defeatAll: check nodes directly since isSatisfied doesn't have node access
    if (completionRule.type == CompletionRuleType.defeatAll) {
      return nodes
          .where((n) => n.type != StoryNodeType.trainer)
          .every((n) => n.isCompleted);
    }
    return completionRule.isSatisfied(
      completedNodes: nodes.where((n) => n.isCompleted).length,
      completionCount: completionCount,
    );
  }

  /// Human-readable progress text for the UI.
  String completionProgressText(int completionCount) {
    return completionRule.progressText(
      completedNodes: nodes.where((n) => n.isCompleted).length,
      completionCount: completionCount,
      speciesName: completionRule.cardId != null
          ? _speciesNameFor(completionRule.cardId!)
          : null,
    );
  }

  /// Completion fraction 0.0–1.0 for progress bars.
  double completionFraction(int completionCount) {
    return completionRule.progressFraction(
      completedNodes: nodes.where((n) => n.isCompleted).length,
      completionCount: completionCount,
    );
  }

  static String _speciesNameFor(String cardId) {
    // Quick lookup — card repository may not be available statically
    return cardId.replaceAll('card_', '').replaceAll('_1', '').replaceAll('_', ' ')
        .split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  /// The first incomplete node, or null if all done.
  StoryNode? get nextNode {
    for (final node in nodes) {
      if (!node.isCompleted) return node;
    }
    return null;
  }

  factory StoryLocation.fromJson(Map<String, dynamic> json) {
    return StoryLocation(
      id: json['id'] as String,
      name: json['name'] as String,
      region: json['region'] as String? ?? 'kanto',
      unlockRequirement: json['unlockRequirement'] as String?,
      entryRequirement: json['entryRequirement'] as String?,
      wildLevelRange: WildLevelRange.fromJson(
          json['wildLevelRange'] as Map<String, dynamic>),
      nodes: (json['nodes'] as List<dynamic>)
          .map((n) => StoryNode.fromJson(n as Map<String, dynamic>))
          .toList(),
      completionUnlocks: (json['completionUnlocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      completionRule: json['completionRule'] != null
          ? CompletionRule.fromJson(json['completionRule'] as Map<String, dynamic>)
          : const CompletionRule(),
      shinyRate: json['shinyRate'] as int? ?? 16,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'region': region,
        'unlockRequirement': unlockRequirement,
        'entryRequirement': entryRequirement,
        'wildLevelRange': wildLevelRange.toJson(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'completionUnlocks': completionUnlocks,
        'completionRule': completionRule.toJson(),
        if (shinyRate != 16) 'shinyRate': shinyRate,
      };
}

/// A single node in a location's path.
class StoryNode {
  final String id;
  final StoryNodeType type;
  final String? requiredNode;

  // For trainer / gym / npcTrainer nodes
  final String? npcId;

  // For wild nodes
  final List<WildEncounterEntry>? encounterTable;

  // For item nodes: what item to give and how many
  final String? itemId;
  final int itemQuantity;

  // For puzzle nodes: dialog lines shown to the player
  final List<String>? dialogLines;

  // For catchChallenge nodes: the species to catch
  final String? targetCardId;

  // Mutable runtime state
  bool isCompleted;
  bool isUnlocked;

  StoryNode({
    required this.id,
    required this.type,
    this.requiredNode,
    this.npcId,
    this.encounterTable,
    this.itemId,
    this.itemQuantity = 1,
    this.dialogLines,
    this.targetCardId,
    this.isCompleted = false,
    this.isUnlocked = false,
  });

  /// The first node in a location has no requiredNode and is always unlocked.
  bool get isFirst => requiredNode == null;

  factory StoryNode.fromJson(Map<String, dynamic> json) {
    return StoryNode(
      id: json['id'] as String,
      type: _nodeTypeFromString(json['type'] as String),
      requiredNode: json['requiredNode'] as String?,
      npcId: json['npcId'] as String?,
      encounterTable: (json['encounterTable'] as List<dynamic>?)
          ?.map((e) =>
              WildEncounterEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      itemId: json['itemId'] as String?,
      itemQuantity: json['itemQuantity'] as int? ?? 1,
      dialogLines: (json['dialogLines'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      targetCardId: json['targetCardId'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      isUnlocked: json['isUnlocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'requiredNode': requiredNode,
        'npcId': npcId,
        'encounterTable': encounterTable?.map((e) => e.toJson()).toList(),
        'itemId': itemId,
        'itemQuantity': itemQuantity,
        'dialogLines': dialogLines,
        'targetCardId': targetCardId,
        'isCompleted': isCompleted,
        'isUnlocked': isUnlocked,
      };

  static StoryNodeType _nodeTypeFromString(String s) {
    switch (s) {
      case 'wild':
        return StoryNodeType.wild;
      case 'trainer':
        return StoryNodeType.trainer;
      case 'story':
        return StoryNodeType.story;
      case 'wild_boss':
        return StoryNodeType.wildBoss;
      case 'npc_trainer':
        return StoryNodeType.npcTrainer;
      case 'item':
        return StoryNodeType.item;
      case 'puzzle':
        return StoryNodeType.puzzle;
      case 'catch_challenge':
        return StoryNodeType.catchChallenge;
      default:
        return StoryNodeType.wild;
    }
  }
}

enum StoryNodeType { wild, trainer, story, wildBoss, npcTrainer, item, puzzle, catchChallenge }

/// Level range for wild Pokémon at a location.
class WildLevelRange {
  final int min;
  final int max;

  const WildLevelRange({required this.min, required this.max});

  factory WildLevelRange.fromJson(Map<String, dynamic> json) {
    return WildLevelRange(
      min: json['min'] as int,
      max: json['max'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'min': min, 'max': max};
}

/// A weighted encounter entry in a route's wild table.
class WildEncounterEntry {
  final String cardId;
  final int weight;
  final EncounterRarity rarity;
  final EncounterTimeOfDay timeOfDay;
  final int? minLevel;
  final int? maxLevel;

  const WildEncounterEntry({
    required this.cardId,
    required this.weight,
    this.rarity = EncounterRarity.common,
    this.timeOfDay = EncounterTimeOfDay.both,
    this.minLevel,
    this.maxLevel,
  });

  factory WildEncounterEntry.fromJson(Map<String, dynamic> json) {
    return WildEncounterEntry(
      cardId: json['cardId'] as String,
      weight: json['weight'] as int,
      rarity: _rarityFromString(json['rarity'] as String? ?? 'common'),
      timeOfDay: _timeOfDayFromString(json['timeOfDay'] as String? ?? 'both'),
      minLevel: json['minLevel'] as int?,
      maxLevel: json['maxLevel'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'weight': weight,
        'rarity': rarity.name,
        if (timeOfDay != EncounterTimeOfDay.both) 'timeOfDay': timeOfDay.name,
        if (minLevel != null) 'minLevel': minLevel,
        if (maxLevel != null) 'maxLevel': maxLevel,
      };

  static EncounterRarity _rarityFromString(String s) {
    switch (s) {
      case 'uncommon':
        return EncounterRarity.uncommon;
      case 'rare':
        return EncounterRarity.rare;
      default:
        return EncounterRarity.common;
    }
  }

  static EncounterTimeOfDay _timeOfDayFromString(String s) {
    switch (s) {
      case 'morning':
        return EncounterTimeOfDay.morning;
      case 'day':
        return EncounterTimeOfDay.day;
      case 'night':
        return EncounterTimeOfDay.night;
      default:
        return EncounterTimeOfDay.both;
    }
  }
}

enum EncounterRarity { common, uncommon, rare }

enum EncounterTimeOfDay { morning, day, night, both }

/// Returns the current in-game time of day.
EncounterTimeOfDay get currentTimeOfDay {
  final hour = DateTime.now().hour;
  if (hour >= 4 && hour < 10) return EncounterTimeOfDay.morning;
  if (hour >= 10 && hour < 18) return EncounterTimeOfDay.day;
  return EncounterTimeOfDay.night;
}

/// Whether [entry] is available at the current time.
bool isAvailableNow(WildEncounterEntry entry) {
  return entry.timeOfDay == EncounterTimeOfDay.both ||
      entry.timeOfDay == currentTimeOfDay;
}

// ── Completion Rules ───────────────────────────────────────────────────

/// How a location is considered "complete".
enum CompletionRuleType {
  /// Complete all non-trainer nodes (the default).
  defeatAll,

  /// Catch N Pokémon of any species in this location.
  catchCount,

  /// Catch a specific species.
  catchSpecies,

  /// Win N wild battles in this location.
  winBattles,

  /// Defeat a specific NPC trainer node.
  defeatTrainer,
}

class CompletionRule {
  final CompletionRuleType type;

  /// For [catchCount], [winBattles]: the number required.
  final int count;

  /// For [catchSpecies]: the specific card ID to catch.
  final String? cardId;

  /// For [defeatTrainer]: the NPC ID to defeat.
  final String? npcId;

  const CompletionRule({
    this.type = CompletionRuleType.defeatAll,
    this.count = 0,
    this.cardId,
    this.npcId,
  });

  bool isSatisfied({required int completedNodes, required int completionCount}) {
    switch (type) {
      case CompletionRuleType.defeatAll:
        return false; // handled externally via isFullyComplete
      case CompletionRuleType.catchCount:
      case CompletionRuleType.winBattles:
        return completionCount >= count;
      case CompletionRuleType.catchSpecies:
        return completionCount >= 1;
      case CompletionRuleType.defeatTrainer:
        return completedNodes >= 1;
    }
  }

  String progressText({required int completedNodes, required int completionCount, String? speciesName}) {
    switch (type) {
      case CompletionRuleType.defeatAll:
        return '$completedNodes nodes cleared';
      case CompletionRuleType.catchCount:
        return 'Catch $completionCount/$count Pokémon';
      case CompletionRuleType.catchSpecies:
        return speciesName != null
            ? '${completionCount >= 1 ? "Caught" : "Catch"} $speciesName'
            : 'Catch target species';
      case CompletionRuleType.winBattles:
        return '$completionCount/$count battles won';
      case CompletionRuleType.defeatTrainer:
        return completedNodes >= 1 ? 'Trainer defeated' : 'Defeat the trainer';
    }
  }

  double progressFraction({required int completedNodes, required int completionCount}) {
    switch (type) {
      case CompletionRuleType.defeatAll:
        return 0.0; // shown per-node
      case CompletionRuleType.catchCount:
      case CompletionRuleType.winBattles:
        return count > 0 ? (completionCount / count).clamp(0.0, 1.0) : 1.0;
      case CompletionRuleType.catchSpecies:
      case CompletionRuleType.defeatTrainer:
        return completionCount >= 1 || completedNodes >= 1 ? 1.0 : 0.0;
    }
  }

  factory CompletionRule.fromJson(Map<String, dynamic> json) {
    return CompletionRule(
      type: _ruleTypeFromString(json['type'] as String? ?? 'defeat_all'),
      count: json['count'] as int? ?? 0,
      cardId: json['cardId'] as String?,
      npcId: json['npcId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (count > 0) 'count': count,
        if (cardId != null) 'cardId': cardId,
        if (npcId != null) 'npcId': npcId,
      };

  static CompletionRuleType _ruleTypeFromString(String s) {
    switch (s) {
      case 'catch_count':
        return CompletionRuleType.catchCount;
      case 'catch_species':
        return CompletionRuleType.catchSpecies;
      case 'win_battles':
        return CompletionRuleType.winBattles;
      case 'defeat_trainer':
        return CompletionRuleType.defeatTrainer;
      default:
        return CompletionRuleType.defeatAll;
    }
  }
}
