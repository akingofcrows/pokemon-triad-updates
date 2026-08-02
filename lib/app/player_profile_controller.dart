import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/systems/score_system.dart';
import '../models/card_growth.dart';
import '../models/card_values.dart';
import '../models/deck.dart';
import '../models/match_growth_result.dart';
import '../models/player_profile.dart';
import '../models/quest.dart';
import '../models/trainer_appearance.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
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
  Quest? _activeQuest;
  final Set<int> _favoriteInstanceIds = {};
  final List<String> _boosterInventory = [];

  PlayerProfile get profile => _profile!;

  /// Per-card XP/level/stat-bonus progress, keyed by card id (unique).
  Map<String, CardGrowth> get cardGrowth => _cardGrowth;

  /// All card instances (including multiples) for the collection view.
  List<CardGrowth> get allCardInstances => _allInstances;

  /// The player's currently active quest, or null if none.
  Quest? get activeQuest => _activeQuest;

  /// Favorite instance IDs (max 3).
  Set<int> get favoriteInstanceIds => _favoriteInstanceIds;

  /// Unopened booster packs in the player's inventory.
  List<String> get boosterInventory => List.unmodifiable(_boosterInventory);

  /// Add a booster pack to inventory (does not open it).
  Future<void> addBoosterToInventory(String boosterName) async {
    _boosterInventory.add(boosterName);
    await _saveBoosterInventory();
    notifyListeners();
  }

  /// Open a booster pack from inventory, removing it. Returns true if opened.
  Future<bool> openBoosterFromInventory(String boosterName) async {
    if (_boosterInventory.remove(boosterName)) {
      await _saveBoosterInventory();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> _saveBoosterInventory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('boosterInventory', _boosterInventory);
  }

  Future<void> _loadBoosterInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('boosterInventory');
    if (saved != null) {
      _boosterInventory.clear();
      _boosterInventory.addAll(saved);
    }
  }

  /// Favorite card instances with full growth data for display.
  List<CardGrowth> get favoriteInstances => _allInstances
      .where((inst) => _favoriteInstanceIds.contains(inst.instanceId))
      .toList();

  /// The player's overall Trainer Level. Starts at 1 and increases as the
  /// player completes story nodes, captures Pokémon, and defeats trainers.
  int get trainerLevel => 1; // TODO: compute from story progress + achievements

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

  /// Mark a quest objective as completed by its description text.
  void completeObjective(String description) {
    if (_activeQuest == null || _activeQuest!.completed) return;
    for (final obj in _activeQuest!.objectives) {
      if (obj.description == description && !obj.completed) {
        obj.completed = true;
        if (_activeQuest!.allObjectivesDone) {
          _activeQuest!.completed = true;
          _profile!.money += _activeQuest!.rewardMoney;
        }
        notifyListeners();
        return;
      }
    }
  }

  /// Start a new quest (completes any currently active one if not done).
  void startQuest(Quest quest) {
    _activeQuest = quest;
    notifyListeners();
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
    _activeQuest = QuestData.oaksParcel;
    notifyListeners();
  }

  /// Reset the parcel quest flag and active quest (for testing).
  Future<void> resetParcelQuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('oak_parcel_seen');
    _activeQuest = null;
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
    );
    _profile!.giftCount = (me['giftCount'] as int?) ?? 0;
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
    // Persist immediately so cards survive evolutions and app restarts.
    await _saveSeenCards();
    await _saveEverOwnedCards();
    await _loadFavorites();
    await _loadBoosterInventory();
    await _refreshCardGrowth();

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
    await deckService.setDefaultDeck(_profile!, deckId);
    // Persist locally so it survives server restarts
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultDeckId', deckId);
    notifyListeners();
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
    List<Map<String, dynamic>> capturedCards = const [],
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

    // ── Always apply XP locally first (from cardXp breakdown) ──────────
    // This ensures the UI shows XP immediately, even if the server call fails.
    if (cardXpBreakdown != null && cardXpBreakdown.isNotEmpty) {
      final updated = List<CardGrowth>.from(_allInstances);
      for (final entry in cardXpBreakdown.entries) {
        final instId = entry.key;
        final data = entry.value;
        final addedXp = (data['totalXp'] as int?) ?? 0;
        if (addedXp <= 0) continue;
        final idx = updated.indexWhere((i) => i.instanceId == instId);
        if (idx >= 0) {
          final old = updated[idx];
          updated[idx] = CardGrowth(
            cardId: old.cardId,
            xp: old.xp + addedXp,
            level: old.level, // server recalculates this
            bonusNorth: old.bonusNorth,
            bonusSouth: old.bonusSouth,
            bonusEast: old.bonusEast,
            bonusWest: old.bonusWest,
            shiny: old.shiny,
            source: old.source,
            instanceId: old.instanceId,
          );
          debugPrint(
            '[XP] local: +${addedXp}xp to instance $instId (${old.cardId}) → ${old.xp + addedXp}xp',
          );
        }
      }
      _allInstances = updated;
      final ng = <String, CardGrowth>{};
      for (final inst in _allInstances) {
        final ex = ng[inst.cardId];
        if (ex == null || inst.level > ex.level) ng[inst.cardId] = inst;
      }
      _cardGrowth = ng;
      notifyListeners();
    }

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
        capturedCards: capturedCards,
      );
      debugPrint('[XP] server response: $result');
    } catch (e) {
      debugPrint('[XP] postMatchResult FAILED: $e');
      // Server unreachable — still update local counters
    }
    switch (outcome) {
      case MatchOutcome.win:
        _profile!.wins++;
      case MatchOutcome.loss:
        _profile!.losses++;
      case MatchOutcome.draw:
        _profile!.draws++;
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
      return const MatchGrowthResult(growth: [], pendingEvolutions: []);
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
      );
    }
    return growthResult;
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
    await _apiClient.addBoosterCards(cards);
    await loadFromServer();
  }

  Future<void> _refreshCardGrowth() async {
    final rows = await _apiClient.getCardGrowth();
    debugPrint(
      '[XP] _refreshCardGrowth: got ${rows.length} card rows from server',
    );
    final growth = <String, CardGrowth>{};
    final instances = <CardGrowth>[];
    for (final row in rows) {
      final entry = CardGrowth.fromJson(row as Map<String, dynamic>);
      instances.add(entry);
      final existing = growth[entry.cardId];
      if (existing == null || entry.level > existing.level) {
        growth[entry.cardId] = entry;
      }
    }
    _cardGrowth = growth;
    _allInstances = instances;

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

    // Log a few instances for debugging
    for (final inst in instances.take(5)) {
      debugPrint(
        '[XP]   instance ${inst.instanceId} cardId=${inst.cardId} xp=${inst.xp} level=${inst.level}',
      );
    }
    if (instances.length > 5)
      debugPrint('[XP]   ... and ${instances.length - 5} more');
  }
}
