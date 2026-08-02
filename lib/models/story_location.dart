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
  final WildLevelRange wildLevelRange;
  final List<StoryNode> nodes;
  final List<String> completionUnlocks;

  const StoryLocation({
    required this.id,
    required this.name,
    required this.region,
    this.unlockRequirement,
    required this.wildLevelRange,
    required this.nodes,
    this.completionUnlocks = const [],
  });

  /// Whether all nodes in this location are completed.
  bool get isFullyComplete {
    return nodes.every((n) => n.isCompleted);
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
      wildLevelRange: WildLevelRange.fromJson(
          json['wildLevelRange'] as Map<String, dynamic>),
      nodes: (json['nodes'] as List<dynamic>)
          .map((n) => StoryNode.fromJson(n as Map<String, dynamic>))
          .toList(),
      completionUnlocks: (json['completionUnlocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'region': region,
        'unlockRequirement': unlockRequirement,
        'wildLevelRange': wildLevelRange.toJson(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'completionUnlocks': completionUnlocks,
      };
}

/// A single node in a location's path.
class StoryNode {
  final String id;
  final StoryNodeType type;
  final String? requiredNode;

  // For trainer nodes
  final String? npcId;

  // For wild nodes
  final List<WildEncounterEntry>? encounterTable;

  // Mutable runtime state
  bool isCompleted;
  bool isUnlocked;

  StoryNode({
    required this.id,
    required this.type,
    this.requiredNode,
    this.npcId,
    this.encounterTable,
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
      default:
        return StoryNodeType.wild;
    }
  }
}

enum StoryNodeType { wild, trainer, story, wildBoss }

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

  const WildEncounterEntry({
    required this.cardId,
    required this.weight,
    this.rarity = EncounterRarity.common,
  });

  factory WildEncounterEntry.fromJson(Map<String, dynamic> json) {
    return WildEncounterEntry(
      cardId: json['cardId'] as String,
      weight: json['weight'] as int,
      rarity: _rarityFromString(json['rarity'] as String? ?? 'common'),
    );
  }

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'weight': weight,
        'rarity': rarity.name,
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
}

enum EncounterRarity { common, uncommon, rare }
