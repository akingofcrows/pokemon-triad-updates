import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/story_location.dart';
import '../services/api_client.dart';

/// Manages story mode progress — locations, node completion, unlocks.
///
/// Loads route definitions from `assets/data/routes.json` and tracks
/// per-node completion state synced with the server.
class StoryProgressController extends ChangeNotifier {
  final ApiClient _api;

  StoryProgressController(this._api);

  /// All story locations loaded from routes.json.
  List<StoryLocation> _locations = [];

  /// Server-synced progress: locationId -> nodeId -> progress data.
  Map<String, Map<String, _NodeProgress>> _progress = {};

  /// Completion counts per location for rule types like catchCount, winBattles.
  /// Key: locationId, Value: current count.
  final Map<String, int> _completionCounts = {};

  /// Set of location IDs that are unlocked.
  Set<String> _unlockedLocations = {};

  List<StoryLocation> get locations => List.unmodifiable(_locations);
  Map<String, Map<String, _NodeProgress>> get progress => _progress;
  Set<String> get unlockedLocations => Set.unmodifiable(_unlockedLocations);

  // ── Initialization ───────────────────────────────────────────────────

  /// Load route definitions and sync progress from server.
  Future<void> initialize() async {
    await _loadRoutes();
    notifyListeners(); // Show locations immediately
    await _syncProgress(); // Then sync server state in background
  }

  /// Reset all progression — clears unlocks, progress, and returns to Pallet Town.
  Future<void> resetProgression() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('unlockedLocations');
    await prefs.remove(_prefsKey);
    await prefs.remove('playerLocation');
    _progress.clear();
    _completionCounts.clear();
    _unlockedLocations = {'pallet_town', 'route_1'};
    // Reset every node's mutable state
    for (final loc in _locations) {
      for (final node in loc.nodes) {
        node.isCompleted = false;
        node.isUnlocked = node.isFirst;
      }
    }
    notifyListeners();
  }

  Future<void> _loadRoutes() async {
    final json = await rootBundle.loadString('assets/data/routes.json');
    final data = jsonDecode(json) as Map<String, dynamic>;
    final list = data['locations'] as List<dynamic>;
    _locations =
        list.map((l) => StoryLocation.fromJson(l as Map<String, dynamic>)).toList();

    // Pallet Town (starting town) and Route 1 are always unlocked.
    _unlockedLocations = {'pallet_town', 'route_1'};
    // Restore previously unlocked locations from local storage
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('unlockedLocations') ?? [];
    _unlockedLocations.addAll(saved);
  }

  Future<void> _syncProgress() async {
    // Primary: sync from server DB
    try {
      final serverProgress = await _api.getStoryProgress();
      _progress = {};
      for (final locEntry in serverProgress.entries) {
        _progress[locEntry.key] = {};
        for (final nodeEntry in (locEntry.value as Map<String, dynamic>).entries) {
          _progress[locEntry.key]![nodeEntry.key] = _NodeProgress(
            completed: (nodeEntry.value as Map<String, dynamic>)['completed'] == true,
            firstClear: (nodeEntry.value as Map<String, dynamic>)['firstClear'] == true,
            timesCleared:
                (nodeEntry.value as Map<String, dynamic>)['timesCleared'] as int? ?? 0,
          );
        }
      }
      _applyProgressToLocations();
      // Mirror to local cache
      await _saveLocalProgress();
      return;
    } catch (e) {
      print('[STORY] Server sync failed: $e, falling back to local cache');
    }

    // Fallback: load cached progress from local storage
    await _loadLocalProgress();
    _applyProgressToLocations();
  }

  static const _prefsKey = 'story_progress';

  Future<void> _loadLocalProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json == null) return;
      final data = jsonDecode(json) as Map<String, dynamic>;
      _progress = {};

      // Support both old format (flat) and new format (nodes + counts)
      final nodesData = data.containsKey('nodes')
          ? data['nodes'] as Map<String, dynamic>
          : data; // old format: flat map

      for (final locEntry in nodesData.entries) {
        _progress[locEntry.key] = {};
        for (final nodeEntry in (locEntry.value as Map<String, dynamic>).entries) {
          final v = nodeEntry.value as Map<String, dynamic>;
          _progress[locEntry.key]![nodeEntry.key] = _NodeProgress(
            completed: v['completed'] == true,
            firstClear: v['firstClear'] == true,
            timesCleared: v['timesCleared'] as int? ?? 0,
          );
        }
      }

      // Restore completion counts (new format), cap at required amount
      if (data.containsKey('counts')) {
        final counts = data['counts'] as Map<String, dynamic>;
        _completionCounts.clear();
        for (final entry in counts.entries) {
          final raw = (entry.value as num).toInt();
          final loc = _locations.firstWhere((l) => l.id == entry.key, orElse: () => _locations.first);
          final max = loc.completionRule.count;
          _completionCounts[entry.key] = raw > max ? max : raw;
        }
      }
      // Restore unlocked locations from cached data
      for (final loc in _locations) {
        final locProgress = _progress[loc.id] ?? {};
        for (final node in loc.nodes) {
          if (locProgress[node.id]?.completed == true) {
            node.isCompleted = true;
          }
        }
        if (loc.isFullyComplete(_completionCounts[loc.id] ?? 0)) {
          for (final unlockId in loc.completionUnlocks) {
            _unlockedLocations.add(unlockId);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLocalProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'nodes': <String, dynamic>{},
        'counts': _completionCounts.map((k, v) => MapEntry(k, v)),
      };
      for (final locEntry in _progress.entries) {
        final nodes = <String, dynamic>{};
        for (final nodeEntry in locEntry.value.entries) {
          nodes[nodeEntry.key] = {
            'completed': nodeEntry.value.completed,
            'firstClear': nodeEntry.value.firstClear,
            'timesCleared': nodeEntry.value.timesCleared,
          };
        }
        (data['nodes'] as Map<String, dynamic>)[locEntry.key] = nodes;
      }
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {}
  }

  /// Apply server-synced progress onto the local location models.
  void _applyProgressToLocations() {
    // Reset unlocks to base set, then rebuild from completed nodes
    _unlockedLocations = {'pallet_town', 'route_1'};
    for (final loc in _locations) {
      final locProgress = _progress[loc.id] ?? {};
      for (final node in loc.nodes) {
        final nodeProg = locProgress[node.id];
        if (nodeProg != null) {
          node.isCompleted = nodeProg.completed;
        }
        // Unlock logic: first node is always unlocked; others need previous node completed
        if (node.isFirst) {
          node.isUnlocked = true;
        } else {
          final prev = loc.nodes.firstWhere(
            (n) => n.id == node.requiredNode,
            orElse: () => node,
          );
          node.isUnlocked = prev.isCompleted || prev == node;
        }
      }
      // If location is fully complete, add its completion unlocks
      if (loc.isFullyComplete(_completionCounts[loc.id] ?? 0)) {
        for (final unlockId in loc.completionUnlocks) {
          _unlockedLocations.add(unlockId);
        }
      }
    }
    // Persist rebuilt unlocks to local storage
    _saveUnlockedLocations();
  }

  Future<void> _saveUnlockedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('unlockedLocations', _unlockedLocations.toList());
  }

  // ── Queries ───────────────────────────────────────────────────────────

  /// Whether a specific location is unlocked.
  bool isLocationUnlocked(String locationId) {
    return _unlockedLocations.contains(locationId);
  }

  /// Manually unlock a location (e.g. from quest completion).
  void addUnlockedLocation(String locationId) {
    if (_unlockedLocations.add(locationId)) {
      _saveUnlockedLocations();
      notifyListeners();
    }
  }

  /// Whether a location is fully completed.
  bool isLocationComplete(String locationId) {
    final loc = _getLocation(locationId);
    return loc?.isFullyComplete(_completionCounts[loc.id] ?? 0) ?? false;
  }

  /// Get a specific location by ID.
  StoryLocation? _getLocation(String locationId) {
    try {
      return _locations.firstWhere((l) => l.id == locationId);
    } catch (_) {
      return null;
    }
  }

  /// Get the next incomplete node for a location.
  StoryNode? nextNodeFor(String locationId) {
    return _getLocation(locationId)?.nextNode;
  }

  /// Completion percentage for a location (0.0 - 1.0).
  double completionFor(String locationId) {
    final loc = _getLocation(locationId);
    if (loc == null) return 0.0;
    return loc.completionFraction(_completionCounts[locationId] ?? 0);
  }

  /// Get the current completion count for a location (catches, wins, etc.), capped at required.
  int getCompletionCount(String locationId) {
    final raw = _completionCounts[locationId] ?? 0;
    final loc = _getLocation(locationId);
    final max = loc?.completionRule.count ?? 999;
    return raw > max ? max : raw;
  }

  /// Get progress text for display.
  String completionProgressText(String locationId) {
    final loc = _getLocation(locationId);
    if (loc == null) return '';
    return loc.completionProgressText(getCompletionCount(locationId));
  }

  /// Record a Pokémon catch in the current location.
  void recordCatch(String locationId) {
    final loc = _getLocation(locationId);
    if (loc == null) return;
    if (loc.completionRule.type == CompletionRuleType.catchCount ||
        loc.completionRule.type == CompletionRuleType.catchSpecies) {
      final current = _completionCounts[locationId] ?? 0;
      if (current < loc.completionRule.count) {
        _completionCounts[locationId] = current + 1;
        _saveLocalProgress();
      }
      notifyListeners();
      // Check if location is now complete
      if (loc.isFullyComplete(_completionCounts[locationId] ?? 0)) {
        for (final unlockId in loc.completionUnlocks) {
          _unlockedLocations.add(unlockId);
        }
        _saveUnlockedLocations();
        notifyListeners();
      }
    }
  }

  /// Record a wild battle win in the current location.
  void recordBattleWin(String locationId) {
    final loc = _getLocation(locationId);
    if (loc == null) return;
    if (loc.completionRule.type == CompletionRuleType.winBattles) {
      final current = _completionCounts[locationId] ?? 0;
      if (current < loc.completionRule.count) {
        _completionCounts[locationId] = current + 1;
        _saveLocalProgress();
      }
      notifyListeners();
      if (loc.isFullyComplete(_completionCounts[locationId] ?? 0)) {
        for (final unlockId in loc.completionUnlocks) {
          _unlockedLocations.add(unlockId);
        }
        _saveUnlockedLocations();
        notifyListeners();
      }
    }
  }

  /// Nodes unlocked for replay at a completed location.
  List<StoryNode> replayableNodes(String locationId) {
    final loc = _getLocation(locationId);
    if (loc == null) return [];
    // All completed nodes are replayable
    return loc.nodes.where((n) => n.isCompleted).toList();
  }

  // ── Actions ───────────────────────────────────────────────────────────

  /// Mark a node as completed. Syncs to server and updates local state.
  /// Returns true if this was a first clear.
  Future<bool> completeNode(String locationId, String nodeId) async {
    final loc = _getLocation(locationId);
    if (loc == null) return false;

    final node = loc.nodes.firstWhere((n) => n.id == nodeId);
    final wasFirstClear = !node.isCompleted;

    // Update local state
    node.isCompleted = true;

    // Unlock next node in sequence
    final nextNode = loc.nodes.firstWhere(
      (n) => n.requiredNode == nodeId,
      orElse: () => node,
    );
    if (nextNode != node) {
      nextNode.isUnlocked = true;
    }

    // Update progress map
    _progress.putIfAbsent(locationId, () => {});
    final existing = _progress[locationId]![nodeId];
    _progress[locationId]![nodeId] = _NodeProgress(
      completed: true,
      firstClear: wasFirstClear || (existing?.firstClear ?? false),
      timesCleared: (existing?.timesCleared ?? 0) + 1,
    );

    notifyListeners();

    // Sync to server
    try {
      await _api.completeStoryNode(locationId, nodeId);
    } catch (_) {
      // Will sync on next initialize()
    }

    // Save locally
    _saveLocalProgress();

    // Check if location is now fully complete → unlock next locations
    if (loc.isFullyComplete(_completionCounts[loc.id] ?? 0)) {
      for (final unlockId in loc.completionUnlocks) {
        _unlockedLocations.add(unlockId);
      }
      _saveUnlockedLocations();
      notifyListeners();
    }

    return wasFirstClear;
  }

  /// Reset all local state (for logout or recovery).
  Future<void> reset() async {
    _locations.clear();
    _progress.clear();
    _completionCounts.clear();
    _unlockedLocations.clear();
    // Clear persisted state too
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('unlockedLocations');
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}

class _NodeProgress {
  final bool completed;
  final bool firstClear;
  final int timesCleared;

  const _NodeProgress({
    required this.completed,
    required this.firstClear,
    this.timesCleared = 0,
  });
}
