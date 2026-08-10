import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/systems/score_system.dart';
import '../models/card_growth.dart';
import '../models/card_values.dart';
import '../models/condition.dart';
import '../models/deck.dart';
import '../models/match_growth_result.dart';
import '../models/player_profile.dart';
import '../models/quest.dart';
import '../models/trainer_appearance.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/item_repository.dart';
import '../services/card_repository.dart';
import '../services/deck_service.dart';

/// Thin ChangeNotifier wrapper around the single [PlayerProfile], now
/// backed by the TTMMO API instead of local SharedPreferences. There is no
/// profile until [loadFromServer] succeeds (called from SessionLoaderScreen
/// right after login/register, or at app boot if already logged in) — no
/// screen reachable before that point reads [profile].
class PlayerProfileController extends ChangeNotifier {
  PlayerProfileController(this._apiClient, this.deckService);

  final ApiClient _apiClient;
  final DeckService deckService;

  PlayerProfile? _profile;
  Map<String, CardGrowth> _cardGrowth = {};
  List<CardGrowth> _allInstances = [];
  final Map<int, CardGrowth> _growthByInstance = {};
  /// Locally-applied healing overrides — maps instanceId → condition.
  /// Re-applied after server refresh to prevent stale server data overwrite.
  final Map<int, int> _localHeals = {};
  final List<Quest> _activeQuests = [];
  static const int _maxActiveQuests = 3;
  final Set<String> _completedQuestIds = {};
  final Set<int> _favoriteInstanceIds = {};
  final List<String> _boosterInventory = [];
  final Map<String, int> _consumableInventory = {};
  final Map<int, DateTime> _acquisitionTimes = {};

  PlayerProfile get profile => _profile!;

  /// Per-card XP/level/stat-bonus progress, keyed by card id (unique).
  Map<String, CardGrowth> get cardGrowth => _cardGrowth;

  /// All card instances (including multiples) for the collection view.
  List<CardGrowth> get allCardInstances => _allInstances;

  /// Growth data keyed by instanceId — accurate per-instance level/XP.
  Map<int, CardGrowth> get cardGrowthByInstance => _growthByInstance;

  /// The player's currently active quests (up to 3).
  List<Quest> get activeQuests => _activeQuests;

  /// The first active quest (for backward compatibility), or null if none.
  Quest? get activeQuest => _activeQuests.isNotEmpty ? _activeQuests.first : null;

  /// Whether a specific quest ID is active.
  bool isQuestActive(String questId) => _activeQuests.any((q) => q.id == questId);

  /// Whether a specific quest ID has been completed.
  bool isQuestCompleted(String questId) => _completedQuestIds.contains(questId);

  /// All completed quest IDs (read-only).
  Set<String> get completedQuestIds => Set.unmodifiable(_completedQuestIds);

  /// Favorite instance IDs (max 3).
  Set<int> get favoriteInstanceIds => _favoriteInstanceIds;

  /// Unopened booster packs in the player's inventory.
  List<String> get boosterInventory => List.unmodifiable(_boosterInventory);

  /// Whether an instance was acquired in the last 2 minutes.
  bool isNewInstance(int instanceId) {
    final time = _acquisitionTimes[instanceId];
    if (time == null) return false;
    return DateTime.now().difference(time).inMinutes < 2;
  }

  /// Gym badges earned by the player.
  Set<String> get badges => _profile?.badges ?? {};

  /// Award a gym badge.
  Future<void> awardBadge(String badgeId) async {
    if (_profile == null) return;
    if (_profile!.badges.add(badgeId)) {
      await _saveBadges();
      notifyListeners();
    }
  }

  Future<void> _saveBadges() async {
    if (_profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('badges', _profile!.badges.toList());
  }

  Future<void> _loadBadges() async {
    if (_profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('badges') ?? [];
    _profile!.badges.addAll(saved);
  }

  Future<void> _saveCompletedQuests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('completedQuests', _completedQuestIds.toList());
  }

  /// Clear all active and completed quests from memory (SharedPreferences
  /// are cleared separately by the caller).
  void clearQuests() {
    _activeQuests.clear();
    _completedQuestIds.clear();
    _consumableInventory.remove('oaks_parcel');
  }

  /// Remove a single quest from the completed set. Returns true if it was removed.
  bool uncompleteQuest(String questId) {
    final removed = _completedQuestIds.remove(questId);
    if (removed) {
      _saveCompletedQuests();
      notifyListeners();
    }
    return removed;
  }

  Future<void> _loadCompletedQuests() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('completedQuests') ?? [];
    _completedQuestIds.addAll(saved);
  }

  /// Consumable battle items (pokéballs, etc.) keyed by item ID.
  Map<String, int> get consumableInventory => Map.unmodifiable(_consumableInventory);

  /// Buy a booster pack into inventory. Deducts money and persists to the
  /// server; rolls back money on failure. Throws [ApiException] /
  /// [ApiNetworkException] on failure so the caller can show an error.
  Future<void> buyBoosterPack(String itemId, int price) async {
    if (profile.money < price) throw Exception('Not enough money');
    profile.money -= price;
    _boosterInventory.add(itemId);
    await _saveBoosterInventory();
    await _saveMoney();
    notifyListeners();
    // Try server sync, but don't block
    try {
      await _apiClient.buyInventoryItem(itemId, price);
    } catch (_) {}
  }

  void addBoosterToInventory(String itemId, int quantity) {
    for (var i = 0; i < quantity; i++) {
      _boosterInventory.add(itemId);
    }
    _saveBoosterInventory();
    notifyListeners();
  }

  /// Open a booster pack from inventory, removing it. Returns true if opened.
  Future<bool> openBoosterFromInventory(String boosterName) async {
    if (!_boosterInventory.contains(boosterName)) return false;
    _boosterInventory.remove(boosterName);
    notifyListeners();
    await _saveBoosterInventory();
    // Try server sync, but don't undo local state on failure
    try {
      await _apiClient.consumeInventoryItem(boosterName);
    } catch (_) {}
    return true;
  }

  // ── Consumable items (Pokéballs etc.) ──

  /// Add items to the consumable inventory.
  void addConsumable(String itemId, [int quantity = 1]) {
    _consumableInventory[itemId] = itemCount(itemId) + quantity;
    _saveConsumableInventory();
    notifyListeners();
  }

  /// Use one item. Returns true if successful (item existed).
  bool useConsumable(String itemId) {
    final current = _consumableInventory[itemId];
    if (current == null || current <= 0) return false;
    if (current == 1) {
      _consumableInventory.remove(itemId);
    } else {
      _consumableInventory[itemId] = current - 1;
    }
    _saveConsumableInventory();
    notifyListeners();
    // Sync to server in background
    _apiClient.consumeInventoryItem(itemId).catchError((_) {});
    return true;
  }

  /// How many of this item the player owns.
  int itemCount(String itemId) => _consumableInventory[itemId] ?? 0;

  Future<void> _saveConsumableInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = _consumableInventory.keys.toList();
    final values = keys.map((k) => _consumableInventory[k].toString()).toList();
    await prefs.setStringList('consumableKeys', keys);
    await prefs.setStringList('consumableValues', values);
  }

  Future<void> _loadConsumableInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('consumableKeys') ?? [];
    final values = prefs.getStringList('consumableValues') ?? [];
    _consumableInventory.clear();
    for (var i = 0; i < keys.length && i < values.length; i++) {
      _consumableInventory[keys[i]] = int.tryParse(values[i]) ?? 0;
    }
    notifyListeners();
  }

  // ── Persistence helpers ──

  Future<void> _saveBoosterInventory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('boosterInventory', _boosterInventory);
  }

  Future<void> _saveMoney() async {
    if (_profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('playerMoney', _profile!.money);
  }

  Future<int?> _loadMoney() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('playerMoney');
  }

  Future<void> _loadBoosterInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final localSaved = prefs.getStringList('boosterInventory') ?? [];
    // Filter out battle items that may have leaked into booster inventory
    final battleItemIds = {'pokeball', 'great_ball', 'ultra_ball', 'master_ball', 'potion'};
    final merged = <String>[...localSaved.where((id) => !battleItemIds.contains(id))];
    final consumableFromServer = <String, int>{};
    try {
      final serverItems = await _apiClient.getInventory();
      for (final raw in serverItems) {
        final map = raw as Map<String, dynamic>;
        final itemId = map['itemId'] as String;
        final quantity = map['quantity'] as int;
        // Consumables (pokéballs etc.) tracked in their own map
        if (itemId.contains('ball') || itemId == 'potion') {
          consumableFromServer[itemId] = quantity;
        } else {
          // Boosters are tracked as a flat list of IDs
          final localCount = merged.where((i) => i == itemId).length;
          if (localCount < quantity) {
            merged.addAll(List.filled(quantity - localCount, itemId));
          }
        }
      }
    } catch (_) {}
    _boosterInventory.clear();
    _boosterInventory.addAll(merged);
    await _saveBoosterInventory();

    // Merge server consumables with local
    for (final entry in consumableFromServer.entries) {
      final localCount = _consumableInventory[entry.key] ?? 0;
      if (entry.value > localCount) {
        _consumableInventory[entry.key] = entry.value;
      }
    }
    await _saveConsumableInventory();
  }

  /// Favorite card instances with full growth data for display.
  List<CardGrowth> get favoriteInstances => _allInstances
      .where((inst) => _favoriteInstanceIds.contains(inst.instanceId))
      .toList();

  /// The player's overall Trainer Level. Starts at 1 and increases as the
  /// player completes story nodes, captures Pokémon, and defeats trainers.
  int get trainerLevel {
    // Simple XP curve: level 1 at 0, level N requires (N-1)*100 XP
    var xp = _profile?.trainerXp ?? 0;
    var level = 1;
    while (xp >= level * 100) {
      xp -= level * 100;
      level++;
    }
    return level;
  }

  /// XP progress within the current trainer level (0..level*100).
  int get trainerXpInLevel {
    final xp = (_profile?.trainerXp ?? 0);
    var remaining = xp;
    for (var lv = 1; lv < trainerLevel; lv++) {
      remaining -= lv * 100;
    }
    return remaining.clamp(0, trainerXpForNextLevel);
  }

  /// Max XP needed to reach the next trainer level.
  int get trainerXpForNextLevel => trainerLevel * 100;

  /// Cards the player has seen or currently owns — union of persisted
  /// `seenCardIds` and current `_cardGrowth` keys.
  Set<String> get seenCardIds {
    final all = <String>{};
    all.addAll(_profile!.seenCardIds);
    all.addAll(_cardGrowth.keys);
    return all;
  }

  /// Cards the player has ever *owned* at any point (persisted locally).
  /// Used by the Card Dex for full-color unlock display.
  Set<String> get everOwnedCardIds {
    final all = <String>{};
    all.addAll(_profile!.everOwnedCardIds);
    all.addAll(_cardGrowth.keys);
    return all;
  }

  /// Cards the player has ever owned as *shiny* variants (persisted locally).
  /// Used by the Shiny Dex so evolved shinies are still remembered.
  Set<String> get everOwnedShinyCardIds {
    final all = <String>{};
    all.addAll(_profile!.everOwnedShinyCardIds);
    for (final inst in _allInstances) {
      if (inst.shiny) all.add(inst.cardId);
    }
    return all;
  }

  /// Mark a card as "seen" in the Pokédex (encountered in battle, etc.).
  void markCardSeen(String cardId) {
    if (_profile!.seenCardIds.add(cardId)) {
      _saveSeenCards();
      notifyListeners();
    }
  }

  Future<void> _saveSeenCards() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _profile!.seenCardIds.toList();
    await prefs.setStringList('seenCardIds', list);
    // Sync to server in background (fire-and-forget)
    _apiClient.putSeenCards(list).catchError((_) {});
  }

  Future<void> _loadSeenCards() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('seenCardIds');
    if (saved != null) {
      _profile!.seenCardIds.addAll(saved);
    }
  }

  Future<void> _saveEverOwnedCards() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('everOwnedCardIds', _profile!.everOwnedCardIds.toList());
  }

  Future<void> _saveEverOwnedShinyCards() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('everOwnedShinyCardIds', _profile!.everOwnedShinyCardIds.toList());
  }

  Future<void> _loadEverOwnedShinyCards() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('everOwnedShinyCardIds');
    if (saved != null) {
      _profile!.everOwnedShinyCardIds.addAll(saved);
    }
  }

  Future<void> _saveTrainerXp() async {
    if (_profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('trainerXp', _profile!.trainerXp);
    // Sync to server in background (fire-and-forget)
    _apiClient.updateTrainerXp(_profile!.trainerXp).catchError((_) {});
  }

  Future<int> _loadTrainerXpRaw() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('trainerXp') ?? 0;
  }

  Future<void> _loadTrainerXp() async {
    if (_profile != null) {
      _profile!.trainerXp = await _loadTrainerXpRaw();
    }
  }

  Future<void> _loadEverOwnedCards() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('everOwnedCardIds');
    if (saved != null) {
      _profile!.everOwnedCardIds.addAll(saved);
    }
  }

  /// Resolved TriadCard objects for backward-compatible UI (no instance data).
  List<TriadCard> get favoriteCards => favoriteInstances
      .map((inst) => CardRepository.instance.cardById(inst.cardId))
      .whereType<TriadCard>()
      .toList();

  /// Toggle an instance as favorite. Max 3. Returns true if toggled on, false if off.
  bool toggleFavorite(int instanceId) {
    if (_favoriteInstanceIds.contains(instanceId)) {
      _favoriteInstanceIds.remove(instanceId);
      _saveFavorites();
      notifyListeners();
      return false;
    } else if (_favoriteInstanceIds.length < 3) {
      _favoriteInstanceIds.add(instanceId);
      _saveFavorites();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'favoriteInstanceIds',
      _favoriteInstanceIds.map((e) => e.toString()).toList(),
    );
    // Sync to server in background
    try {
      await _apiClient.putFavorites(_favoriteInstanceIds.toList());
    } catch (_) {}
  }

  /// Sells a card instance for PokéDollars. Returns true on success.
  Future<bool> sellCardInstance(int instanceId, int price) async {
    final idx = _allInstances.indexWhere((i) => i.instanceId == instanceId);
    if (idx < 0) return false;
    final soldCardId = _allInstances[idx].cardId;
    _allInstances.removeAt(idx);
    // Update _cardGrowth if this was the last instance of this card
    final stillOwns = _allInstances.any((i) => i.cardId == soldCardId);
    if (!stillOwns) {
      _cardGrowth.remove(soldCardId);
      _growthByInstance.remove(instanceId);
    }
    _profile!.money += price;
    await _saveMoney();
    notifyListeners();
    // Try server sync
    try {
      await _apiClient.sellCard(instanceId, price);
    } catch (_) {}
    return true;
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    // Always keep local cache as fallback
    final localRaw = prefs.getStringList('favoriteInstanceIds');
    final localIds =
        localRaw
            ?.map((s) => int.tryParse(s) ?? 0)
            .where((id) => id > 0)
            .toList() ??
        [];
    // Try server, but never clear favorites if server returns empty
    List<int> ids = localIds;
    try {
      final serverIds = await _apiClient.getFavorites();
      if (serverIds.isNotEmpty) {
        ids = serverIds;
      }
    } catch (_) {
      // Keep local fallback
    }
    _favoriteInstanceIds.clear();
    _favoriteInstanceIds.addAll(ids);
    if (_favoriteInstanceIds.isNotEmpty) {
      await prefs.setStringList(
        'favoriteInstanceIds',
        _favoriteInstanceIds.map((e) => e.toString()).toList(),
      );
      notifyListeners();
    }
  }

  bool isFavorite(int instanceId) => _favoriteInstanceIds.contains(instanceId);

  /// Force-complete a quest, granting all rewards. Use this when rewards
  /// are deferred (e.g. player must click "Claim Rewards").
  void forceCompleteQuest(String questId) {
    final quest = _activeQuests.firstWhere((q) => q.id == questId);
    if (quest.completed) return;
    quest.completed = true;
    for (final obj in quest.objectives) {
      obj.completed = true;
    }
    _completedQuestIds.add(quest.id);
    _saveCompletedQuests();
    _profile!.money += quest.rewardMoney;
    if (quest.id == 'oaks_parcel') {
      _consumableInventory['pokeball'] = (_consumableInventory['pokeball'] ?? 0) + 10;
    }
    _saveActiveQuests();
    notifyListeners();
  }

  /// Mark a quest objective as completed by its description text.
  /// Searches all active quests.
  void completeObjective(String description) {
    for (final quest in _activeQuests.toList()) {
      if (quest.completed) continue;
      for (final obj in quest.objectives) {
        if (obj.description == description && !obj.completed) {
          obj.completed = true;
          if (quest.allObjectivesDone) {
            quest.completed = true;
            _completedQuestIds.add(quest.id);
            _saveCompletedQuests();
            _profile!.money += quest.rewardMoney;
            if (quest.id == 'oaks_parcel') {
              _consumableInventory['pokeball'] = (_consumableInventory['pokeball'] ?? 0) + 10;
            }
          }
          _saveActiveQuests();
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Start a new quest. If 3 are already active, replaces the oldest completed one.
  void startQuest(Quest quest) {
    // Don't add if already active
    if (_activeQuests.any((q) => q.id == quest.id)) return;
    // Remove completed quests to make room
    _activeQuests.removeWhere((q) => q.completed);
    // If still full, remove the oldest
    if (_activeQuests.length >= _maxActiveQuests) {
      _activeQuests.removeAt(0);
    }
    _activeQuests.add(quest);
    _saveActiveQuests();
    notifyListeners();
  }

  Future<void> _saveActiveQuests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeQuests', jsonEncode(_activeQuests.map((q) => q.toJson()).toList()));
  }

  Future<void> _loadActiveQuests() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('activeQuests');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _activeQuests.clear();
        _activeQuests.addAll(list.map((j) => Quest.fromJson(j as Map<String, dynamic>)));
        return;
      } catch (_) {}
    }
    // Migration: load from old single-quest format
    final oldRaw = prefs.getString('activeQuest');
    if (oldRaw != null) {
      try {
        final oldQuest = Quest.fromJson(jsonDecode(oldRaw) as Map<String, dynamic>);
        _activeQuests.add(oldQuest);
        await prefs.remove('activeQuest'); // clean up old key
      } catch (_) {}
    }
  }

  /// Initialize the starting quest for new players.
  void initNewPlayerQuests() {
    // No default quest — quests start from story interactions.
  }

  /// Check if Oak's parcel quest has already been introduced.
  Future<bool> hasSeenParcelQuest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('oak_parcel_seen') ?? false;
  }

  /// Mark Oak's parcel quest as introduced and start it.
  Future<void> startParcelQuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('oak_parcel_seen', true);
    startQuest(QuestData.oaksParcel);
  }

  /// Reset the parcel quest flag and active quests (for testing).
  Future<void> resetParcelQuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('oak_parcel_seen');
    _activeQuests.clear();
    await _saveActiveQuests();
    notifyListeners();
  }

  Future<void> loadFromServer() async {
    final me = await _apiClient.getMe();
    final deckMaps = await _apiClient.getDecks();

    // The live TTMMO catalog can contain more cards (trainer cards, variant
    // ids) than this app's bundled snapshot — drop anything not locally
    // known rather than let it reach Collection/Deck Builder as a dead id.
    final knownIds = CardRepository.instance.allCardIds.toSet();
    final ownedCardIds = (me['ownedCardIds'] as List<dynamic>)
        .cast<String>()
        .where(knownIds.contains)
        .toSet();

    final decks = deckMaps
        .map((d) => Deck.fromJson(d as Map<String, dynamic>))
        .toList();
    final defaultDeck = decks.where((d) => d.isDefault).firstOrNull;

    // Fall back to locally-saved default deck if server doesn't have one
    String? defaultId = defaultDeck?.id;
    if (defaultId == null) {
      final prefs = await SharedPreferences.getInstance();
      defaultId = prefs.getString('defaultDeckId');
      // Verify the saved id still exists in the player's decks
      if (defaultId != null && !decks.any((d) => d.id == defaultId)) {
        defaultId = null;
      }
    }

    _profile = PlayerProfile(
      playerName: me['playerName'] as String,
      ownedCardIds: ownedCardIds,
      decks: decks,
      defaultDeckId: defaultId,
      wins: me['wins'] as int? ?? 0,
      losses: me['losses'] as int? ?? 0,
      draws: me['draws'] as int? ?? 0,
      money: me['money'] as int? ?? 0,
      joinedAt: me['joinedAt'] as String?,
      trainerName: me['trainerName'] as String?,
      gender: me['gender'] as String?,
      skinTone: me['skinTone'] as String?,
      hairPath: me['hairPath'] as String?,
      topPath: me['topPath'] as String?,
      bottomPath: me['bottomPath'] as String?,
      hatPath: me['hatPath'] as String?,
      friendCode: me['friendCode'] as String?,
      location: me['location'] as String? ?? 'Pallet Town',
      unlockedDeckBoxes: me['unlockedDeckBoxes'] != null
          ? (me['unlockedDeckBoxes'] as List<dynamic>).cast<String>().toSet()
          : null,
    );
    _profile!.giftCount = (me['giftCount'] as int?) ?? 0;
    // Use the greater of server money and locally-saved money so we never
    // lose PokéDollars from a failed server sync (e.g. selling cards).
    final localMoney = await _loadMoney();
    if (localMoney != null && localMoney > _profile!.money) {
      _profile!.money = localMoney;
    }
    await _saveMoney();
    // Seed seen cards & ever-owned: owning a card implies having seen it.
    _profile!.seenCardIds.addAll(ownedCardIds);
    _profile!.everOwnedCardIds.addAll(ownedCardIds);
    // Merge server-side seen cards (survives across devices)
    final serverSeen = (me['seenCardIds'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toSet();
    if (serverSeen != null) {
      _profile!.seenCardIds.addAll(serverSeen);
    }
    await _loadSeenCards();
    await _loadEverOwnedCards();
    await _loadEverOwnedShinyCards();
    // trainerXp: take the larger of server and local (survives reinstall)
    final serverXp = (me['trainerXp'] as int?) ?? 0;
    final localXp = await _loadTrainerXpRaw();
    _profile!.trainerXp = serverXp > localXp ? serverXp : localXp;
    await _saveTrainerXp(); // persist the merged value locally
    // Persist immediately so cards survive evolutions and app restarts.
    await _saveSeenCards();
    await _saveEverOwnedCards();
    await _loadFavorites();
    await _loadConsumableInventory();  // local first
    await _loadBadges();
    await _loadCompletedQuests();
    await _loadActiveQuests();
    await _loadBoosterInventory();     // then server (merges consumables on top)
    await _refreshCardGrowth();

    // ── Starter Kit: 3000 ₽ + 5 Field Trip Boosters (one-time) ──
    final prefs = await SharedPreferences.getInstance();
    final granted = prefs.getBool('starterKitGranted') ?? false;
    if (!granted) {
      if (_profile!.money < 3000) {
        _profile!.money = 3000;
      }
      for (var i = 0; i < 5; i++) {
        _boosterInventory.add('field_trip');
      }
      // Starter pokéballs: 5 standard, 2 great, 1 ultra
      _consumableInventory['pokeball'] = 5;
      _consumableInventory['great_ball'] = 2;
      _consumableInventory['ultra_ball'] = 1;
      // Starter potions so Condition recovery is usable right away
      _consumableInventory['potion'] = 3;
      _consumableInventory['super_potion'] = 1;
      await _saveBoosterInventory();
      await _saveConsumableInventory();
      await prefs.setBool('starterKitGranted', true);
      notifyListeners();
    }

    // Auto-create a starter deck if player has cards but no decks
    if (_profile!.decks.isEmpty && ownedCardIds.isNotEmpty) {
      final pokemonIds = ownedCardIds
          .map((id) => CardRepository.instance.cardById(id))
          .whereType<TriadCard>()
          .where((c) => c.cardType == TriadCardType.pokemon)
          .take(5)
          .map((c) => c.id)
          .toList();
      if (pokemonIds.isNotEmpty) {
        final deck = Deck(
          id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Starter Deck',
          cardIds: pokemonIds,
          isDefault: true,
        );
        try {
          await deckService.saveDeck(_profile!, deck);
          await deckService.setDefaultDeck(_profile!, deck.id);
          _profile!.defaultDeckId = deck.id;
        } catch (_) {
          // Add locally if server save fails
          _profile!.decks.add(deck);
          _profile!.defaultDeckId = deck.id;
        }
      }
    }

    notifyListeners();
  }

  Future<void> saveDeck(Deck deck) async {
    await deckService.saveDeck(_profile!, deck);
    notifyListeners();
  }

  Future<void> unlockDeckBox(String boxKey) async {
    if (_profile!.unlockedDeckBoxes.add(boxKey)) {
      await _apiClient.putUnlockedDeckBoxes(_profile!.unlockedDeckBoxes.toList());
      notifyListeners();
    }
  }

  Future<void> createDeck(String name, List<String> cardIds) async {
    final isFirstDeck = _profile!.decks.isEmpty;
    final deck = Deck(
      id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      cardIds: cardIds,
      isDefault: isFirstDeck,
    );
    // Add locally first so UI reacts immediately, then persist to server
    _profile!.decks.add(deck);
    _profile!.ownedCardIds.addAll(cardIds);
    // Initialize card growth for new cards
    for (final id in cardIds) {
      _cardGrowth.putIfAbsent(
        id,
        () => CardGrowth(
          cardId: id,
          xp: 0,
          level: 0,
          bonusNorth: 0,
          bonusSouth: 0,
          bonusEast: 0,
          bonusWest: 0,
        ),
      );
    }
    // Set as default if it's the first deck
    if (isFirstDeck) {
      _profile!.defaultDeckId = deck.id;
    }
    notifyListeners();

    try {
      await deckService.saveDeck(_profile!, deck);
      // Also activate as default on server if first deck
      if (isFirstDeck) {
        await deckService.setDefaultDeck(_profile!, deck.id);
      }
    } catch (_) {
      // Deck is already in the local profile — server sync can catch up later
    }
  }

  Future<void> deleteDeck(String deckId) async {
    await deckService.deleteDeck(_profile!, deckId);
    notifyListeners();
  }

  Future<void> setDefaultDeck(String deckId) async {
    _profile!.defaultDeckId = deckId;
    notifyListeners();
    // Fire-and-forget server sync
    deckService.setDefaultDeck(_profile!, deckId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultDeckId', deckId);
  }

  /// Saves the Professor Oak character-creation result, then refreshes the
  /// profile so [PlayerProfile.trainerName] reflects it immediately.
  Future<void> saveCharacter(TrainerAppearance appearance) async {
    await _apiClient.putCharacter(appearance.toJson());
    await loadFromServer();
  }

  /// Records the match outcome and awards growth XP.
  /// [captureXp] is the legacy per-instance total (for backward compat).
  /// [cardXpBreakdown] is the new detailed per-source XP breakdown.
  /// Returns the resulting XP/level-ups and any cards that just became
  /// eligible to evolve so the caller (ResultsScreen) can show them.
  Future<MatchGrowthResult> recordMatchResult(
    MatchOutcome outcome, {
    Map<int, int> captureXp = const {},
    Map<String, int> captureCounts = const {},
    List<String>? deckCardIds,
    List<int?>? deckInstanceIds,
    Map<int, Map<String, dynamic>>? cardXpBreakdown,
    Map<int, int> conditionLoss = const {},
    List<Map<String, dynamic>> capturedCards = const [],
    int opponentTotalPower = 40, // sum of all opponent card values
  }) async {
    final outcomeStr = switch (outcome) {
      MatchOutcome.win => 'win',
      MatchOutcome.loss => 'loss',
      MatchOutcome.draw => 'draw',
    };

    debugPrint(
      '[XP] recordMatchResult: captureXp=$captureXp, captureCounts=$captureCounts, deckInstIds=$deckInstanceIds',
    );

    // If instance-level XP is empty but we have card-level captures, resolve instances
    var effectiveCaptureXp = Map<int, int>.from(captureXp);
    if (effectiveCaptureXp.isEmpty && captureCounts.isNotEmpty) {
      debugPrint(
        '[XP] captureXp empty, falling back to captureCounts (allInstances=${_allInstances.length})',
      );
      for (final entry in captureCounts.entries) {
        // Find all owned instances of this card and give XP to the best one
        final best = _allInstances
            .where((inst) => inst.cardId == entry.key)
            .toList();
        debugPrint(
          '[XP]   cardId=${entry.key}: found ${best.length} instances',
        );
        if (best.isNotEmpty) {
          // Give XP to the highest-level instance (most likely the one in the deck)
          best.sort((a, b) => b.level.compareTo(a.level));
          final target = best.first;
          if (target.instanceId != null) {
            effectiveCaptureXp[target.instanceId!] =
                entry.value * 5; // default 5 XP per capture
            debugPrint(
              '[XP]   → instanceId=${target.instanceId}, xp=${entry.value * 5}',
            );
          }
        }
      }
    }

    debugPrint(
      '[XP] effectiveCaptureXp=$effectiveCaptureXp, bonusXp pending...',
    );

    // Win bonus: 1-3 random deck cards get 10-30 XP each
    final bonusXp = <int, int>{};
    if (outcome == MatchOutcome.win &&
        deckInstanceIds != null &&
        deckInstanceIds.isNotEmpty) {
      final valid = deckInstanceIds
          .where((id) => id != null && id > 0)
          .toList();
      if (valid.isNotEmpty) {
        final rng = _rng();
        final bonusCount = (rng % 3) + 1;
        valid.shuffle();
        for (var i = 0; i < bonusCount && i < valid.length; i++) {
          bonusXp[valid[i]!] = ((rng >> (i * 5)) % 21) + 10;
        }
      }
    }

    Map<String, dynamic>? result;
    try {
      debugPrint(
        '[XP] posting match result: captureXp=$effectiveCaptureXp, bonusXp=$bonusXp, cardXp=$cardXpBreakdown',
      );
      result = await _apiClient.postMatchResult(
        outcomeStr,
        captureXp: effectiveCaptureXp,
        bonusXp: bonusXp,
        cardXp: cardXpBreakdown,
        conditionLoss: conditionLoss,
        capturedCards: capturedCards,
      );
      debugPrint('[XP] server response: $result');
    } catch (e) {
      debugPrint('[XP] postMatchResult FAILED: $e');
      // Server unreachable — still update local counters
    }
    // Trainer XP scales with opponent strength: sum of all opponent card values × 2
    final earnedTrainerXp = opponentTotalPower * 2;
    switch (outcome) {
      case MatchOutcome.win:
        _profile!.wins++;
        _profile!.trainerXp = (_profile!.trainerXp) + earnedTrainerXp;
        _saveTrainerXp();
        break;
      case MatchOutcome.loss:
        _profile!.losses++;
        _profile!.trainerXp = (_profile!.trainerXp) + (earnedTrainerXp ~/ 3); // 1/3 XP for loss
        _saveTrainerXp();
        break;
      case MatchOutcome.draw:
        _profile!.draws++;
        _profile!.trainerXp = (_profile!.trainerXp) + (earnedTrainerXp ~/ 2); // 1/2 XP for draw
        _saveTrainerXp();
        break;
    }
    // Always refresh card growth after a match so the server's XP state is pulled
    bool growthRefreshed = false;
    if (result != null) {
      debugPrint('[XP] calling _refreshCardGrowth...');
      try {
        await _refreshCardGrowth();
        growthRefreshed = true;
        debugPrint('[XP] _refreshCardGrowth completed');
      } catch (e) {
        debugPrint('[XP] _refreshCardGrowth FAILED: $e');
      }
    } else {
      debugPrint('[XP] skipping _refreshCardGrowth (server call failed)');
    }

    if (result == null) {
      notifyListeners();
      return MatchGrowthResult(
        growth: [],
        pendingEvolutions: [],
        trainerXpEarned: earnedTrainerXp,
      );
    }
    final growthResult = MatchGrowthResult.fromJson(
      result as Map<String, dynamic>,
    );

    // If _refreshCardGrowth didn't run (network error), apply XP directly
    // from the postMatchResult response as a fallback.
    if (!growthRefreshed) {
      final updatedInstances = List<CardGrowth>.from(_allInstances);
      for (final g in growthResult.growth) {
        if (g.instanceId == null) continue;
        final idx = updatedInstances.indexWhere(
          (i) => i.instanceId == g.instanceId,
        );
        if (idx >= 0) {
          final old = updatedInstances[idx];
          updatedInstances[idx] = CardGrowth(
            cardId: old.cardId,
            xp: old.xp + g.xpGained,
            level: g.leveledUp ? g.newLevel : old.level,
            bonusNorth: old.bonusNorth,
            bonusSouth: old.bonusSouth,
            bonusEast: old.bonusEast,
            bonusWest: old.bonusWest,
            shiny: old.shiny,
            source: old.source,
            instanceId: old.instanceId,
            condition: old.condition,
          );
        }
      }
      _allInstances = updatedInstances;
      final newGrowth = <String, CardGrowth>{};
      for (final inst in _allInstances) {
        final existing = newGrowth[inst.cardId];
        if (existing == null || inst.level > existing.level) {
          newGrowth[inst.cardId] = inst;
        }
        if (inst.instanceId != null) {
          _growthByInstance[inst.instanceId!] = inst;
        }
      }
      _cardGrowth = newGrowth;
    }
    notifyListeners();

    // Attach bonus XP info (cardId → amount) for results screen display
    if (bonusXp.isNotEmpty) {
      final bonusMap = <String, int>{};
      for (final entry in bonusXp.entries) {
        final inst = _allInstances
            .where((i) => i.instanceId == entry.key)
            .firstOrNull;
        if (inst != null) {
          bonusMap[inst.cardId] = (bonusMap[inst.cardId] ?? 0) + entry.value;
        }
      }
      return MatchGrowthResult(
        growth: growthResult.growth,
        pendingEvolutions: growthResult.pendingEvolutions,
        bonusXp: bonusMap,
        trainerXpEarned: earnedTrainerXp,
      );
    }
    return MatchGrowthResult(
      growth: growthResult.growth,
      pendingEvolutions: growthResult.pendingEvolutions,
      bonusXp: growthResult.bonusXp,
      trainerXpEarned: earnedTrainerXp,
    );
  }

  /// Simple PRNG for bonus XP distribution (deterministic per match).
  int _rng() => DateTime.now().microsecondsSinceEpoch ~/ 1000;

  /// Evolves the card and returns its new N/S/E/W leveling bonus — evolving
  /// randomly trims each stat's bonus rather than carrying it over intact,
  /// so callers (the evolution animation) need the real post-evolve value
  /// rather than assuming the pre-evolve bonus still applies.
  Future<CardValues?> evolveCard(
    String cardId,
    String toId, {
    int? instanceId,
  }) async {
    final result = await _apiClient.postEvolve(
      cardId,
      toId,
      instanceId: instanceId,
    );
    await loadFromServer();
    final newBonuses = result['newBonuses'] as Map<String, dynamic>?;
    if (newBonuses == null) return null;
    return CardValues(
      north: newBonuses['north'] as int? ?? 0,
      south: newBonuses['south'] as int? ?? 0,
      east: newBonuses['east'] as int? ?? 0,
      west: newBonuses['west'] as int? ?? 0,
    );
  }

  Future<void> addBoosterCards(List<Map<String, dynamic>> cards) async {
    // Add card IDs to local state immediately
    final cardIds = cards.map((c) => c['cardId'] as String).toList();
    _profile!.ownedCardIds.addAll(cardIds);
    _profile!.seenCardIds.addAll(cardIds);
    _profile!.everOwnedCardIds.addAll(cardIds);
    notifyListeners();

    try {
      await _apiClient.addBoosterCards(cards);
    } catch (_) {
      // Server sync failed, but cards are already saved locally
    }
    // Refresh from server to get instance IDs and growth data
    await _refreshCardGrowth();
    await _saveSeenCards();
    await _saveEverOwnedCards();
  }

  /// Public wrapper for refreshing card growth from the server
  /// without posting a new match result. Used after evolutions, etc.
  Future<void> refreshCardGrowth() async {
    await _refreshCardGrowth();
  }

  /// Pokémon Center: free full Condition restore for every owned card
  /// (GDD §15).
  Future<void> restoreAllCondition() async {
    await _apiClient.restoreAllCondition();
    await _refreshCardGrowth();
  }

  /// Restore Condition for specific card instances only.
  Future<void> restoreCards(List<int> instanceIds) async {
    await _apiClient.restoreAllCondition(instanceIds: instanceIds);
    await _refreshCardGrowth();
  }

  /// Consumes one [itemId] potion to restore Condition on the owned card
  /// instance [instanceId] (GDD §16). Also decrements the local consumable
  /// count so the Items screen reflects the spend immediately.
  Future<void> usePotionOnCard(String itemId, int instanceId) async {
    final item = ItemRepository().itemById(itemId);
    final restoreAmount = item?.restoreAmount ?? 20;

    // Apply locally (server may be unavailable)
    final inst = _growthByInstance[instanceId];
    if (inst != null) {
      final newCond = (inst.condition + restoreAmount).clamp(0, kMaxCondition);
      final healed = CardGrowth(
        cardId: inst.cardId, xp: inst.xp, level: inst.level,
        bonusNorth: inst.bonusNorth, bonusSouth: inst.bonusSouth,
        bonusEast: inst.bonusEast, bonusWest: inst.bonusWest,
        source: inst.source, shiny: inst.shiny,
        instanceId: inst.instanceId, condition: newCond,
        reverseHolo: inst.reverseHolo,
      );
      _growthByInstance[instanceId] = healed;
      _cardGrowth[inst.cardId] = healed;
      final idx = _allInstances.indexWhere((i) => i.instanceId == instanceId);
      if (idx >= 0) _allInstances[idx] = healed;
      _localHeals[instanceId] = newCond;
    }

    // Deduct potion immediately (don't wait for server)
    final current = _consumableInventory[itemId];
    if (current != null && current > 0) {
      if (current <= 1) {
        _consumableInventory.remove(itemId);
      } else {
        _consumableInventory[itemId] = current - 1;
      }
      await _saveConsumableInventory();
    }
    notifyListeners();

    // Sync to server in background — clear local heal on success
    _apiClient.usePotion(itemId, instanceId).then((_) {
      _localHeals.remove(instanceId);
    }).catchError((_) {
      // Server unreachable — heal stays in _localHeals
    });
  }

  Future<void> _refreshCardGrowth() async {
    final rows = await _apiClient.getCardGrowth();
    debugPrint(
      '[XP] _refreshCardGrowth: got ${rows.length} card rows from server',
    );
    final knownCardIds = CardRepository.instance.allCardIds.toSet();
    final growth = <String, CardGrowth>{};
    final instances = <CardGrowth>[];
    var skipped = 0;
    for (final row in rows) {
      final entry = CardGrowth.fromJson(row as Map<String, dynamic>);
      instances.add(entry);
      if (entry.instanceId != null) {
        _growthByInstance[entry.instanceId!] = entry;
      }
      final existing = growth[entry.cardId];
      // Prefer shiny, then highest level, then most recent instance
      if (existing == null) {
        growth[entry.cardId] = entry;
      } else if (entry.shiny && !existing.shiny) {
        growth[entry.cardId] = entry;
      } else if (entry.shiny == existing.shiny && entry.level > existing.level) {
        growth[entry.cardId] = entry;
      }
    }
    if (skipped > 0) {
      debugPrint('[XP] skipped $skipped unknown cards');
    }
    _cardGrowth = growth;
    final oldIds = _allInstances.map((e) => e.instanceId).toSet();
    _allInstances = instances;
    // Only track new acquisitions if we had previous data (skip first load)
    if (oldIds.isNotEmpty) {
      final now = DateTime.now();
      for (final inst in instances) {
        if (inst.instanceId != null && !oldIds.contains(inst.instanceId)) {
          _acquisitionTimes[inst.instanceId!] = now;
        }
      }
      _acquisitionTimes.removeWhere((_, t) => now.difference(t).inMinutes > 5);
    }

    // Persist every card we currently own into `seenCardIds`,
    // `everOwnedCardIds`, and (for shinies) `everOwnedShinyCardIds`.
    if (_profile != null) {
      final seenBefore = _profile!.seenCardIds.length;
      final ownedBefore = _profile!.everOwnedCardIds.length;
      final shinyBefore = _profile!.everOwnedShinyCardIds.length;
      _profile!.seenCardIds.addAll(growth.keys);
      _profile!.everOwnedCardIds.addAll(growth.keys);
      for (final inst in instances) {
        if (inst.shiny) {
          _profile!.everOwnedShinyCardIds.add(inst.cardId);
        }
      }
      if (_profile!.seenCardIds.length > seenBefore) {
        await _saveSeenCards();
      }
      if (_profile!.everOwnedCardIds.length > ownedBefore) {
        await _saveEverOwnedCards();
      }
      if (_profile!.everOwnedShinyCardIds.length > shinyBefore) {
        await _saveEverOwnedShinyCards();
      }
    }

    // Re-apply any local heals that the server hasn't synced yet
    for (final entry in _localHeals.entries) {
      final inst = _growthByInstance[entry.key];
      if (inst != null && inst.condition < entry.value) {
        final healed = CardGrowth(
          cardId: inst.cardId, xp: inst.xp, level: inst.level,
          bonusNorth: inst.bonusNorth, bonusSouth: inst.bonusSouth,
          bonusEast: inst.bonusEast, bonusWest: inst.bonusWest,
          source: inst.source, shiny: inst.shiny,
          instanceId: inst.instanceId, condition: entry.value,
          reverseHolo: inst.reverseHolo,
        );
        _growthByInstance[entry.key] = healed;
        _cardGrowth[inst.cardId] = healed;
        final idx = _allInstances.indexWhere((i) => i.instanceId == entry.key);
        if (idx >= 0) _allInstances[idx] = healed;
      }
    }

    // Log a few instances for debugging
    for (final inst in instances.take(5)) {
      debugPrint(
        '[XP]   instance ${inst.instanceId} cardId=${inst.cardId} xp=${inst.xp} level=${inst.level}',
      );
    }
    if (instances.length > 5)
      debugPrint('[XP]   ... and ${instances.length - 5} more');

    notifyListeners();
  }
}
