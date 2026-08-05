import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

/// A non-2xx response from the TTMMO API (e.g. bad credentials, validation
/// error) — distinct from [ApiNetworkException] so the UI can tell "wrong
/// password" apart from "server unreachable".
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The request never reached the server (unreachable, timed out, DNS, etc).
class ApiNetworkException implements Exception {
  ApiNetworkException(this.message);

  final String message;

  @override
  String toString() => 'ApiNetworkException: $message';
}

/// Thin HTTP client for the TTMMO backend's new API server.
/// The base URL is stored in SharedPreferences so it can be changed
/// from the Settings screen on device without rebuilding.
class ApiClient {
  ApiClient({required this.tokenProvider, required this.baseUrlProvider});

  final Future<String?> Function() tokenProvider;
  final Future<String> Function() baseUrlProvider;

  Future<Map<String, String>> _headers({bool authorized = true}) async {
    final headers = {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'User-Agent': 'PokemonTriad/1.0',
    };
    if (authorized) {
      final token = await tokenProvider();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 8));
    } catch (e) {
      throw ApiNetworkException('Could not reach the server: $e');
    }

    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(response.statusCode, 'Server returned an invalid response (HTTP ${response.statusCode}).');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    final message =
        (body is Map && body['error'] is String) ? body['error'] as String : 'Request failed (${response.statusCode}).';
    throw ApiException(response.statusCode, message);
  }

  Future<Map<String, dynamic>> register(String username, String password) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/register'),
        headers: await _headers(authorized: false),
        body: jsonEncode({'username': username, 'password': password}),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/login'),
        headers: await _headers(authorized: false),
        body: jsonEncode({'username': username, 'password': password}),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/me'), headers: await _headers()),
    );
    return result as Map<String, dynamic>;
  }

  Future<void> putCharacter(Map<String, dynamic> characterJson) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.put(
        Uri.parse('$baseUrl/me/character'),
        headers: await _headers(),
        body: jsonEncode(characterJson),
      ),
    );
  }

  Future<void> updateLocation(String location) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.put(
        Uri.parse('$baseUrl/me/location'),
        headers: await _headers(),
        body: jsonEncode({'location': location}),
      ),
    );
  }

  /// Get the player's story mode progress for all locations.
  Future<Map<String, dynamic>> getStoryProgress() async {
    final baseUrl = await baseUrlProvider();
    final response = await _send(
      () async => http.get(
        Uri.parse('$baseUrl/me/story'),
        headers: await _headers(),
      ),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Mark a story node as completed on the server.
  /// Mark a story node as completed on the server.
  Future<void> completeStoryNode(String locationId, String nodeId) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/story/node-complete'),
        headers: await _headers(),
        body: jsonEncode({
          'locationId': locationId,
          'nodeId': nodeId,
        }),
      ),
    );
  }

  /// Add cards from a booster pack to the player's collection.
  Future<void> addBoosterCards(List<Map<String, dynamic>> cards) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/open-booster'),
        headers: await _headers(),
        body: jsonEncode({'cards': cards}),
      ),
    );
  }

  /// Sync the player's seen card IDs to the server.
  Future<void> putSeenCards(List<String> seenCardIds) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.put(
        Uri.parse('$baseUrl/me/seen-cards'),
        headers: await _headers(),
        body: jsonEncode({'seenCardIds': seenCardIds}),
      ),
    );
  }

  /// [captureXp] maps instanceId → total XP earned from captures.
  /// [bonusXp] maps instanceId → bonus XP (deprecated, now part of cardXp).
  /// [cardXp] is the new detailed per-source XP breakdown keyed by instanceId.
  Future<Map<String, dynamic>> postMatchResult(
    String outcome, {
    Map<int, int> captureXp = const {},
    Map<int, int> bonusXp = const {},
    Map<int, Map<String, dynamic>>? cardXp,
    List<Map<String, dynamic>> capturedCards = const [],
  }) async {
    final baseUrl = await baseUrlProvider();
    // jsonEncode requires string keys — convert int-keyed maps explicitly
    final captureXpStr = <String, int>{};
    for (final e in captureXp.entries) {
      captureXpStr[e.key.toString()] = e.value;
    }
    final bonusXpStr = <String, int>{};
    for (final e in bonusXp.entries) {
      bonusXpStr[e.key.toString()] = e.value;
    }
    final cardXpStr = <String, Map<String, dynamic>>{};
    if (cardXp != null) {
      for (final e in cardXp.entries) {
        cardXpStr[e.key.toString()] = e.value;
      }
    }
    final body = <String, dynamic>{
      'outcome': outcome,
      'captureXp': captureXpStr,
      'bonusXp': bonusXpStr,
    };
    if (cardXpStr.isNotEmpty) {
      body['cardXp'] = cardXpStr;
    }
    if (capturedCards.isNotEmpty) {
      body['capturedCards'] = capturedCards;
      print('[CAPTURE] apiClient sending capturedCards: $capturedCards');
    }
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/match-result'),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<List<dynamic>> getCardGrowth() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/me/cards'), headers: await _headers()),
    );
    return result as List<dynamic>;
  }

  Future<void> putCardGrowth(List<Map<String, dynamic>> cards) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.put(
        Uri.parse('$baseUrl/me/cards'),
        headers: await _headers(),
        body: jsonEncode({'cards': cards}),
      ),
    );
  }

  Future<Map<String, dynamic>> postEvolve(String cardId, String toId, {int? instanceId}) async {
    final baseUrl = await baseUrlProvider();
    final body = <String, dynamic>{'cardId': cardId, 'toId': toId};
    if (instanceId != null) body['instanceId'] = instanceId;
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/evolve'),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<List<dynamic>> getDecks() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/decks'), headers: await _headers()),
    );
    return result as List<dynamic>;
  }

  Future<Map<String, dynamic>> putDeck(Map<String, dynamic> deckJson) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.put(
        Uri.parse('$baseUrl/decks'),
        headers: await _headers(),
        body: jsonEncode(deckJson),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<void> activateDeck(String deckId) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(Uri.parse('$baseUrl/decks/$deckId/activate'), headers: await _headers()),
    );
  }

  Future<void> deleteDeck(String deckId) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.delete(Uri.parse('$baseUrl/decks/$deckId'), headers: await _headers()),
    );
  }

  /// Today's Poké Mart singles lineup (EST-anchored, same for every player
  /// until the next midnight-EST rollover).
  Future<Map<String, dynamic>> getDailyShop() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/shop/today'), headers: await _headers()),
    );
    return result as Map<String, dynamic>;
  }

  /// The player's unopened item inventory (e.g. booster packs).
  Future<List<dynamic>> getInventory() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/me/inventory'), headers: await _headers()),
    );
    return (result as Map<String, dynamic>)['items'] as List<dynamic>;
  }

  /// Buy an item into inventory (deducts money server-side) without opening it.
  Future<Map<String, dynamic>> buyInventoryItem(String itemId, int price) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/inventory/buy'),
        headers: await _headers(),
        body: jsonEncode({'itemId': itemId, 'price': price}),
      ),
    );
    return result as Map<String, dynamic>;
  }

  /// Consume (open) one unit of an inventory item.
  Future<void> consumeInventoryItem(String itemId) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/inventory/consume'),
        headers: await _headers(),
        body: jsonEncode({'itemId': itemId}),
      ),
    );
  }

  Future<Map<String, dynamic>> getGifts() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/me/gifts'), headers: await _headers()),
    );
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> claimGift(int giftId) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.post(Uri.parse('$baseUrl/me/gifts/$giftId/claim'), headers: await _headers()),
    );
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> claimStarterDeck(List<Map<String, dynamic>> cards) async {
    final baseUrl = await baseUrlProvider();
    // Extract plain card IDs for backward compat with older servers
    final cardIds = cards.map((c) => c['cardId'] as String).toList();
    final result = await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/claim-starter'),
        headers: await _headers(),
        body: jsonEncode({
          'cards': cards,       // new format: [{cardId, shiny}]
          'cardIds': cardIds,   // old format: [string, ...]
        }),
      ),
    );
    return result as Map<String, dynamic>;
  }

  Future<List<dynamic>> getChat() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/chat'), headers: await _headers(authorized: false)),
    );
    return result as List<dynamic>;
  }

  Future<void> postChat(String text, String sender) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(
        Uri.parse('$baseUrl/chat'),
        headers: await _headers(),
        body: jsonEncode({'text': text, 'sender': sender}),
      ),
    );
  }

  Future<bool> checkTrainerName(String name) async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(
        Uri.parse('$baseUrl/me/check-name?name=${Uri.encodeComponent(name)}'),
        headers: await _headers(),
      ),
    );
    return (result as Map<String, dynamic>)['available'] == true;
  }

  Future<List<int>> getFavorites() async {
    final baseUrl = await baseUrlProvider();
    final result = await _send(
      () async => http.get(Uri.parse('$baseUrl/me/favorites'), headers: await _headers()),
    );
    // Returns List of {instanceId, cardId} objects or List<int> from PUT response
    if (result is List) {
      if (result.isEmpty) return [];
      if (result.first is int) return result.cast<int>();
      if (result.first is Map) {
        return (result as List<dynamic>)
            .map((f) => (f['instanceId'] as int?) ?? 0)
            .where((id) => id > 0)
            .toList();
      }
    }
    return [];
  }

  Future<void> putFavorites(List<int> instanceIds) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.put(
        Uri.parse('$baseUrl/me/favorites'),
        headers: await _headers(),
        body: jsonEncode({'instanceIds': instanceIds}),
      ),
    );
  }

  Future<void> sellCard(int instanceId, int price) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.post(
        Uri.parse('$baseUrl/me/sell-card'),
        headers: await _headers(),
        body: jsonEncode({'instanceId': instanceId, 'price': price}),
      ),
    );
  }

  Future<void> deleteCharacter(String trainerName) async {
    final baseUrl = await baseUrlProvider();
    await _send(
      () async => http.delete(
        Uri.parse('$baseUrl/me/character'),
        headers: await _headers(),
        body: jsonEncode({'trainerName': trainerName}),
      ),
    );
  }
}
