import '../models/deck.dart';
import '../models/player_profile.dart';
import 'api_client.dart';

class DeckService {
  DeckService(this._apiClient);

  final ApiClient _apiClient;

  /// Returns a validation message, or null if the card selection is a legal deck.
  String? validateDeck(List<String> cardIds) {
    if (cardIds.length != kDeckSize) {
      return 'A deck must have exactly $kDeckSize cards (currently ${cardIds.length}).';
    }
    return null;
  }

  Future<void> saveDeck(PlayerProfile profile, Deck deck) async {
    final response = await _apiClient.putDeck(deck.toJson());
    final saved = Deck.fromJson(response);

    final index = profile.decks.indexWhere((d) => d.id == deck.id);
    if (index >= 0) {
      profile.decks[index] = saved;
    } else {
      profile.decks.add(saved);
    }
    if (saved.isDefault) {
      profile.defaultDeckId = saved.id;
    }
  }

  Future<void> deleteDeck(PlayerProfile profile, String deckId) async {
    await _apiClient.deleteDeck(deckId);
    profile.decks.removeWhere((d) => d.id == deckId);
    if (profile.defaultDeckId == deckId) {
      profile.defaultDeckId = null;
    }
  }

  Future<void> setDefaultDeck(PlayerProfile profile, String deckId) async {
    await _apiClient.activateDeck(deckId);
    profile.defaultDeckId = deckId;
  }
}
